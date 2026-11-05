#!/usr/bin/env bash
# openbao.sh — the secret-store adapter for OpenBao, the local cluster secret
# store (ADR-0026). It mimics a cloud secret store: it runs OUTSIDE the cluster,
# beside Zot, on the environment's container network and its own volume; it
# exists before the cluster, outlives `down`, and keeps every secret the
# operator gave it. Every secret-store adapter has the same functions:
#
#   secret_store_up                 EMIT: make the store (container, first-time
#                                   init, policies, KV v2, transit); idempotent
#   secret_store_prelude            EMIT: define bao() for the run sheet: one CLI
#                                   call in the store container as the driver
#                                   (token from driver.token, via the environment)
#   secret_store_bind_cluster       EMIT: let the cluster's ESO authenticate to
#                                   the store (Kubernetes auth + the ESO role)
#   secret_put <path> <VAR_NAME>    EMIT (one line, no newline): write
#                                   $VAR_NAME's value at <path>; the value goes
#                                   on stdin, the token through the environment;
#                                   the run sheet names the variable
#   secret_get <path>               EMIT: print the value at <path> on stdout,
#                                   for a pipe into its consumer
#   secret_exists <path>            EMIT: succeed if <path> holds a value
#   secret_store_ca_up <host>       EMIT: a CA in the store (PKI engine, root
#                                   made once); the CA certificate to
#                                   <dir>/ca.crt (ADR-0036). Phase 10: the CA
#                                   exists before the cluster, as the store does
#   secret_store_client_cert_up <role> <name> <dir>
#                                   EMIT: a PKI role that signs client
#                                   certificates for <name> only, and one such
#                                   certificate in <dir> (tls.crt, tls.key,
#                                   ca.crt; 0600), valid 30 days, issued anew
#                                   on every run
#   secret_store_pki_up <host>      EMIT: the PKI role `portal`, which signs
#                                   server certificates for <host> and the
#                                   names under it, and the auth role
#                                   cert-manager logs in with
#   secret_store_check              GENERATOR: unsealed, driver token valid,
#                                   transit round trip
#   secret_store_has <path>         GENERATOR: does <path> hold a value?
#   secret_store_pki_check <host> [run_dir]
#                                   GENERATOR: CA, role and auth role exist;
#                                   names the host run sheet that trusts the CA
#                                   on the operator's machine
#   secret_store_host_steps         print the host run sheet's part that trusts
#                                   the CA on the operator's machine (Q180)
#   secret_store_client_cert_check <dir>
#                                   GENERATOR: the client certificate in <dir>
#                                   exists and is valid for at least one day
#
# Trust on the driver side, all under $BRZL_SECRET_STORE_DIR (gitignored, 600):
#   seal.key      32 bytes (hex); the static seal's key. Lost = the store is
#                 lost: purge it (docs/LOCAL.md) and start again.
#   driver.token  the operator's token (policy `driver`); made once at init,
#                 when the root token is revoked.
#   recovery.key  the init recovery key, to mint a new root token if driver.token
#                 is lost (bao operator generate-root).
#
# The `bao` CLI runs inside the store's container (docker exec), so the only
# host tool is the docker CLI. Pinned image: openbao/openbao:2.7.1 (storage
# "pebbledb"; the `file` backend is gone since 2.7). Sourced by phase scripts
# through phase_init, never run on its own. Inputs: BRZL_OPENBAO_*,
# BRZL_SECRET_STORE_DIR, BRZL_DOCKER_NETWORK, BRZL_K3D_CLUSTER. The sourcing
# phase script sets repo_root.
# shellcheck disable=SC2154,SC2016  # repo_root from the sourcer; emitted text names variables

