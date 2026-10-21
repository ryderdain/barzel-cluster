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
#   secret_store_pki_up <host>      EMIT: a CA in the store (PKI engine, root
#                                   made once), a role that signs <host>, and
#                                   the auth role cert-manager logs in with;
#                                   the CA certificate to <dir>/ca.crt (ADR-0036)
#   secret_store_check              GENERATOR: unsealed, driver token valid,
#                                   transit round trip
#   secret_store_has <path>         GENERATOR: does <path> hold a value?
#   secret_store_pki_check <host>   GENERATOR: CA, role and auth role exist;
#                                   prints how to trust the CA on the operator's
#                                   machine (checked only when run there)
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
# and outlives the cluster, like the rest of the store. The role allows the
# portal's host and names under it; certificates last at most 90 days
# (cert-manager renews them). The CA certificate (public) is written beside
# the trust files, for the operator to trust once and for the checks.
secret_store_pki_up() {
  local host="$1" dir="$BRZL_SECRET_STORE_DIR" bao
  bao="$(openbao_bao)"
  printf '{ # PKI in the store (local-ca, ADR-0036): the engine, the root CA (once), the portal role, the issuer auth role\n'
  printf '  %s secrets list -format=json | jq -e '"'"'."pki/"'"'"' >/dev/null 2>&1 \\\n' "$bao"
  printf '    || %s secrets enable -max-lease-ttl=87600h pki\n' "$bao"
  printf '  %s read -field=certificate pki/cert/ca >/dev/null 2>&1 \\\n' "$bao"
  printf '    || %s write -field=serial_number pki/root/generate/internal common_name=%q ttl=87600h key_type=ec key_bits=256 >/dev/null\n' \
    "$bao" "brzl CA for $host"
  printf '  %s write pki/roles/portal allowed_domains=%q allow_bare_domains=true allow_subdomains=true \\\n' "$bao" "$host"
  printf '    max_ttl=2160h key_type=ec key_bits=256 >/dev/null\n'
  printf '  %s write auth/kubernetes/role/cert-manager \\\n' "$bao"
  printf '    bound_service_account_names=brzl-pki-client bound_service_account_namespaces=cert-manager \\\n'
  printf '    token_policies=pki-issuer token_ttl=1h audience=openbao\n'
  printf '  %s read -field=certificate pki/cert/ca > %q\n' "$bao" "$dir/ca.crt"
  printf '}\n'
}

secret_store_pki_check() {
  local host="$1" ca="$repo_root/$BRZL_SECRET_STORE_DIR/ca.crt" caps
  caps="$(openbao_run_bao token capabilities pki/roles/portal 2>/dev/null)"
  if [[ "$caps" != *update* ]]; then
    printf 'fix: the driver token predates the PKI engine (no update on pki/roles/portal): purge the store (docs/LOCAL.md) and run again\n' >&2
    return 1
  fi
  if ! openbao_run_bao read -field=certificate pki/cert/ca >/dev/null 2>&1 \
      || ! openbao_run_bao read pki/roles/portal >/dev/null 2>&1 \
      || ! openbao_run_bao read auth/kubernetes/role/cert-manager >/dev/null 2>&1; then
    printf 'fix: the store has no CA, portal role or cert-manager auth role; run the 25-bootstrap phase again\n' >&2
    return 1
  fi
  if [[ ! -s "$ca" ]]; then
    printf 'fix: no CA certificate at %s; run the 25-bootstrap phase again\n' "$ca" >&2
    return 1
  fi
  printf 'the store is a CA for %s (role portal; cert-manager may ask it to sign); CA certificate: %s\n' \
    "$host" "$BRZL_SECRET_STORE_DIR/ca.crt"
  # Trust on the operator's machine can be checked only there; from kiesei
  # the one-time step is printed for the operator's OS (BRZL_HOST_OS). The
  # CA was made once, under the host name of that time: its subject is read
  # from the file, not rebuilt from today's host.
  local cn
  cn="$(openssl x509 -in "$ca" -noout -subject -nameopt sep_multiline,utf8 2>/dev/null | sed -n 's/^ *CN=//p')"
  case "$(host_os)" in
    Darwin)
      if [[ "$(uname)" == Darwin && -n "$cn" ]] \
          && security find-certificate -c "$cn" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
        return 0
      fi
      operator_step "so that the browser trusts the CA of $host (skip if done):" \
        "security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db $BRZL_SECRET_STORE_DIR/ca.crt"
      ;;
    *)
      operator_step "so that the system trusts the CA of $host (skip if done; Debian/Ubuntu shown; Firefox keeps its own store):" \
        "sudo cp $BRZL_SECRET_STORE_DIR/ca.crt /usr/local/share/ca-certificates/brzl-$host.crt" \
        "sudo update-ca-certificates"
      ;;
  esac
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
