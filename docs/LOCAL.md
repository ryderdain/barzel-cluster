# Runbook — Local-dev stack (k3d)

Run the **CNPG + demo-app** stack on a developer laptop with **no AWS** — the
portability proof for the platform (k3s everywhere; ADR-0015 /
[ARCHITECTURE](ARCHITECTURE.md)). It's the same workload manifests as the cloud
cluster, applied through a thin
[`gitops/clusters/local`](../gitops/clusters/local) overlay.

## Prerequisites

- A container engine (Docker Desktop, Colima, or equivalent), with the engine
  started, and its `docker` CLI.
- Internet access. The images come from the upstream registries, through the
  local Zot cache.
- No AWS account, profile, or credentials.

The other tools (`k3d`, `kubectl`, `helm`, `jq`) are in the kiesei image. Make
the image one time, and again after a change to `containers/kiesei/`:

```sh
docker build -t kiesei:local containers/kiesei
```

## Where the procedure operates

The driver prints a procedure. The command on the right side of the pipe
selects where it operates:

- `| bash driver/kiesei.sh` operates it in the kiesei image, with the pinned
  tools. This is the usual selection.
- `| bash` operates it on the host. Then the host must have `k3d`, `kubectl`,
  `helm`, and `jq`.

The procedure is the same for the two shells.

## Up

The driver prints a procedure and does not operate it. You give your approval
when you pipe the procedure to a shell.

Careful mode, one phase at a time:

```sh
bash driver/driver.sh local next                          # read the next phase
bash driver/driver.sh local next | bash driver/kiesei.sh  # operate it; do again
```

Fast mode, all phases that are not complete:

```sh
bash driver/driver.sh local up | bash driver/kiesei.sh
```

The local environment has five phases. Each phase has a locus: the driver
(where you operate the procedure) or the conductor (a kiesei pod in the
cluster).

- `10-substrate` (driver) makes the Zot registry (if it is not there) and the
  k3d cluster, and writes the kubeconfig to the run directory.
- `15-conductor` (driver) pushes the kiesei image to Zot and starts the
  conductor in the namespace `brzl-system`.
- `20-platform` (conductor) installs the CloudNativePG and External Secrets
  operators with helm.
- `30-images` (driver) assembles the demo-app image and pushes it to Zot.
- `40-workloads` (conductor) applies the local overlay. The driver renders the
  overlay into the run-log, so the run-log shows all that was applied.

For a conductor phase, the driver copies the run-log into the conductor pod,
operates it there, shows its output, and copies back the exit status. The
conductor stops itself after `BRZL_CONDUCTOR_IDLE_SECONDS` with no work. The
next conductor phase starts it again.

Each phase writes a run-log to `var/run/local/<YYYYmmddHHMM>/`: the commands
(`<NN>-<phase>.sh`), their output (`.out`), the exit status (`.rc`), and `.ok`
when the check of the phase is correct. If a phase stops, repair the cause and
operate `up` or `next` again. The driver starts at the first phase that has no
`.ok`.

To see the commands of one phase without the driver:

```sh
bash driver/phases/20-platform.sh phase_up local var/run/local/preview
```

To see the condition of the current run:

```sh
bash driver/driver.sh local status
```

The values for the local environment are in `env/local.env`. To change one
value for one run, export it. The driver shows a warning and records the
value in the run-log. Export the value. Then the two sides of the pipe get
it:

```sh
export BRZL_K3D_AGENTS=2
bash driver/driver.sh local up | bash driver/kiesei.sh
```

### The Zot registry

Zot operates adjacent to the cluster, on the container network `brzl-local`.
It is a pull-through cache for `docker.io`, `ghcr.io`, `quay.io`, and
`registry.k8s.io`, and the registry for images that you assemble here
(`localhost:5001/brzl/...`). Its data is on the volume `brzl-zot-data`. Thus the
cache stays when you remove the cluster. The first pull of an image through
Zot can continue for some minutes.

To remove Zot, its cache, and the network:

```sh
docker rm -f brzl-zot
docker volume rm brzl-zot-data
docker network rm brzl-local
```

## Use it

```sh
export KUBECONFIG=var/run/local/current/kubeconfig
kubectl -n demo port-forward svc/demo-app 8088:80   # → http://localhost:8088
```

k3d also adds the cluster to your default kubeconfig, as the context
`k3d-brzl-local`.

Do a search. The app sends the query to Sefaria, shows the results, and writes
them to the local Postgres, as in the cloud. The ESO credential projection
between namespaces uses the same path.

## Up with the operator SSO gateway (`--with-sso`)