openbao_policy_driver='path "secret/*"               { capabilities = ["create", "read", "update", "delete", "list"] }
path "transit/encrypt/*"      { capabilities = ["update"] }
path "transit/decrypt/*"      { capabilities = ["update"] }
path "auth/kubernetes/config" { capabilities = ["create", "update", "read"] }
path "auth/kubernetes/role/*" { capabilities = ["create", "update", "read"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "sys/mounts"             { capabilities = ["read"] }
path "sys/mounts/pki"         { capabilities = ["create", "update", "read"] }
path "pki/*"                  { capabilities = ["create", "read", "update", "delete", "list"] }'
openbao_policy_eso_reader='path "secret/data/*"     { capabilities = ["read"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }'
# cert-manager may only ask the portal role to sign (ADR-0036).
openbao_policy_pki_issuer='path "pki/sign/portal" { capabilities = ["update"] }'

# openbao_config — the server config (JSON: the image writes BAO_LOCAL_CONFIG to
# /openbao/config/local.json). The seal key comes from the container's
# environment (env://), never from a mounted file: a bind-mounted 600 file is
# unreadable to the image's unprivileged user. The audit device is declared here
# too (OpenBao 2.3+): a file in /openbao/logs, a host directory (ADR-0027).
openbao_config() {
  printf '%s' '{"storage":{"pebbledb":{"path":"/openbao/file"}},"listener":{"tcp":{"address":"0.0.0.0:8200","tls_disable":true}},"seal":{"static":{"current_key_id":"brzl-1","current_key":"env://BAO_SEAL_KEY"}},"ui":false,"audit":{"brzl":{"type":"file","path":"brzl/","options":{"file_path":"/openbao/logs/audit.log"}}}}'
}

secret_store_prelude() {
  printf '# bao <args…>: one CLI call in the store container, as the driver (token via the environment)\n'
  printf 'bao() { BAO_TOKEN="$(<%q)" docker exec -i -e BAO_TOKEN -e BAO_ADDR=http://127.0.0.1:8200 %q bao "$@"; }\n' \
    "$BRZL_SECRET_STORE_DIR/driver.token" "$BRZL_OPENBAO_NAME"
}

# openbao_bao — the name the emitted lines call (defined by secret_store_prelude).
openbao_bao() { printf 'bao'; }

# openbao_run_bao <args…> — the same call, run here (for generators). No -i:
# a generator never feeds data in, and an inherited stdin would be swallowed.
openbao_run_bao() {
  BAO_TOKEN="$(<"$repo_root/$BRZL_SECRET_STORE_DIR/driver.token")" \
    docker exec -e BAO_TOKEN -e BAO_ADDR=http://127.0.0.1:8200 "$BRZL_OPENBAO_NAME" bao "$@"
}

# openbao_state <config_sha> — absent | current | stale, for the container.
openbao_state() {
  local want="$1" have
  if ! have="$(docker inspect --format '{{ index .Config.Labels "dev.brzl.openbao-config-sha256" }}' \
      "$BRZL_OPENBAO_NAME" 2>/dev/null)"; then
    printf absent
  elif [[ "$have" == "$want" ]]; then
    printf current
  else
    printf stale
  fi
}

secret_store_up() {
  local name="$BRZL_OPENBAO_NAME" dir="$BRZL_SECRET_STORE_DIR" sha state config
  config="$(openbao_config)"
  sha="$(sha256sum <<< "$config")"; sha="${sha%% *}"
  state="$(openbao_state "$sha")"
  printf '{ # the seal key of the secret store: made once, kept in %s (lost key = lost store)\n' "$dir"
  printf '  mkdir -p %q\n' "$dir"
  printf '  [[ -s %q ]] || (umask 077; openssl rand -hex 32 > %q)\n' "$dir/seal.key" "$dir/seal.key"
  printf '}\n'
  printf '{ # the store'"'"'s audit log goes to the log store'"'"'s directory (ADR-0027); the collector beside the cluster reads it\n'
  printf '  mkdir -p %q\n' "$BRZL_LOG_STORE_DIR/openbao-audit"
  printf '}\n'
  if [[ "$state" == current ]]; then
    printf '{ # OpenBao secret store: its config is current; make sure it runs\n'
    printf '  docker start %q\n' "$name"
    printf '}\n'
  else
    printf '{ # OpenBao secret store, outside the cluster (ADR-0026); its data outlives the cluster\n'
    printf '  docker volume create %q\n' "$BRZL_OPENBAO_VOLUME"
    [[ "$state" == stale ]] && printf '  docker rm -f %q   # its config changed; the data volume stays\n' "$name"
    printf '  BAO_SEAL_KEY="$(<%q)" BAO_LOCAL_CONFIG='"'"'%s'"'"' \\\n' "$dir/seal.key" "$config"
    printf '    docker run -d --name %q --network %q --restart unless-stopped \\\n' "$name" "$BRZL_DOCKER_NETWORK"
    printf '    --label %q \\\n' "dev.brzl.openbao-config-sha256=$sha"
    printf '    -e BAO_SEAL_KEY -e BAO_LOCAL_CONFIG -p %q -v %q \\\n' \
      "127.0.0.1:$BRZL_OPENBAO_PORT:8200" "$BRZL_OPENBAO_VOLUME:/openbao/file"
    printf '    -v %q \\\n' "$repo_root/$BRZL_LOG_STORE_DIR/openbao-audit:/openbao/logs"
    printf '    %q server\n' "$BRZL_OPENBAO_IMAGE"
    printf '}\n'
  fi
  printf '{ # wait until the store answers (sealed or not)\n'
  printf '  for _ in $(seq 30); do curl -fsS -o /dev/null "http://127.0.0.1:%s/v1/sys/health?sealedcode=200&uninitcode=200" && break; sleep 2; done\n' \
    "$BRZL_OPENBAO_PORT"
  printf '}\n'
  # Initialize once. Whether the volume already holds an initialized store is
  # known only at run time (an absent container tells nothing), so the group
  # reads the status there. An initialized store with no driver token cannot
  # converge: it stops, and the operator purges the store.
  printf '{ # OpenBao, first start only: initialize, the policies, KV v2 at secret/, transit; the driver token; root revoked\n'
  printf '  if [[ "$(docker exec -e BAO_ADDR=http://127.0.0.1:8200 %q bao status -format=json | jq -r .initialized)" == true ]]; then\n' "$name"
  printf '    [[ -s %q ]] \\\n' "$dir/driver.token"
  printf "      || error 3 'the store is initialized but %s is missing: purge the store (docs/LOCAL.md) and run again'\n" "$dir/driver.token"
  printf '  else\n'
  printf '    init="$(docker exec -e BAO_ADDR=http://127.0.0.1:8200 %q bao operator init -recovery-shares=1 -recovery-threshold=1 -format=json)" \\\n' "$name"
  printf "      || error 3 'OpenBao did not initialize; see: docker logs %s'\n" "$name"
  printf '    (umask 077; jq -r '\''.recovery_keys_b64[0]'\'' <<< "$init" > %q)\n' "$dir/recovery.key"
  printf '    root="$(jq -r .root_token <<< "$init")"\n'
  printf '    root_bao() { BAO_TOKEN="$root" docker exec -i -e BAO_TOKEN -e BAO_ADDR=http://127.0.0.1:8200 %q bao "$@"; }\n' "$name"
  printf "    root_bao policy write driver - <<'EOF'\n%s\nEOF\n" "$openbao_policy_driver"
  printf "    root_bao policy write eso-reader - <<'EOF'\n%s\nEOF\n" "$openbao_policy_eso_reader"
  printf "    root_bao policy write pki-issuer - <<'EOF'\n%s\nEOF\n" "$openbao_policy_pki_issuer"
  printf '    root_bao secrets enable -version=2 -path=secret kv\n'
  printf '    root_bao secrets enable transit\n'
  printf '    root_bao write -f transit/keys/%q\n' "$BRZL_OPENBAO_TRANSIT_KEY"
  printf '    root_bao auth enable kubernetes\n'
  printf '    (umask 077; root_bao token create -policy=driver -orphan -field=token > %q)\n' "$dir/driver.token"
  printf '    root_bao token revoke -self\n'
  printf '    unset root init; unset -f root_bao\n'
  printf '  fi\n'
  printf '}\n'
}

# secret_store_bind_cluster <run_dir> — Kubernetes auth for ESO: a reviewer
# service account (TokenReview) with a long-lived token, the auth config with
# the cluster's CA and API address as the store container reaches it, and the
# role ESO logs in with. Idempotent: every write replaces the same config.
secret_store_bind_cluster() {
  local api="https://k3d-$BRZL_K3D_CLUSTER-server-0:6443"
  printf '{ # the store verifies ESO tokens with the cluster: a reviewer service account and its token\n'
  printf "  kubectl apply -f - <<'EOF'\n"
  cat <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openbao-auth
  namespace: brzl-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: brzl-openbao-auth
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: openbao-auth
    namespace: brzl-system
---
apiVersion: v1
kind: Secret
metadata:
  name: openbao-auth-token
  namespace: brzl-system
  annotations:
    kubernetes.io/service-account.name: openbao-auth
type: kubernetes.io/service-account-token
EOF
  printf 'EOF\n'
  printf '  for _ in $(seq 15); do [[ -n "$(kubectl -n brzl-system get secret openbao-auth-token -o jsonpath='\''{.data.token}'\'')" ]] && break; sleep 2; done\n'
  printf '}\n'
  printf '{ # Kubernetes auth config in the store (reviewer token and CA on stdin, as JSON), and the ESO role\n'
  printf '  kubectl -n brzl-system get secret openbao-auth-token -o json \\\n'
  printf '    | jq '\''{kubernetes_host: %s, token_reviewer_jwt: (.data.token | @base64d), kubernetes_ca_cert: (.data["ca.crt"] | @base64d)}'\'' \\\n' \
    "$(printf '"%s"' "$api")"
  printf '    | %s write auth/kubernetes/config -\n' "$(openbao_bao)"
  printf '  %s write auth/kubernetes/role/eso \\\n' "$(openbao_bao)"
  printf '    bound_service_account_names=brzl-secrets-reader bound_service_account_namespaces=external-secrets \\\n'
  printf '    token_policies=eso-reader token_ttl=1h audience=openbao\n'
  printf '}\n'
}

