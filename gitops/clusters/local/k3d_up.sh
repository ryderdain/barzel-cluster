#!/usr/bin/env bash
# k3d_up.sh — EMIT the commands that stand up the local-dev (k3d) stack: a
# laptop k3s cluster running the CNPG + demo-app stack with NO AWS. Per the repo
# convention this is a mutating/action script — it only PRINTS commands. Review:
#
#   bash gitops/clusters/local/k3d_up.sh            # preview (default: up)
#   bash gitops/clusters/local/k3d_up.sh | bash     # run
#   bash gitops/clusters/local/k3d_up.sh down | bash # tear the local cluster down
#
#   bash gitops/clusters/local/k3d_up.sh --with-sso         # preview the SSO build
#   bash gitops/clusters/local/k3d_up.sh --with-sso | bash  # run it
#
# What plain `up` emits (&&-chained, fail-fast): create the k3d cluster (local-path
# is the built-in default StorageClass) → build the demo-app image and import it
# into the cluster (no registry, no ECR auth) → helm-install the CNPG + External
# Secrets operators from upstream charts → apply the local overlay
# (gitops/clusters/local) → wait for Postgres + demo-app. Images are upstream.
#
# `--with-sso` RECREATES the cluster with the SSO edge (docs/composed plan): host
# ports 443/80, the kube-API-server OIDC args, cert-manager + the FreeDNS DNS-01
# webhook for a trusted *.sso.barzel.sh wildcard, Dex (GitHub IdP), three
# per-host oauth2-proxies (operator/users tiers), and a lean Grafana+Prometheus.
# It folds in gitops/bootstrap/create_sso_secrets.sh, so the same one-time exports
# that script needs (GITHUB_CLIENT_ID/SECRET, OAUTH2_PROXY_CLIENT_SECRET) plus the
# FreeDNS cred (FREEDNS_USERNAME/PASSWORD) must be in the env. See docs/LOCAL.md.
#
# No `set -euo pipefail` (CLAUDE.md / BashPitfalls/105): the emit-time checks are
# explicit; the emitted stream is &&-chained and fails fast on the first error.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

# ---- args: [up|down] [--with-sso] -------------------------------------------
action=""
with_sso=0
for arg in "$@"; do
  case "$arg" in
    up | down) action="$arg" ;;
    --with-sso) with_sso=1 ;;
    *) printf 'error: unknown arg %q (use: [up|down] [--with-sso])\n' "$arg" >&2; exit 2 ;;
  esac
done
action="${action:-up}"

cluster="${K3D_CLUSTER:-brzl-local}"
tag="${DEMO_APP_LOCAL_TAG:-local}"
cnpg_chart_version="${CNPG_CHART_VERSION:-0.28.2}"
eso_chart_version="${ESO_CHART_VERSION:-0.10.7}"
certmgr_version="${CERT_MANAGER_VERSION:-v1.16.2}"
kps_version="${KPS_CHART_VERSION:-86.1.1}"

# SSO identity knobs (non-secret → expanded at emit time into the preview).
acme_email="${ACME_EMAIL:-ryder.dain@gmail.com}"
operator_email="${OPERATOR_EMAIL:-ryder.dain@gmail.com}"
acme_issuer="${ACME_ISSUER:-letsencrypt-staging}"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
overlay="${repo_root}/gitops/clusters/local"
sso="${overlay}/sso"
app_dir="${repo_root}/apps/demo-app"

if [[ "$action" == down ]]; then
  printf 'k3d cluster delete %s\n' "$cluster"
  exit 0
fi

for tool in k3d docker kubectl helm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: %s not found on PATH (prereqs: docker, k3d, kubectl, helm)\n' "$tool" >&2
    exit 1
  fi
done
if (( with_sso )) && ! command -v git >/dev/null 2>&1; then
  printf 'error: git not found on PATH (needed to fetch the FreeDNS webhook chart)\n' >&2
  exit 1
fi

