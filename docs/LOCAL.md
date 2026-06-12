# Runbook — Local-dev stack (k3d)

Run the **CNPG + demo-app** stack on a developer laptop with **no AWS** — the
portability proof for the platform (k3s everywhere; ADR-0015 / [ARCHITECTURE](ARCHITECTURE.md)).
It's the same workload manifests as the cloud cluster, applied through a thin
[`gitops/clusters/local`](../gitops/clusters/local) overlay.

## Prerequisites
- **Docker** (running), **k3d** (`brew install k3d`), **kubectl**, **helm**.
- Internet egress (the operator images pull from upstream registries).
- No AWS account, profile, or credentials.

## Up
```sh
bash gitops/clusters/local/k3d_up.sh            # preview the commands
bash gitops/clusters/local/k3d_up.sh | bash     # run it
```
This creates a 1-server k3d cluster, **builds the demo-app and imports it**
(`k3d image import` — no registry, no ECR auth), helm-installs the **CloudNativePG**
and **External Secrets** operators from upstream charts, applies the local overlay,
and waits for Postgres + demo-app.

## Use it
```sh
kubectl -n demo port-forward svc/demo-app 8088:80   # → http://localhost:8088
```
Run a search — it calls Sefaria, renders results, and writes them to the local
Postgres exactly as in the cloud; the ESO cross-namespace credential projection
runs the same path.

## Up with the operator SSO gateway (`--with-sso`)

The same script can **recreate** the cluster with the full operator-SSO edge
(ADR-0018): host ports 443/80, the kube-API OIDC args, **cert-manager** + the
**FreeDNS DNS-01** webhook for a trusted `*.sso.barzel.sh` Let's Encrypt wildcard,
**Dex** (GitHub IdP), three per-host **oauth2-proxy** gates (operator/users tiers),
and a lean **Grafana + Prometheus**. This **destroys and rebuilds** the local cluster
(the plain-up dataset is disposable).

**One-time prerequisites** (all flow in as env — nothing is written to a file or git):

1. **GitHub OAuth App** — Authorization callback URL `https://dex.sso.barzel.sh/callback`.
2. **FreeDNS / afraid.org** account that manages `barzel.sh` (for the DNS-01 TXT).
3. **`/etc/hosts`**: `127.0.0.1 dex.sso.barzel.sh grafana.sso.barzel.sh prometheus.sso.barzel.sh demo.sso.barzel.sh`
4. **`kubelogin`** (`brew install int128/kubelogin/kubelogin`) for the kube-API OIDC step.

```sh
export GITHUB_CLIENT_ID=...  GITHUB_CLIENT_SECRET=...
export OAUTH2_PROXY_CLIENT_SECRET="$(openssl rand -hex 32)"   # you mint this — hex (URL-safe), NOT base64
export FREEDNS_USERNAME=...  FREEDNS_PASSWORD=...
export ACME_EMAIL=you@example.com         # default ryder.dain@gmail.com
export OPERATOR_EMAIL=you@example.com      # MUST equal your GitHub primary email (gates Grafana/Prometheus + kube-admin)
# Optional: ACME_ISSUER=letsencrypt-prod   # default letsencrypt-staging while validating DNS-01

bash gitops/clusters/local/k3d_up.sh --with-sso          # preview (creds stay as $VAR literals)
bash gitops/clusters/local/k3d_up.sh --with-sso | bash   # run it
```
The cert issuer is config, not a manual step: `ACME_ISSUER` (default
`letsencrypt-staging`) substitutes the `__ACME_ISSUER__` sentinel in
[`certificate.yaml`](../gitops/clusters/local/sso/certificate.yaml) at apply.
Staging is rate-limit-safe for first iteration but is browser-distrusted *and* the
kube-API server won't trust it. Once DNS-01 validates
(`kubectl -n sso get certificate sso-wildcard -w`), move to the trusted prod chain —
**`ACME_ISSUER=letsencrypt-prod`**. On a fresh run, just export it before `--with-sso`.
On an already-running cluster (to keep data), re-apply just the cert with the same
substitution — no recreate:

```sh
sed "s|__ACME_ISSUER__|letsencrypt-prod|g" gitops/clusters/local/sso/certificate.yaml | kubectl apply -f -
```

cert-manager re-issues against prod via the same FreeDNS DNS-01 path (a few minutes).
**AWS promotes identically** — same manifests, `ACME_ISSUER=letsencrypt-prod` at
bring-up; there is no per-environment manual cert step (ADR-0018).

**Try the tiers:** open `https://demo.sso.barzel.sh` (any authenticated GitHub user is
allowed → `users` tier) and `https://grafana.sso.barzel.sh` (only `OPERATOR_EMAIL` is
allowed → `operators`; others are denied). `https://prometheus.sso.barzel.sh` is
operator-only and has no other auth. Onboarding + the kube-API OIDC `kubectl` context
are in [ACCESS.md](ACCESS.md).

## Down
```sh
bash gitops/clusters/local/k3d_up.sh down | bash    # k3d cluster delete (same for either up path)
```

## What differs from the AWS cluster (and why)
The overlay touches only the genuinely AWS-specific bits; everything else is byte-
for-byte the cloud manifests:

| Concern | AWS cluster | Local (k3d) | Why |
|---------|-------------|-------------|-----|
| Images | ECR + pull-through (host injected by the ApplicationSet) | upstream registries + a locally-built `demo-app:local` (imported) | the host-injection is AWS-only; local needs no registry auth |
| Storage | EBS CSI, `gp3` | `local-path` (k3d built-in) | no cloud block storage on a laptop |
| Postgres | 3 instances (HA) | 1 instance | laptop footprint; HA isn't the point locally |
| Backups | CNPG → S3 (Barman) | **off** | no object store locally |
| Monitoring | kube-prometheus-stack + ServiceMonitor | **off** by default; **on** with `--with-sso` | not needed for plain app iteration |
| GitOps | ArgoCD ApplicationSet | `kubectl apply -k` (direct) | skips the ECR-coupled ApplicationSet; faster dev loop |
| Identity / UI SSO | OIDC roles, ingress (prod path) | none by default; **the full SSO edge** with `--with-sso` (see below) | the local cluster is where the SSO gateway is actually built (ADR-0018) |

**Image strategy.** Local builds the demo-app and `k3d image import`s it (tag
`demo-app:local`, `imagePullPolicy: IfNotPresent`), so there's no ECR login. If you
*do* want to pull the published image from ECR instead, `aws ecr get-login-password`
→ create a docker-registry `imagePullSecret` in the `demo` namespace and point the
deployment at the ECR ref — but that reintroduces an AWS dependency the import path
avoids.

**Parity note.** The CNPG operator, External Secrets, the `Cluster`, the ESO
`ClusterSecretStore`/`ExternalSecret`, and the demo-app Deployment/Service are the
same objects as production — so a green local run is real evidence the stack is
substrate-portable, not a bespoke laptop variant.