# The PKI engine is the CA of local-ca mode (ADR-0036): the root is made once
# and outlives the cluster, like the rest of the store. The CA certificate
# (public) is written beside the trust files, for the operator to trust once
# and for the checks.
secret_store_ca_up() {
  local host="$1" dir="$BRZL_SECRET_STORE_DIR" bao
  bao="$(openbao_bao)"
  printf '{ # the CA in the store (local-ca, ADR-0036): the PKI engine and the root, made once\n'
  printf '  %s secrets list -format=json | jq -e '"'"'."pki/"'"'"' >/dev/null 2>&1 \\\n' "$bao"
  printf '    || %s secrets enable -max-lease-ttl=87600h pki\n' "$bao"
  printf '  %s read -field=certificate pki/cert/ca >/dev/null 2>&1 \\\n' "$bao"
  printf '    || %s write -field=serial_number pki/root/generate/internal common_name=%q ttl=87600h key_type=ec key_bits=256 >/dev/null\n' \
    "$bao" "brzl CA for $host"
  printf '  %s read -field=certificate pki/cert/ca > %q\n' "$bao" "$dir/ca.crt"
  printf '}\n'
}

# A client certificate for a program outside the cluster (BACKLOG 4a): today
# the collector beside a local cluster, which proves itself to the in-cluster
# collector's OTLP receiver with it. The role signs client certificates for
# that one name and nothing else; no auth role names it, so only the driver
# can ask it. The certificate is issued anew on every run of the phase and
# lasts 30 days; the collector reads its files again on a timer. The issued
# JSON stays in a shell variable; only its parts reach the files (umask 077).
secret_store_client_cert_up() {
  local role="$1" name="$2" dir="$3" bao
  bao="$(openbao_bao)"
  printf '{ # a client certificate for %s from the store'"'"'s CA (PKI role %s: client only, this name only, 30 days)\n' "$name" "$role"
  printf '  %s write pki/roles/%s allowed_domains=%q allow_bare_domains=true enforce_hostnames=false \\\n' "$bao" "$role" "$name"
  printf '    server_flag=false client_flag=true max_ttl=720h key_type=ec key_bits=256 >/dev/null\n'
  printf '  mkdir -p %q\n' "$dir"
  printf '  issued="$(%s write -format=json pki/issue/%s common_name=%q ttl=720h)" \\\n' "$bao" "$role" "$name"
  printf '    && (umask 077\n'
  printf '        jq -r .data.certificate <<< "$issued" > %q\n' "$dir/tls.crt"
  printf '        jq -r .data.private_key <<< "$issued" > %q\n' "$dir/tls.key"
  printf '        jq -r .data.issuing_ca <<< "$issued" > %q)\n' "$dir/ca.crt"
  printf '  unset issued\n'
  printf '}\n'
}

