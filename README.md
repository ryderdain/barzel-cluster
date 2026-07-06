# barzel-cluster — GitOps Infrastructure Platform

A reproducible, GitOps-driven platform that provisions AWS infrastructure with
Terraform, bootstraps a 3-node HA k3s cluster with Ansible, and uses ArgoCD to
sync a CloudNativePG-managed Postgres plus a demo application — a Sefaria
text-search web app — that reads/writes it.

> **Status:** **complete — verified end-to-end on AWS** —
> `tofu apply` → Ansible k3s HA → ArgoCD sync → CloudNativePG 3-instance Postgres
> → demo-app read/writes, with **failover validated** (kill primary →
> standby promoted, zero data loss), the **DR restore drill passed**
> (2026-06-08: full teardown → fresh stack → restore from S3 alone,
> acceptance-verified to exact row counts — [`docs/RECOVERY.md`](docs/RECOVERY.md)),
> and the **prod environment validated live** (2026-06-10: private-subnet nodes,
> NLB-only ingress, 7/7 apps —
> [ADR-0019](docs/ARCHITECTURE.md#adr-0019--prod-environment-private-subnet-placement-nlb-only-ingress)).
> Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); reproduce via
> [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md).

## How this was built

This platform was built with heavy use of AI tools (primarily Claude Code) —
partly because of the size of the surface, and partly as deliberate practice in
working with agentic tooling effectively. I drove the design decisions and
supervised every billable or mutating step; the model accelerated the mechanical
work. Where and how AI was used is logged session-by-session in
[`notes/LLM-CONDUCT.md`](notes/LLM-CONDUCT.md) — kept as an engineering-hygiene
record, not a disclaimer.

The most useful lesson came from where it went wrong. I'd instructed the agent
to have `gitops/tools/seed_demo_data.sh` build the tunnel to the demo app; it
reported the work done, and I didn't re-verify the postcondition before cloning
the environment for "prod" — so the gap propagated. The fix was cheap; the
lesson was not: **an agent's claim that something is done is not evidence that it
is** — treat agent postconditions the way you'd treat a `terraform plan`,
inspected rather than trusted. That principle is now visible in how the operator
scripts here work (emit-commands-then-pipe preview, explicit verification) and in
the repo's own working discipline.

## Architecture at a glance

```
Terraform  ──>  AWS infra (VPC, SGs, IAM, ECR, KMS, 3x EC2 Graviton nodes)
Ansible    ──>  base + security hardening + k3s HA (3 servers, embedded etcd)
ArgoCD     ──>  ApplicationSet, sync waves: operators (CloudNativePG) before apps
CNPG       ──>  3-instance Postgres on EBS gp3 PVCs, S3 backups (Barman Cloud)
demo-app   ──>  Sefaria search web app, reads/writes Postgres, /metrics scraped
```

Full write-up + decision rationale: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

**Scope — core vs. optional.** The **core platform** is exactly what a stateful
GitOps deployment needs: Terraform infra → Ansible k3s → ArgoCD GitOps → the **CloudNativePG operator**
managing a production-shaped HA Postgres (failover, S3 backup/restore, monitoring,
upgrades) → a demo app that uses it. The operator and its **lifecycle** are the
centerpiece. Everything else is a clearly-labeled **optional differentiator** that
the core neither needs nor depends on — notably the [operator SSO gateway](#operator-sso-gateway--optional-differentiator-local-)
(local, opt-in) and the operator/CI **toolbox** image. Each optional piece is isolated
in its own path and carries its own pre-staging; skip any of them and the core stands.

## Repository layout

| Path | Purpose |
|------|---------|
| [`terraform/`](terraform/) | Layered IaC: reusable `modules/` + per-env `environments/{dev,prod}` |
| [`ansible/`](ansible/) | `roles/{base,security,kubernetes}` + `playbooks/` (node config + k3s bootstrap) |
| [`gitops/`](gitops/) | ArgoCD GitOps: `clusters/{dev,prod}` (the `ApplicationSet` + AppProject + in-cluster Secret), `infrastructure/` (argocd, ebs-csi, cnpg, external-secrets, monitoring values), `applications/`, `operators/postgres/`; `bootstrap/` (one-time argo install + ECR-host shim + repo deploy-key) and `tools/` (read-only cluster/SSM/IP checks + toolbox shell + `ui_forward.sh`) |
| [`apps/demo-app/`](apps/demo-app/) | Demo app: a Sefaria search web UI (search logic borrowed from [chofesh](https://github.com/ryderdain/chofesh)) — persists queries/results + outbound-call logs to Postgres, exposes `/metrics` + a ServiceMonitor — and Dockerfile |
| [`containers/`](containers/) | `toolbox/` (pinned, verified arm64 deploy toolchain image) + `bootstrap-vm/` (cloud-init that runs the toolbox via podman/ECR) |
| [`docs/`](docs/) | Delivery-facing docs: architecture + ADR log, operational-lifecycle runbooks, security |
| [`notes/`](notes/) | Historical working files from the initial build (the execution plan `PLAN-HISTORICAL.md`, the task brief, run reports, the LLM-conduct log, design guidance) — tracked as history |

> **Maintenance note — toolbox aws-cli key.** The toolbox image GPG-verifies the
> aws-cli installer against AWS's signing key, vendored at
> [`containers/toolbox/awscli-public-key.asc`](containers/toolbox/awscli-public-key.asc).
> That key **expires 2026-07-07**; after which a toolbox rebuild's `gpg --verify`
> will fail until the key is refreshed (procedure in the colocated `.asc.example`,
> or build with `--build-arg AWSCLI_VERIFY=false`). This is outside the delivery
> window — the project's delivery date precedes the expiry — and is noted only so
> a later rebuild isn't caught out.

## Prerequisites

- [OpenTofu](https://opentofu.org/) `>= 1.6` (or Terraform `>= 1.6`) — this repo is developed with `tofu`
- [AWS CLI v2](https://aws.amazon.com/cli/) plus the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  — SSM is the only path onto the conductor and the nodes (no inbound `:22`)
- An **admin** identity for the one-time Phase 0 only (the state backend and the
  identity roles — the scoped roles don't exist yet). Everything after runs under
  the TF-created least-privilege roles: `AWS_PROFILE=brzl-apply` on the laptop,
  instance-role creds on the conductor ([`docs/ACCESS.md`](docs/ACCESS.md))
- No SSH key to supply — the node and conductor keypairs are **generated by
  OpenTofu** (break-glass only; SSM is the access path)
- **Upstream registry tokens** — a GitHub PAT (**classic, `read:packages` only**;
  ghcr.io feeds CNPG/ESO through the ECR pull-through) and a **Docker Hub
  read-only token** (Grafana). Mint these **up front** — the `secrets` phase
  consumes them and the bring-up stalls without them. Exact minting shapes in
  [`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md)
- Region defaults to `eu-central-1`

> **Running this yourself?** A few inputs are deliberately **not in the
> repo** — gitignored secrets or GitHub-side config you must **pre-stage**, or the
> bring-up stalls. The conductor runs the *shipped* tree with gitignored files excluded,
> so it won't have them either — stage them on whichever host runs the relevant phase:
>
> - **ArgoCD repo deploy key** *(most likely to be missed)* — generate an ed25519 key,
>   register the **public** half as a read-only **Deploy key** on the GitHub repo ArgoCD
>   pulls (repo → Settings → Deploy keys, **no** write), and paste the **private** half
>   into `gitops/bootstrap/repo-deploy-key.yaml` (from the committed `.example`). Without
>   it ArgoCD installs but can't sync — **every app sits `SYNC: Unknown` with an empty
>   `REVISION`** (the driver blocks on this; the fix is `kubectl apply -f` the Secret,
>   picked up in ~3 min). Pointing at **your own fork**?
>   Update the `url:` in that Secret and the `ApplicationSet`'s repo to match.
> - **Upstream registry tokens** — export `GHCR_USERNAME`/`GHCR_TOKEN` and
>   `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` before the `secrets` phase (ECR pull-through:
>   CNPG/ESO from ghcr.io, Grafana from Docker Hub).
> - **Grafana admin** — created by the `gitops` phase automatically; `export
>   GRAFANA_ADMIN_PASSWORD` first only if you want to pin it (else one is generated).
>
> Step-by-step in [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md); full inventory in
> [docs/SECRETS.md](docs/SECRETS.md).

## Reproduce (high level)

> **AWS is billable.** Every `apply` below creates real, costed resources. See the
> teardown / cost-leak sweep in [`docs/TEARDOWN.md`](docs/TEARDOWN.md).

**"Bootstrap" means two different things here — keep them separate:**

- **Account bootstrap** (the *trust anchor*): one-time **per AWS account**, run by an
  **admin** from a laptop. Creates the Terraform state backend and the identity roles.
  After it, the account is ready to be operated by scoped roles. This is **Phase 0**.
- **Platform bring-up** (the *environment + cluster*): provisions an environment's
  infra, the k3s cluster, and the GitOps apps. Runs **from the conductor** under the
  scoped apply role via [`gitops/tools/platform.sh`](gitops/tools/platform.sh)
  (whose own `bootstrap` subcommand brings up the cluster). Repeatable per environment.

### Phase 0 — account bootstrap (admin, once per account)

1. **State backend:** `cd terraform/bootstrap`, set the bucket name in
   `terraform.tfvars`, then `tofu init && tofu plan -out=tfplan && tofu apply tfplan`
   — creates the S3 state bucket + DynamoDB lock + a customer-managed KMS key. The
   bucket name is a **convention, not a free choice**: it must be
   `brzl-demo-tfstate-<account_id>`, because the stack layers and the identity policy
   *derive* it from the caller's account id (so there's no `TF_VAR_state_bucket` to
   drop or mistype). The stack layers need **no `backend.hcl`** — the driver composes
   the backend (key `<env>/<layer>/terraform.tfstate`) at init (SPEC §3). (Only the
   `identity` primitive + the conductor take a `backend.hcl`, from `.example`.)
2. **Trust anchor:** apply [`terraform/identity/`](terraform/identity/) — the GitHub
   OIDC provider + scoped `tofu-plan` / `tofu-apply` roles. Everything after runs under
   an assumed least-privilege role, not static keys ([`docs/ACCESS.md`](docs/ACCESS.md)).

### Platform bring-up (from the conductor, per environment)

The concrete sequence:

```sh
# Laptop (apply role): launch the disposable conductor, ship the COMMITTED tree
AWS_PROFILE=brzl-apply bash gitops/tools/platform.sh conductor
AWS_PROFILE=brzl-apply bash gitops/tools/ship_repo.sh
aws ssm start-session --target <conductor-instance-id>   # printed by the conductor step

# Conductor (instance-role creds, no profile):
#   stack layers need no backend.hcl — the driver composes the backend from the
#   account + ENV. Just export the upstream tokens and run the driver:
export GHCR_USERNAME=… GHCR_TOKEN=… DOCKERHUB_USERNAME=… DOCKERHUB_TOKEN=…
ENV=dev bash gitops/tools/platform.sh bootstrap           # or ENV=prod
```

One gated driver sequences
the Terraform layers (`10-network → 15-kms → 20-security → 30-iam → 40-ecr →
50-compute`) → Ansible (base → security → k3s HA) → ArgoCD + the `ApplicationSet`
(EBS CSI/gp3 and the CloudNativePG + External Secrets operators ahead of the Postgres
cluster and demo-app, by sync wave). The real ECR host is resolved at bootstrap and
injected at render, so **no AWS account id is ever committed to git**
([ADR-0016](docs/ARCHITECTURE.md#adr-0016--account-id-free-gitops-applicationset-host-injection-at-render)).
AWS ops run from the conductor (audited, IAM-gated, identical toolchain); the laptop
only does Phase 0 and launches the conductor.

**The two environments differ by inputs, not by code** — one single-source stack
([`terraform/stack/aws/`](terraform/stack/aws/)), per-env `dev.tfvars`/`prod.tfvars`
(model B; SPEC §3). `dev` (`public_nodes=true`): nodes in public subnets, /32-locked,
API direct. `prod` (`public_nodes=false`): nodes in **private subnets with no public
IPs**, kube-API via SSM port-forward, and the **only public surface is a
Terraform-owned NLB** (`enable_public_ingress=true`) fronting the demo-app UI
(allowlisted to the operator /32 by default; `lb_ingress_cidr` opens it deliberately).

The conductor holds **no GitHub credential**: the laptop ships your approved working
tree to the state bucket (`ship_repo.sh`) and the conductor pulls it via its instance
role (`brzl-fetch`), so it runs exactly the snapshot you push over the audited channel.
The step-by-step, billing-annotated procedure (exact assume-role + per-phase commands)
is the **[`docs/BOOTSTRAP.md`](docs/BOOTSTRAP.md)** runbook. local-dev (k3d, no AWS) is
a separate laptop-only path — [`docs/LOCAL.md`](docs/LOCAL.md).

**Accessing the cluster (kubectl).** Because the control plane is self-managed
k3s, there's no managed `aws eks update-kubeconfig` to hand you credentials — the
admin kubeconfig is generated on a control-plane node. The Ansible k3s role drops
a copy locally, and [`gitops/tools/kubeconfig_setup.sh`](gitops/tools/kubeconfig_setup.sh)
installs it as an `brzl-dev` context in your `~/.kube/config`, re-resolving the
API endpoint to the node's current address (node IPs change when compute is
recreated). Details in [`docs/ACCESS.md`](docs/ACCESS.md). *(This self-managed
kubeconfig handling is a deliberate trade of EKS's turnkey access for control-
plane portability — see [why k3s, not EKS](docs/ARCHITECTURE.md#3-why-k3s-not-eks).)*

## Scaling

Scaling is a configuration change the platform reconciles for you, not a manual
build-out:

- **Application:** a Kubernetes `HorizontalPodAutoscaler` would scale `demo-app`
  replicas on CPU/memory (extensible to custom Prometheus metrics). With ArgoCD owning
  the manifest, the desired range becomes a git value. Not implemented —
  out of scope for the task.
- **Database:** CloudNativePG scales read replicas by changing `.spec.instances`
  (a GitOps diff); the operator provisions the new PVC and streams the replica in
  automatically. Storage grows by gp3 volume expansion on the PVC.
- **Nodes:** the `50-compute` layer's node count is a single Terraform variable;
  bumping it and re-running the Ansible `kubernetes` role joins new **arm64**
  nodes to the cluster. Production path (documented): an EC2 Auto Scaling Group /
  Karpenter for demand-driven node scaling.

## Backups & recovery — automated

Database durability is automated end to end (details + the restore drill in
**[`docs/RECOVERY.md`](docs/RECOVERY.md)**):

- **Continuous + scheduled:** CloudNativePG ships WAL to S3 continuously and
  takes a scheduled base backup (a `ScheduledBackup` cron CR under
  `gitops/operators/postgres/`) — all GitOps-managed, no operator action.
- **Auth without a second secret:** backups authenticate via the **EC2 instance
  profile** (no second IAM user); the backup bucket is **customer-managed-KMS**
  encrypted.
- **Restore is verified, not assumed:** recovery bootstraps a *new* cluster from
  the object store with point-in-time targeting. The drill has been run for real
  (2026-06-08, conductor-driven via `platform.sh restore`): full teardown → fresh
  stack → restore from the S3 backups alone, acceptance-verified to exact row
  counts.

## Observability & web UIs

Monitoring is a GitOps app like everything else: **kube-prometheus-stack** (chart
86.1.1) syncs at wave 1 — Prometheus + Grafana + node-exporter + kube-state-metrics
— giving cluster/node/workload dashboards out of the box. Postgres is scraped via
the CNPG cluster's PodMonitor, and the official **CloudNativePG Grafana dashboard**
(grafana.com id 20417) ships with it. A custom **app & database overview**
dashboard (`gitops/applications/demo-app/dashboard.gen.py`) puts the demo-app's
metrics and the Postgres metrics **side-by-side** — request/search/error rates and
outbound-call latency next to transactions, connections, tuples, and rollbacks — so
app↔DB drift or errors stand out at a glance. Alertmanager is trimmed off (no receiver
wired; a one-line re-enable). Prometheus/Grafana persist on small gp3 PVCs. Every
image routes through ECR pull-through — including Grafana via the Docker Hub rule
(rationale in [ADR-0017](docs/ARCHITECTURE.md#adr-0017--observability-kube-prometheus-stack-trimmed-port-forward-access)).

The web UIs are reached with **zero extra cost** — no LoadBalancer/Ingress. One
helper port-forwards them and prints each admin credential:

```bash
bash gitops/tools/ui_forward.sh          # Grafana + Prometheus + the ArgoCD panel
bash gitops/tools/ui_forward.sh grafana  # or just one
```

→ Grafana `localhost:3000`, Prometheus `localhost:9090`, ArgoCD `localhost:8080`.

The **demo app's** own web UI (the Sefaria search) is reached the same way:

```bash
kubectl -n demo port-forward svc/demo-app 8088:80   # → http://localhost:8088
```

Each search runs a live Sefaria API call, renders the results in-page, and writes
the query + results to Postgres while logging the outbound call — so the CNPG and
`demoapp_*` panels show real traffic. Its `/metrics` are scraped by the
ServiceMonitor above.

### Operator SSO gateway — optional differentiator (local) 🧩

> **Scope:** this is an **optional add-on, not part of the core deliverable.** The
> core platform (Terraform → Ansible k3s → ArgoCD → CloudNativePG → demo-app, on AWS)
> stands up and is operated **without it**. SSO is a self-contained extra that lives
> only under [`gitops/clusters/local/sso/`](gitops/clusters/local/sso) and is brought
> up on the **local k3d** cluster with a single opt-in flag (`k3d_up.sh --with-sso`).
> It carries its **own** one-time pre-staging — a **GitHub OAuth App** + a **FreeDNS**
> credential — entirely separate from the core's image-supply-chain creds (the
> quay/ghcr/Docker-Hub ECR pull-through tokens, which the core needs regardless). Skip
> this whole section and the core platform is unaffected.

Per-service admin+password logins are the wrong posture for a team. The optional
answer — built and proven on the **local k3d cluster** (no billing meter), portable
to AWS unchanged — is a self-hosted **operator SSO gateway**: **Dex** federates a
GitHub OAuth App and issues one OIDC identity that gates the web UIs **and** the
kube-API. Three role tiers (`users` → the demo app; `operators` → Grafana/Prometheus;
`admins` → org-team only), real **Let's Encrypt** certs via **cert-manager + DNS-01**
over the operator's own `*.sso.barzel.sh`, and `kubectl` by the same GitHub identity
through `oidc-login`. Access to the app UI never grants the operational UIs. Stand it
up with `k3d_up.sh --with-sso` — rationale in
[ADR-0018](docs/ARCHITECTURE.md#adr-0018--operator-sso-gateway-dexgithub-local-first),
onboarding + tiers in [`docs/ACCESS.md`](docs/ACCESS.md), steps in [`docs/LOCAL.md`](docs/LOCAL.md).

## Documentation map

This README is the front door — start here, then follow into the deeper docs.
There are intentionally **no per-directory READMEs**; each area is described here
and detailed in the documents below.

**Design**
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the delivery-facing design doc:
  architecture, the rationale for each load-bearing choice (notably k3s over EKS),
  and a running ADR log.
- [`docs/SECRETS.md`](docs/SECRETS.md) — inventory of every credential, key, and
  secret: what it protects, where it's stored, and how it rotates.
- [`docs/SECURITY.md`](docs/SECURITY.md) — security considerations: secret
  management, access control, and network exposure across the platform.

**Operator runbooks** (`docs/`)
- [`BOOTSTRAP.md`](docs/BOOTSTRAP.md) — zero → running platform, phase by phase.
- [`ACCESS.md`](docs/ACCESS.md) — role/SSO onboarding, assume-role, offboarding.
- [`UPGRADE.md`](docs/UPGRADE.md) — PostgreSQL / k3s / chart / app upgrades (GitOps).
- [`RECOVERY.md`](docs/RECOVERY.md) — backups, restore/PITR, failover, state recovery.
- [`TEARDOWN.md`](docs/TEARDOWN.md) — decommission + the mandatory cost-leak sweep.
- [`LOCAL.md`](docs/LOCAL.md) — run the CNPG + demo-app stack locally on **k3d**, no AWS (the portability proof); `--with-sso` adds the operator SSO gateway.

**Historical**
- [`notes/`](notes/) — the original working files from the initial build (the
  execution plan `PLAN-HISTORICAL.md`, the task brief, run reports, the
  [LLM-conduct log](notes/LLM-CONDUCT.md), and the design guidance), kept as
  tracked history. A GitOps repo's past is a
  feature, not clutter; nothing here is load-bearing for a fresh clone.