# Build the demo-app for the host/k3d-node arch (k3d runs in the host's docker, so
# node arch == host arch). The Dockerfile defaults arm64 — override to match.
host_arch="$(uname -m)"
case "$host_arch" in
  x86_64 | amd64) host_arch=amd64 ;;
  aarch64 | arm64) host_arch=arm64 ;;
esac

# ---- plain local-dev up (no SSO) --------------------------------------------
if (( ! with_sso )); then
  printf '%s\n' "\
k3d cluster create ${cluster} --servers 1 --wait && \\
docker build --build-arg TARGETARCH=${host_arch} -t demo-app:${tag} ${app_dir} && \\
k3d image import demo-app:${tag} -c ${cluster} && \\
helm repo add cnpg https://cloudnative-pg.github.io/charts && \\
helm repo add external-secrets https://charts.external-secrets.io && \\
helm repo update cnpg external-secrets && \\
helm upgrade --install cnpg-operator cnpg/cloudnative-pg \\
  --version ${cnpg_chart_version} --namespace cnpg-system --create-namespace --wait && \\
helm upgrade --install external-secrets external-secrets/external-secrets \\
  --version ${eso_chart_version} --namespace external-secrets --create-namespace \\
  --set installCRDs=true --wait && \\
kubectl apply -k ${overlay} && \\
kubectl -n cnpg-demo wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \\
  cluster/pg --timeout=300s && \\
kubectl -n demo rollout status deploy/demo-app --timeout=180s && \\
echo 'local stack up — open the app:  kubectl -n demo port-forward svc/demo-app 8088:80  then http://localhost:8088'"
  exit 0
fi

# ---- --with-sso: validate the one-time SSO env before emitting --------------
for v in GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET OAUTH2_PROXY_CLIENT_SECRET \
         FREEDNS_USERNAME FREEDNS_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    printf 'error: %s must be exported for --with-sso (see docs/LOCAL.md / create_sso_secrets.sh)\n' "$v" >&2
    exit 1
  fi
done

# Prefatory (not &&-chained): drop any existing cluster so it is recreated WITH the
# host-port maps + API-server OIDC args (which can only be set at create time).
printf 'k3d cluster delete %s >/dev/null 2>&1 || true\n' "$cluster"

# The main bring-up: one fail-fast &&-chain. FreeDNS creds are referenced by env
# name (\$FREEDNS_*) so they expand only in the piped shell — never in the preview.
printf '%s\n' "\
k3d cluster create ${cluster} --servers 1 --wait \\
  --port \"443:443@loadbalancer\" --port \"80:80@loadbalancer\" \\
  --k3s-arg \"--kube-apiserver-arg=oidc-issuer-url=https://dex.sso.barzel.sh@server:*\" \\
  --k3s-arg \"--kube-apiserver-arg=oidc-client-id=kubernetes@server:*\" \\
  --k3s-arg \"--kube-apiserver-arg=oidc-username-claim=email@server:*\" \\
  --k3s-arg \"--kube-apiserver-arg=oidc-groups-claim=groups@server:*\" && \\
kubectl apply -f ${sso}/traefik-config.yaml && \\
docker build --build-arg TARGETARCH=${host_arch} -t demo-app:${tag} ${app_dir} && \\
k3d image import demo-app:${tag} -c ${cluster} && \\
helm repo add cnpg https://cloudnative-pg.github.io/charts && \\
helm repo add external-secrets https://charts.external-secrets.io && \\
helm repo add jetstack https://charts.jetstack.io && \\
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \\
helm repo update cnpg external-secrets jetstack prometheus-community && \\
helm upgrade --install cnpg-operator cnpg/cloudnative-pg \\
  --version ${cnpg_chart_version} --namespace cnpg-system --create-namespace && \\
kubectl -n cnpg-system wait --for=condition=Available deploy --all --timeout=300s && \\
helm upgrade --install external-secrets external-secrets/external-secrets \\
  --version ${eso_chart_version} --namespace external-secrets --create-namespace \\
  --set installCRDs=true && \\