# The portal role signs server certificates only, for the portal's host and
# the names under it (the admin portal; the log intake, BACKLOG 4a). It must
# not sign client certificates: the OTLP receiver trusts any client
# certificate from this CA, so only the client-only roles may make one.
# Certificates last at most 90 days (cert-manager renews them).
secret_store_pki_up() {
  local host="$1" bao
  bao="$(openbao_bao)"
  printf '{ # the PKI role portal (server certificates only) and the auth role cert-manager logs in with\n'
  printf '  %s write pki/roles/portal allowed_domains=%q allow_bare_domains=true allow_subdomains=true \\\n' "$bao" "$host"
  printf '    server_flag=true client_flag=false max_ttl=2160h key_type=ec key_bits=256 >/dev/null\n'
  printf '  %s write auth/kubernetes/role/cert-manager \\\n' "$bao"
  printf '    bound_service_account_names=brzl-pki-client bound_service_account_namespaces=cert-manager \\\n'
  printf '    token_policies=pki-issuer token_ttl=1h audience=openbao\n'
  printf '}\n'
}

secret_store_client_cert_check() {
  local dir="$repo_root/$1" left
  if ! openssl x509 -in "$dir/tls.crt" -noout -checkend 86400 >/dev/null 2>&1 || [[ ! -s "$dir/tls.key" ]]; then
    printf 'fix: no valid client certificate in %s (absent, or less than one day left); run the 10-substrate phase again\n' "$1" >&2
    return 1
  fi
  left="$(openssl x509 -in "$dir/tls.crt" -noout -enddate | sed 's/^notAfter=//')"
  printf 'the client certificate in %s is valid until %s\n' "$1" "$left"
}