At this time, the driver does not make the SSO edge. Until it does, the
previous script, `gitops/clusters/local/k3d-up.sh`, makes it. That script can
**recreate** the cluster with the full operator-SSO edge (ADR-0018): host ports
443/80, the kube-API OIDC args, **cert-manager** + the **FreeDNS DNS-01**
webhook for a trusted `*.sso.barzel.sh` Let's Encrypt wildcard, **Dex** (GitHub
IdP), three per-host **oauth2-proxy** gates (operator/users tiers), and a lean
**Grafana + Prometheus**. This **destroys and rebuilds** the local cluster (the
plain-up dataset is disposable).

**One-time prerequisites** (all flow in as env — nothing is written to a file
or git):

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

bash gitops/clusters/local/k3d-up.sh --with-sso          # preview (creds stay as $VAR literals)
bash gitops/clusters/local/k3d-up.sh --with-sso | bash   # run it
```

The cert issuer is config, not a manual step: `ACME_ISSUER` (default
`letsencrypt-staging`) substitutes the `__ACME_ISSUER__` sentinel in
[`certificate.yaml`](../gitops/clusters/local/sso/certificate.yaml) at apply.
Staging is rate-limit-safe for first iteration but is browser-distrusted *and*
the kube-API server won't trust it. Once DNS-01 validates (`kubectl -n sso get
certificate sso-wildcard -w`), move to the trusted prod chain —
**`ACME_ISSUER=letsencrypt-prod`**. On a fresh run, just export it before
`--with-sso`. On an already-running cluster (to keep data), re-apply just the
cert with the same substitution — no recreate:

```sh
sed "s|__ACME_ISSUER__|letsencrypt-prod|g" gitops/clusters/local/sso/certificate.yaml | kubectl apply -f -
```

cert-manager re-issues against prod via the same FreeDNS DNS-01 path (a few
minutes). **AWS promotes identically** — same manifests,
`ACME_ISSUER=letsencrypt-prod` at bring-up; there is no per-environment manual
cert step (ADR-0018).

**Try the tiers:** open `https://demo.sso.barzel.sh` (any authenticated GitHub
user is allowed → `users` tier) and `https://grafana.sso.barzel.sh` (only
`OPERATOR_EMAIL` is allowed → `operators`; others are denied).
`https://prometheus.sso.barzel.sh` is operator-only and has no other auth.
Onboarding + the kube-API OIDC `kubectl` context are in [ACCESS.md](ACCESS.md).

## Down

```sh
bash driver/driver.sh local down            # read the procedure
bash driver/driver.sh local down | bash     # remove the k3d cluster
```

This removes the cluster for either path (`driver.sh` or `--with-sso`). The
next `up` starts a new run.

## What differs from the AWS cluster (and why)

The overlay touches only the genuinely AWS-specific bits; everything else is
byte- for-byte the cloud manifests:

| Concern | AWS cluster | Local (k3d) | Why |
|---------|-------------|-------------|-----|
| Images | ECR + pull-through (host injected by the ApplicationSet) | Zot pull-through + a locally built `localhost:5001/brzl/demo-app:local` (pushed) | same pull path as the cloud; no registry auth locally |
| Storage | EBS CSI, `gp3` | `local-path` (k3d built-in) | no cloud block storage on a laptop |
| Postgres | 3 instances (HA) | 1 instance | laptop footprint; HA isn't the point locally |
| Backups | CNPG → S3 (Barman) | **off** | no object store locally |
| Monitoring | kube-prometheus-stack + ServiceMonitor | **off** by default; **on** with `--with-sso` | not needed for plain app iteration |
| GitOps | ArgoCD ApplicationSet | `kubectl apply -k` (direct) | skips the ECR-coupled ApplicationSet; faster dev loop |
| Identity / UI SSO | OIDC roles, ingress (prod path) | none by default; **the full SSO edge** with `--with-sso` (see below) | the local cluster is where the SSO gateway is actually built (ADR-0018) |

**Image strategy.** Local builds the demo-app and pushes it to Zot
(`localhost:5001/brzl/demo-app:local`). The cluster pulls it from Zot, and it
pulls every upstream image through Zot's cache, as a cloud cluster pulls
through ECR (ADR-0023). There is no ECR login and no registry credential.

**Parity note.** The CNPG operator, External Secrets, the `Cluster`, the ESO
`ClusterSecretStore`/`ExternalSecret`, and the demo-app Deployment/Service are
the same objects as production — so a green local run is real evidence the
stack is substrate-portable, not a bespoke laptop variant.