kubectl -n external-secrets wait --for=condition=Available deploy --all --timeout=300s && \\
helm upgrade --install cert-manager jetstack/cert-manager \\
  --version ${certmgr_version} --namespace cert-manager --create-namespace \\
  --set crds.enabled=true && \\
kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=300s && \\
rm -rf /tmp/cmw-freedns && \\
git clone --depth 1 https://github.com/tgckpg/cert-manager-webhook-freedns /tmp/cmw-freedns && \\
docker build --platform=linux/${host_arch} -t cert-manager-webhook-freedns:local /tmp/cmw-freedns && \\
k3d image import cert-manager-webhook-freedns:local -c ${cluster} && \\
helm upgrade --install cert-manager-webhook-freedns /tmp/cmw-freedns/deploy/freedns-webhook \\
  --namespace cert-manager \\
  --set-string image.repository=cert-manager-webhook-freedns \\
  --set-string image.tag=local --set-string image.pullPolicy=IfNotPresent \\
  --set-string freedns.auth.FREEDNS_USERNAME=\"\$FREEDNS_USERNAME\" \\
  --set-string freedns.auth.FREEDNS_PASSWORD=\"\$FREEDNS_PASSWORD\" && \\
kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=300s && \\
helm upgrade --install kps prometheus-community/kube-prometheus-stack \\
  --version ${kps_version} --namespace monitoring --create-namespace \\
  -f ${sso}/monitoring-values.yaml && \\
kubectl -n monitoring wait --for=condition=Available deploy --all --timeout=600s && \\
kubectl apply -k ${overlay} && \\
kubectl apply -f ${repo_root}/gitops/applications/demo-app/servicemonitor.yaml && \\
kubectl -n cnpg-demo patch cluster pg --type merge \\
  -p '{\"spec\":{\"monitoring\":{\"enablePodMonitor\":true}}}' && \\
kubectl apply -f ${sso}/monitoring-extras.yaml && \\
kubectl apply -f ${sso}/namespace.yaml && \\
bash ${repo_root}/gitops/bootstrap/create_sso_secrets.sh | bash && \\
sed 's|__ACME_EMAIL__|${acme_email}|g' ${sso}/cluster-issuer.yaml | kubectl apply -f - && \\
sed 's|__ACME_ISSUER__|${acme_issuer}|g' ${sso}/certificate.yaml | kubectl apply -f - && \\
kubectl apply -f ${sso}/dex.yaml && \\
sed 's|__OPERATOR_EMAIL__|${operator_email}|g' ${sso}/oauth2-proxy.yaml | kubectl apply -f - && \\
kubectl apply -f ${sso}/ingressroutes.yaml && \\
sed 's|__OPERATOR_EMAIL__|${operator_email}|g' ${sso}/rbac.yaml | kubectl apply -f - && \\
LB_IP=\"\$(docker inspect k3d-${cluster}-serverlb --format '{{(index .NetworkSettings.Networks \"k3d-${cluster}\").IPAddress}}')\" && \\
docker exec -e LB_IP=\"\$LB_IP\" k3d-${cluster}-server-0 sh -c 'grep -q dex.sso.barzel.sh /etc/hosts || echo \"\$LB_IP dex.sso.barzel.sh\" >> /etc/hosts' && \\
kubectl -n cnpg-demo wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \\
  cluster/pg --timeout=300s && \\
kubectl -n demo rollout status deploy/demo-app --timeout=180s && \\
kubectl -n sso rollout status deploy/dex --timeout=120s && \\
echo '' && \\
echo 'SSO edge applied. Next:' && \\
echo '  1) /etc/hosts: 127.0.0.1 dex.sso.barzel.sh grafana.sso.barzel.sh prometheus.sso.barzel.sh demo.sso.barzel.sh' && \\
echo '  2) DNS-01 cert (minutes): kubectl -n sso get certificate sso-wildcard -w' && \\
echo '     (staging issuer = browser warning; flip ACME_ISSUER=letsencrypt-prod for a trusted chain + working kube-API OIDC)' && \\
echo '  3) open https://grafana.sso.barzel.sh (operator) | https://demo.sso.barzel.sh (any GitHub user)'"