# secret_store_host_steps — print the part of the host run sheet (phase 10,
# Q180) that makes the operator's machine trust the store's CA, in local-ca
# mode. The commands depend on the system; the Linux ones were tested in
# containers (docs/LOCAL.md, "Steps on your machine"). Each step is added
# only when it is not done; the sheet runs on the host, so it can tell. On
# Linux, browsers keep their own store (NSS): the CA goes there too when
# certutil and the user's NSS database exist.
secret_store_host_steps() {
  local ca="$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt" name qca dest update family
  name="brzl-$BRZL_PORTAL_HOST"
  qca="$(printf '%q' "$ca")"
  # The CA is made when phase 10 runs, after this is emitted: the sheet reads
  # its name and its fingerprint when it runs (OpenSSL and LibreSSL print
  # both alike). The fingerprint tells a new CA from an old one of the same
  # name, which a purge of the store and a new bootstrap leave in a trust
  # store (found 2026-11-05).
  printf '# trust the CA of the store, %s\n' "$BRZL_SECRET_STORE_DIR/ca.crt"
  printf 'cn="$(openssl x509 -in %s -noout -subject 2>/dev/null | sed -n '"'"'s/.*CN *= *//p'"'"')"\n' "$qca"
  printf 'fp="$(openssl x509 -in %s -noout -fingerprint -sha256 2>/dev/null | sed '"'"'s/.*=//; s/://g'"'"')"\n' "$qca"
  printf 'if [[ ! -s %s ]]; then\n' "$qca"
  printf '  printf '"'"'no CA certificate at %%s yet: run phase 10 first\\n'"'"' %s\n' "$qca"
  printf 'elif [[ "$(uname)" == Darwin ]]; then\n'
  printf '  security find-certificate -a -c "$cn" -Z ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -q "SHA-256 hash: $fp" \\\n'
  printf '    || steps+=(%s)\n' "$(squote "security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db $qca")"
  printf 'else\n'
  printf '  [[ -r /etc/os-release ]] && . /etc/os-release\n'
  printf '  case " ${ID:-} ${ID_LIKE:-} " in\n'
  for family in debian fedora suse; do
    case "$family" in
      debian) printf '    *" debian "*|*" ubuntu "*|*" alpine "*)\n'
              dest="/usr/local/share/ca-certificates/$name.crt"; update='sudo update-ca-certificates' ;;
      fedora) printf '    *" fedora "*|*" rhel "*|*" centos "*)\n'
              dest="/etc/pki/ca-trust/source/anchors/$name.crt"; update='sudo update-ca-trust' ;;
      suse)   printf '    *" suse "*|*" opensuse "*)\n'
              dest="/etc/pki/trust/anchors/$name.crt"; update='sudo update-ca-certificates' ;;
    esac
    printf '      [[ "$(cat %s 2>/dev/null)" == "$(cat %s)" ]] \\\n' "$dest" "$qca"
    printf '        || steps+=(%s %s) ;;\n' "$(squote "sudo cp $qca $dest")" "$(squote "$update")"
  done
  printf '    *" arch "*)\n'
  printf '      trust list 2>/dev/null | grep -qF "$cn" || steps+=(%s) ;;\n' "$(squote "sudo trust anchor --store $qca")"
  printf '    *) printf '"'"'no CA step for this system (%%s): see docs/LOCAL.md, "Steps on your machine"\\n'"'"' "${ID:-unknown}" ;;\n'
  printf '  esac\n'
  printf '  if command -v certutil >/dev/null 2>&1 && [[ -d "$HOME/.pki/nssdb" ]] \\\n'
  printf '      && [[ "$(certutil -d "sql:$HOME/.pki/nssdb" -L -n %q -a 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed '"'"'s/.*=//; s/://g'"'"')" != "$fp" ]]; then\n' "$name"
  printf '    steps+=(%s)\n' "$(squote "certutil -d \"sql:\$HOME/.pki/nssdb\" -A -t C,, -n $name -i $qca")"
  printf '  fi\n'
  printf 'fi\n'
}

secret_store_pki_check() {
  local host="$1" ca="$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt" caps
  caps="$(openbao_run_bao token capabilities pki/roles/portal 2>/dev/null)"
  if [[ "$caps" != *update* ]]; then
    printf 'fix: the driver token predates the PKI engine (no update on pki/roles/portal): purge the store (docs/LOCAL.md) and run again\n' >&2
    return 1
  fi
  if ! openbao_run_bao read -field=certificate pki/cert/ca >/dev/null 2>&1 \
      || ! openbao_run_bao read auth/kubernetes/role/cert-manager >/dev/null 2>&1; then
    printf 'fix: the store has no CA or no cert-manager auth role; run the 10-substrate and 25-bootstrap phases again\n' >&2
    return 1
  fi
  if [[ "$(openbao_run_bao read -field=client_flag pki/roles/portal 2>/dev/null)" != false ]]; then
    printf 'fix: the PKI role portal is absent or also signs client certificates; run the 25-bootstrap phase again\n' >&2
    return 1
  fi
  if [[ ! -s "$ca" ]]; then
    printf 'fix: no CA certificate at %s; run the 10-substrate phase again\n' "$ca" >&2
    return 1
  fi
  printf 'the store is a CA for %s (PKI role portal, server certificates only; cert-manager may ask it to sign); CA certificate: %s\n' \
    "$host" "$BRZL_SECRET_STORE_DIR/ca.crt"
  # Trust on the operator's machine can be checked only there. In kiesei
  # (BRZL_HOST_OS is set) the check names the host run sheet as
  # information; on macOS it reads the login keychain. The CA was made once,
  # under the host name of that time: its subject is read from the file.
  if [[ -n "${BRZL_HOST_OS:-}" ]]; then
    printf 'whether your machine trusts this CA is in the host run sheet (10-host.sh, docs/LOCAL.md)\n'
    return 0
  fi
  local cn fp
  cn="$(openssl x509 -in "$ca" -noout -subject -nameopt sep_multiline,utf8 2>/dev/null | sed -n 's/^ *CN=//p')"
  fp="$(openssl x509 -in "$ca" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//; s/://g')"
  if [[ "$(uname)" == Darwin && -n "$cn" && -n "$fp" ]] \
      && security find-certificate -a -c "$cn" -Z ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -q "SHA-256 hash: $fp"; then
    return 0
  fi
  operator_step "so that your machine trusts the CA of $host (skip if done), the host run sheet does it:" \
    "bash ${2:-var/run/<env>/current}/10-host.sh"
}

secret_put() {
  local path="$1" var="$2"
  printf 'printf '\''%%s'\'' "$%s" | %s kv put -mount=secret %q value=-' "$var" "$(openbao_bao)" "$path"
}

# secret_put_file <path> <file> — the file's bytes become the value. The file
# goes on stdin: `bao` in the run sheet is a call into the store's container,
# which cannot see the driver's files, and nothing enters argv.
secret_put_file() {
  printf '%s kv put -mount=secret %q value=- < %q' "$(openbao_bao)" "$1" "$2"
}

secret_get() {
  printf '%s kv get -mount=secret -field=value %q' "$(openbao_bao)" "$1"
}

secret_exists() {
  printf '%s kv get -mount=secret -field=value %q >/dev/null 2>&1' "$(openbao_bao)" "$1"
}

secret_store_check() {
  local status plain cipher back
  if ! status="$(docker exec -e BAO_ADDR=http://127.0.0.1:8200 "$BRZL_OPENBAO_NAME" bao status -format=json 2>&1)"; then
    printf 'fix: the secret store %s does not answer: %s; see: docker logs %s\n' \
      "$BRZL_OPENBAO_NAME" "$status" "$BRZL_OPENBAO_NAME" >&2
    return 1
  fi
  if [[ "$(jq -r '.initialized' <<< "$status")" != true || "$(jq -r '.sealed' <<< "$status")" != false ]]; then
    printf 'fix: the secret store is not initialized or is sealed (%s); see: docker logs %s\n' \
      "$(jq -c '{initialized,sealed}' <<< "$status")" "$BRZL_OPENBAO_NAME" >&2
    return 1
  fi
  if [[ ! -s "$repo_root/$BRZL_SECRET_STORE_DIR/driver.token" ]] \
      || ! openbao_run_bao token lookup -format=json >/dev/null 2>&1; then
    printf 'fix: no valid driver token in %s; mint one with recovery.key (docs/LOCAL.md) or purge the store\n' \
      "$BRZL_SECRET_STORE_DIR" >&2
    return 1
  fi
  plain="$(openssl rand -hex 8 | base64)"
  cipher="$(openbao_run_bao write -field=ciphertext "transit/encrypt/$BRZL_OPENBAO_TRANSIT_KEY" "plaintext=$plain" 2>/dev/null)"
  back="$(openbao_run_bao write -field=plaintext "transit/decrypt/$BRZL_OPENBAO_TRANSIT_KEY" "ciphertext=$cipher" 2>/dev/null)"
  if [[ -z "$cipher" || "$back" != "$plain" ]]; then
    printf 'fix: transit key %s did not round-trip; see: docker logs %s\n' "$BRZL_OPENBAO_TRANSIT_KEY" "$BRZL_OPENBAO_NAME" >&2
    return 1
  fi
  printf 'secret store %s is unsealed, the driver token is valid, transit %s round-trips\n' \
    "$BRZL_OPENBAO_NAME" "$BRZL_OPENBAO_TRANSIT_KEY"
}

secret_store_has() {
  openbao_run_bao kv get -mount=secret -field=value "$1" >/dev/null 2>&1
}
