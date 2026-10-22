# SPEC.md — Design Specification (the design source of truth)

> **The design source of truth.** This is the internal home for *what we are
> building* and the **standing technical decisions** (§3) that govern it.
> **New design decisions land here first**, then promote to the delivery-facing
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (curated prose + the ADR index; ADRs in `docs/adr/`).
> [`CLAUDE.md`](CLAUDE.md) delegates design directives here rather than
> duplicating them — one home, so they can't drift. Originated answering a
> take-home brief (kept private); the take-home is delivered and **no
> longer the governing scope** — this doc now tracks the *ongoing* design (the
> refactor in [`BACKLOG.md`](BACKLOG.md)).
>
> **Delivery snapshot (historical):** v0.6 shipped 2026-06-10 — MVP + monitoring +
> backups live, prod env built + validated, full DR restore proven. History is in
> private working notes. Decisions §7; cost/lifecycle §8; differentiators §4; multi-account/org topology (future) §9; changelog §10.

---

## 1. Objective

**(2026-10-14, user)** barzel-cluster is a **platform**: a general, fully
featured, secured Kubernetes cluster that runs on any substrate (k3d on a
laptop, AWS, GCP, DigitalOcean, …) with as few changes as possible. It is
the backbone of a CI/CD chain, and it does not depend on any workload. An
example app (chofesh, ADR-0034) shows stateless and stateful workloads. Any
other app can take its place. Keep it simple: the plainest working shape
wins.

- **Local is the first environment** (ADR-0024). It mimics the cloud: a
  service that a cloud keeps outside the cluster runs outside it locally too
  (ADR-0023, ADR-0026). A person must be able to try the platform on their
  own machine with no public DNS zone and no account at a provider; at the
  same time the local environment stands in for a production environment
  with public endpoints. The laptop substrate alone resolves this, with a
  local stand-in for each public service (DNS, a CA; ADR-0036).
- **One adapter for each substrate**, with the same interface (ADR-0022,
  §3 platform-layer portability). Each cloud provider is a substrate.
- **Promotion** moves platform revisions and workload releases along the
  chain of environments, separately (`promote platform`, `promote
  workloads`; `promote all` when they depend on each other).
- **Confidential computing is a guide, not the goal.** Support for an
  operator-held trust boundary keeps the platform independent of any one
  provider.

*History.* The project began as a take-home brief (kept private): Terraform
→ Ansible k3s → Argo CD → CloudNativePG → a demo REST app, on AWS
(`eu-central-1`), for a confidential-computing company. §2 and §4–§9 keep
that record.

---

## 2. Requirements coverage (TASK.md → our approach → status)

| # | TASK requirement | Our approach | Status |
|---|------------------|--------------|--------|
| 1 | Infra (Terraform): modular, dev/prod, reusable | **Layered state** (Lee Briggs): `modules/` + per-env `environments/{dev,prod}/NN-layer`; remote state S3+DynamoDB | ✅ **live** (applied 10→50; full teardown + DR test done) |
| 2 | Node config (Ansible): runtime, k8s, networking, idempotent | `roles/{base,security,kubernetes}` + `playbooks/bootstrap.yml`; inventory from TF outputs | ✅ **live** (k3s HA 3 servers, idempotent, validated) |
| 3 | GitOps (ArgoCD): operators, apps, env separation | **ApplicationSet** (account-id-free, ADR-0016) + **sync waves**; `clusters/{dev,prod}` + `clusters/local` | ✅ **live** (6 apps Synced/Healthy) |
| 4a | Operator: DB cluster (3x, PVs, failover) | **CloudNativePG**, 3 instances, EBS gp3 PVCs | ✅ **live** (3/3 HA; **failover drilled** — promote, 0 data loss) |
| 4b | Operator: backups (object store, scheduled, restore) | CNPG → **S3 via Barman Cloud**, scheduled + on-demand, restore | ✅ **backup drilled** (CMK-encrypted, instance-profile); restore = the A2 DR test (pending return to AWS) |
| 4c | Operator: monitoring (Prometheus) | CNPG metrics + **ServiceMonitor/PodMonitor**; kube-prometheus-stack + CNPG dashboard + custom app/DB overview | ✅ **live** (scraping CNPG + demo-app; dashboards) |
| 4d | Operator: upgrades (minor PG, rolling, GitOps) | Documented + demonstrated minor bump via GitOps change | ⏳ pending |
| 5 | Example app: REST API r/w Postgres, via GitOps | `apps/demo-app` — a **Sefaria search web app** (Go+pgx, distroless) in its own `demo` ns; CNPG `pg-app` via **ESO** (ADR-0014); app-level Prometheus metrics; ArgoCD wave 3 | ✅ **live** (read/writes verified; also runs on local k3d) |
| D | Docs: architecture, lifecycle, security | `docs/ARCHITECTURE.md` (+ADRs), runbooks `{BOOTSTRAP,ACCESS,UPGRADE,RECOVERY,TEARDOWN,LOCAL}.md`, `SECRETS.md` | 🔄 extensive; security/leadership pending |
| L | Leadership: team org, multi-env, reliability, security | `docs/leadership.md` | ⏳ pending |
| — | README + **time table (actuals)** + LLM-conduct log | `README.md`, time table, `LLM-CONDUCT.md` | 🔄 README + LLM-CONDUCT maintained; time table pending |

---

## 3. Standing technical decisions (locked)

This section is the **single home** for the project's standing technical
decisions; [`CLAUDE.md`](CLAUDE.md) references it rather than restating them.
**Do not silently change these.**

- **Kubernetes:** k3s HA (3 servers, embedded etcd). Not kubeadm/Talos.
- **Compute:** **AWS Graviton / arm64** (`m6g.large` default). Forces arm64 across AMI, k3s, all images/Helm charts, ECR pull-through manifests.
- **Terraform layering:** modular + layered by rate of change (`10-network`→`20-security`→`30-iam`→`40-ecr`→`50-compute`; `15-kms` the persistent foundation); reusable `modules/`. OpenTofu (`tofu`); HCL kept Terraform-compatible.
- **Environment layout — single-source stack (model B, 2026-06-15).** ONE source per layer under `terraform/stack/aws/<layer>/`, applied per environment via a committed per-env `<env>.tfvars` (`-var-file`). The dev→prod **promotion gate is separate INSTANCES** — distinct state + independent apply per env — NOT duplicated source; per-env source directories are retired. Real per-env differences are explicit + input-driven and **favor parity** (a resource may exist dormant in an env rather than be conditionalized out, keeping the option to adopt it later). Replaces the former `environments/{dev,prod}/` duplicated trees. Rationale + rejected alternatives (workspaces; per-env dirs) in the design note (Third Lobe `202606151456`) and BACKLOG item 3.
- **Terraform state backend — ONE bucket, ONE CMK, env split by S3 object key (2026-06-15).** A single S3 state bucket (`brzl-demo-tfstate-<account_id>`) + a single state CMK; environments are separated by the **S3 object key** (`<env>/<layer>/terraform.tfstate`), not by separate buckets/keys. The driver (`gitops/tools/platform.sh`) **composes the backend config at init** — bucket DERIVED from the caller's account, key from `<env>`+`<layer>` — so no account-bearing value or per-env path is committed or kept in a gitignored `backend.hcl` (that per-env file is **retired**). The `terraform_remote_state` data sources derive the bucket the same way and compose the lower-layer key from `var.env`, so a layer reads its own env's lower layers. S3 + DynamoDB lock. **Multi-account form (decided 2026-06-17, built in §9's pass):** one state bucket + CMK **per account**, environments within an account still key-separated (`<env>/<layer>/…`, e.g. dev/stage/prod) — the conductor is *tied to its account's state*, composing the backend from its own caller identity. Single-account today is the degenerate case. *(Later passes: local-first bootstrap → `init -migrate-state` lift into S3; the bootstrap state stays separate from the targets.)*
- **Registry:** ECR for images + OCI Helm charts + pull-through cache (Docker Hub, registry.k8s.io, quay.io, ghcr.io). **Harbor** = documented production recommendation.
- **Storage:** EBS CSI + gp3 default StorageClass. `local-path` only as a documented descope lever. A standalone/DR path installs the CSI driver + gp3 itself (it bypasses the wave-0 GitOps storage app).
- **Backups:** CNPG → S3 (Barman Cloud), authenticated by the **EC2 instance profile** — no second IAM user.
- **GitOps:** a **single `ApplicationSet`** (account-id-free, ADR-0016 — NOT an app-of-apps root) with **sync waves** so operators land before the applications that need them; `clusters/{dev,prod}` + `clusters/local`.
- **Local is the first environment (2026-10-07, ADR-0024).** The promotion chain is local → dev → prod. Local runs on a laptop (k3d) as a real environment, not an exception: GitOps mode (Argo follows a pushed branch) plus **fast mode** (`fast_on`/`fast_off` turn Argo auto-sync off and on so the working tree can be applied directly). Local mimics the cloud functions with stand-ins (ADR-0023): **Zot** outside the k3d cluster (pull-through + push registry, persistent), **OpenBao** outside the cluster, persistent, static seal (KV v2 + transit; ADR-0026), ESO as the read boundary with one write adapter per store, and the admin log store's data on a host directory (ADR-0027). The local cluster is disposable.
- **A workload is deployed from its own repo, and the environment decides what
  it follows (2026-10-18, ADR-0034).** A workload element names its repo and
  its release. The cluster's `brzl.dev/workload-follow` label is `release`
  (the tag) or `branch`. With `branch`, an SCM generator gives the
  development branch's head commit, and the image is the one its CI
  published for that commit. The platform renames only the registry host of
  a workload's image, never a tag, and never builds it.
- **One platform ApplicationSet; values and sync switch per cluster (2026-10-12,
  ADR-0025).** `gitops/platform/applicationset.yaml` serves local, dev and prod
  (same Application names and AWS values as the old per-env files, verified by
  an offline render). Every per-environment value is a label or annotation on
  the cluster Secret (registry host, per-upstream prefix, the workload follow
  policy, backup bucket, git revision), written by the bootstrap (AWS) or phase
  30-gitops (local) — never in git. The annotation `brzl.dev/auto-sync: "false"`
  is the one switch that stops automated sync: **fast mode** (local,
  `fast_on`/`fast_off`, `apply` renders the working tree with Argo's own
  injection) and **break-glass mode** (any environment, emergencies, BACKLOG
  pass 6b). Guard against the ADR-0016 prune cascade: `applicationsSync:
  create-update` + `preserveResourcesOnDeletion`, and phase 30-gitops stops
  before an apply that would orphan a live Application. Argo CD reads the
  private repo with a read-only deploy key from the bootstrap source
  `BRZL_REPO_DEPLOY_KEY` (phase 25, driver locus); a GitHub App replaces it
  before any environment beyond local.
- **The cluster secret store is external, persistent, and seeds the cluster
  (2026-10-13, ADR-0026).** On every substrate the store exists before the
  cluster and outlives it (AWS: Secrets Manager; local: OpenBao beside Zot on
  the container network, `pebbledb` on a volume, static seal with the key in
  `var/secret-store/<env>/`, init once with the root token revoked). The driver
  seeds it from the bootstrap secret sources (`secret_put`), then bootstraps the
  cluster FROM the store (Argo CD's repo credential): a secret enters once. ESO
  reads it through one ClusterSecretStore name, `brzl-secrets`, defined per
  environment in `gitops/clusters/<env>/secret-store` (Vault provider +
  Kubernetes auth on local). Smoke: phase 25 writes a random value, phase 40
  compares hashes. One adapter per store type (`driver/secret-stores/`).
- **Logs: an admin log store and a diagnostic log store (2026-10-14,
  ADR-0027).** Platform logs that audit the environment (run outputs, k3s
  server, API audit, OpenBao audit, events, break-glass) go to the **admin
  log store**, whose data is outside the cluster (object storage; local: a
  host directory) and flushes within minutes. Detailed logs go to the
  **diagnostic log store** in the cluster. OpenTelemetry Collector (OTLP),
  two Loki installations, Grafana. Each namespace routes its logs with
  `brzl.dev/log-routes` (`drop|admin|diagnostic|cold`) and chooses a
  retention class with `brzl.dev/log-retention` (`7d|30d|90d`). Time is UTC,
  ISO 8601 with `Z`, everywhere; each run output starts with a logfmt
  header. Grafana is kube-prometheus-stack's, on every substrate. Loki and
  the collector come from their Helm charts. The collector beside a local
  cluster sends to the one in it, with a queue on disk (Q158–Q162).
- **The admin portal (2026-10-14, ADR-0028).** One nginx in the cluster
  serves a static page and passes each path to its service (`/argocd/`,
  `/grafana/`, `/apps/<workload>/`): one host name, one certificate, the
  same page on every environment, the same URL for HTTP CLI tools. Sign-on,
  later, leads to it.
- **Certificates and the local stand-ins (2026-10-15, ADR-0036).**
  cert-manager is a platform component on every substrate; it renews the
  portal's certificate from the `ClusterIssuer` that each environment's
  `gitops/clusters/<env>/pki/` defines: `local-ca` (OpenBao's PKI engine,
  outside the cluster; the default for a local environment) or
  `letsencrypt` (ACME DNS-01; the default on a cloud, pass 8). On a laptop
  a small CoreDNS container stands in for public DNS: it answers for the
  portal's host name only, when that name is one the operator chose; the
  default, `brzl-<env>.localhost`, resolves by itself. The host name is a
  value in the environment definition, never built from a pattern.
- **Supply chain of the kiesei image (restated 2026-10-14, from ADR-0007).**
  Every tool that the image downloads is pinned to a version and verified,
  by checksum or GPG signature, before it is installed; a build that cannot
  verify a tool fails. ADR-0021 replaced the toolbox image with kiesei and
  did not restate this rule. It stands (`containers/kiesei/`).
- **The Bash doctrine helpers are vendored and pinned (2026-10-14,
  ADR-0029).** `driver/lib/{runlib,error}.sh` are byte-identical to a tagged
  commit of `ryderdain/bash` master; `upstream-check.sh` enforces it.
- **Platform-layer portability (2026-10-07).** The platform layer (`gitops/infrastructure`, operators, workloads) assumes only conformant Kubernetes plus the substrate adapter's outputs (kubeconfig, registry host, secret store). No dependency on k3s-bundled components, so a managed control plane (EKS/GKE/DOKS) can later replace k3s inside one adapter. Known violation: the legacy local SSO edge uses Traefik `IngressRoute` CRDs; the admin portal (ADR-0028) replaces its routing.
- **CI:** keep all pipeline/runner definitions **CI-system agnostic** (must work on GitHub Actions or GitLab CI).
- **Node access:** **SSM Session Manager (SSH-over-SSM)** is the access path — no inbound `:22` (`20-security` `enable_ssh_ingress=false`), node role granted SSM (`30-iam` `enable_ssm=true`), Ansible tunnels via a ProxyCommand using the EC2 instance-id. IAM-gated + audited; the TF-generated key is break-glass only. *Chosen over the Ansible `aws_ssm` connection plugin specifically to avoid its S3 file-transfer bucket — SSH-over-SSM needs none.* Prod hardening (documented): private subnets, no public IP, VPC interface endpoints for `ssm`/`ssmmessages`/`ec2messages`.
- **Operations run from the kiesei image, in two modes (2026-10-07, ADR-0021).** The operator toolchain is one container image, **kiesei** (formerly "toolbox"), which needs only a container engine. The **driver** (*kiesei nahag*) runs it outside the cluster: it makes and removes clusters, sequences phases, approves, and collects outputs. The **conductor** (*kiesei bakar*) runs it as a warm pod in the cluster and runs the run sheets the driver sends. **Substrate phases run on the driver; cluster phases run on the conductor; a locus never removes or replaces itself.** Locus is a property of where the driver sends a run sheet, not of a script, so scripts stay dual-locus and never hard-require `AWS_PROFILE`. Goals unchanged: one toolchain for every operator, an access-controlled entry, audited activity (run sheets in the admin log store, ADR-0027).
- **Driver execution model (2026-10-07, ADR-0022).** `platform.sh` is being split into emit-style phase scripts plus a thin driver. The driver is itself an emit script: one `{ … }` group per phase, each group = emit the phase into a run sheet (`var/run/<env>/<YYYYmmddHHMM>/<NN>-<phase>.sh`, gitignored) → run the file → `.rc` → the phase's check → `.ok`. **No prompts: approval is running the output** — `driver.sh <env> next` (one phase, careful) or `driver.sh <env> up | bash` (all remaining, fast; only for local-only effects). Emitted commands sit in `{ … }` groups used as anonymous functions, with a check only where re-running a block would harm or leave state ambiguous. Outputs pass between phases as files. **Every phase must be safe to run again** — resume is "the first phase with no `.ok`" (the exit code is not the verdict; the check is). Phases with effects outside the driver's machine, or billable ones, are driven one reviewed phase at a time. Each environment has one committed **environment definition** (plain `NAME=value`, no secrets; an exported value wins with a warning; never flags). Rules: `ryderdain/bash` STYLE.md §1.2, §1.11–§1.12. *The EC2 conductor (`environments/dev/00-conductor`) is retired as a concept; it stays in the tree, frozen with the rest of AWS, until pass 8.*
- **Saved-plan workflow (every billable/mutating tofu change):** `tofu plan -out=FILE` → review → `tofu apply FILE`. **Never `-auto-approve`** (it re-plans fresh, can drift from what was reviewed). Plan files gitignored (`*tfplan*`).
- **Encryption:** **customer-managed KMS keys only** (per-purpose: state / ECR / EBS) — never the AWS-managed default keys, for key-policy control, rotation, and grantability (HYOK posture). ~$1/mo per key.
- **Secrets / account-bearing values:** account-id-bearing names are **DERIVED at runtime from the caller** (`aws sts get-caller-identity`) or persisted in a gitignored auto-loaded file — never a per-run `TF_VAR_*` the operator must remember (if it can be dropped between runs, it will be). Committed per-env `<env>.tfvars` hold only **non-secret** env definitions (CIDRs, flags); rendered secret/ARN tfvars use `*.auto.tfvars` and stay gitignored; otherwise only `.example` templates are committed. Inventory in [`docs/SECRETS.md`](docs/SECRETS.md).
- **Conductor GitHub credential — one precisely-scoped token.** The conductor reaches GitHub with **one** dedicated fine-grained PAT scoped to exactly its jobs: `read:packages` (GHCR pull-through) **+** Contents:read + Metadata:read (repo clone). **Not** split per job — "scope credentials to their job" means *no broader than needed*, not *one token per call*; the earlier clone-403 was an **under-scoped** token (a `read:packages`-only PAT used to clone), not a multi-purpose one. (This replaces the S3 tree-ship repo delivery — §9.)
- **Runbooks:** `docs/{BOOTSTRAP,ACCESS,UPGRADE,RECOVERY,TEARDOWN}.md` maintained as living team runbooks. Scaling + backups are automated and documented in the top-level `README.md` (no separate SCALING runbook). The **top-level `README.md` is the primary doc**; no per-directory READMEs.

---

## 4. Differentiators — what makes this stand out

Beyond the literal task. Each maps to an evaluation criterion in `TASK.md §Evaluation`.

### 4.1 Constrained-identity deployment (SSO / OIDC)
*Hits: Security (Access/Secrets Mgmt), Leadership (team org, security), Operational thinking.*

**Two layers, both built:** (a) **CI/agent identity** — federated OIDC role
assumption, no static creds (✅ live: GitHub OIDC → `tofu-plan`/`tofu-apply`); and
(b) **operator SSO** — one GitHub-backed sign-on (**Dex → GitHub**) in front of the
cluster web UIs (Grafana/Prometheus, demo-app) with **role tiers**, plus the same
identity extended to the **kube-API** (kubectl by GitHub identity). Built
**local-first** on k3d (no billing, fully portable — Dex + oauth2-proxy + Traefik +
cert-manager, no IRSA), TLS via **Let's Encrypt over the owned `*.sso.barzel.sh`**
(FreeDNS DNS-01); promotes to AWS by swapping only the edge.

Subsequent deployments run as **agents/operators assuming least-privilege IAM
roles via federated OIDC** — no long-lived static credentials. A human admin
performs only the initial trust-anchor bootstrap; everything after runs under
scoped roles (e.g. `tofu-plan` read-only, `tofu-apply`, `ansible-runner`,
`argocd-deployer`).

- **Humans:** SSO → roles (AWS IAM Identity Center, or Ory-issued).
- **CI runners:** CI's OIDC provider → `AssumeRoleWithWebIdentity` → scoped role (free, cloud-agnostic at the CI layer).
- **In-cluster (ArgoCD/CNPG):** IRSA via a self-published cluster OIDC issuer is the *finer-grained future option*; for the deliverable, CNPG→S3 stays on the instance profile (already decided). Documented as the upgrade path.

**Decided (v0.2):** **native AWS OIDC now** (IAM OIDC provider + IAM Identity Center + scoped roles); **Ory (Hydra) documented** as the portable production recommendation. First slice tonight.

### 4.2 Operator/CI toolbox containers + bootstrap VM — **NEW**
*Hits: Operational thinking, Reliability (repeatable deployments), Supply-chain security, GitOps.*

The bootstrap and upgrade/deploy paths run inside **purpose-built containers**
carrying a pinned toolchain (tofu, ansible, kubectl, helm, git, aws-cli, jq,
repo bash helpers), runnable by an individual operator **or** CI (ArgoCD). This:

- **Eliminates session-timeout failures** on long-running ops (bootstrap, k8s/PG
  upgrades) by decoupling execution from an operator's SSO/SSH session.
- **Kills toolchain drift** across the 3-person team and CI ("works on my machine").
- **Unifies imperative + GitOps:** same image runs as a laptop container, a
  cloud-init bootstrap host, or a k8s `Job` triggered by ArgoCD.

Form factors:
- **Toolbox container image** (arm64, pushed to ECR) — primary artifact.
- **Bootstrap VM** for the chicken-egg first apply + long ops: a host that runs
  the toolbox container, provisioned by **cloud-init** (fast) or a **Packer**-baked
  AMI (immutable/reproducible — documented prod path).

**Decided (v0.2):** **toolbox container (arm64 → ECR) + cloud-init bootstrap VM**;
**Packer-baked AMI documented** as the immutable production path.

### 4.3 Already-baked differentiators
- Layered IaC (rate-of-change separation) — most submissions ship a flat root.
- Graviton/arm64 end-to-end (cost + perf).
- Backup **and verified restore** (not just backup config).
- Consistent "cloud-native for the demo, portable OSS for prod" narrative:
  ECR→**Harbor**, AWS OIDC→**Ory**, cloud-init→**Packer**.

---

## 5. Architecture overview (textual; full diagram in docs/architecture.md)

```
                 ┌─ admin (once) ─┐
                 │  bootstrap:    │  state backend (S3+DynamoDB)
                 │  trust anchor  │  identity: IAM OIDC provider + scoped roles
                 └───────┬────────┘
                         │ assume scoped role (OIDC, no static creds)
        ┌────────────────▼──────────────────┐
        │  TOOLBOX CONTAINER / bootstrap VM │  tofu·ansible·kubectl·helm·git
        └───────┬───────────────┬───────────┘
        tofu apply (layers)     ansible (base→security→k3s HA)
                │               │
   AWS infra (VPC, SG, IAM, ECR, 3x m6g) ──> 3-node k3s HA (embedded etcd)
                                                   │ ArgoCD app-of-apps (sync waves)
                                   ┌───────────────┼────────────────┐
                              EBS CSI/gp3     CloudNativePG op.   demo-app
                                              3x PG + PVCs + failover
                                              S3 backups (Barman, instance profile)
                                              ServiceMonitor → Prometheus/Grafana
```

---

## 6. Proposed repo additions (for the new differentiators)

```
terraform/identity/        # IAM OIDC provider + IAM Identity Center + least-priv roles (admin-run once, after bootstrap)
containers/
  toolbox/                 # Dockerfile (arm64) + pinned tool versions -> ECR
  bootstrap-vm/            # cloud-init user-data -> runs toolbox container
                           # (Packer template documented as the prod immutable path)
```
*(`terraform/identity/` is a top-level sibling to `bootstrap/`: account-global, admin-run once.)*

---

## 7. Decisions (resolved)

| # | Decision | Resolution |
|---|----------|------------|
| 1 | SSO/OIDC IdP | ✅ **Native AWS OIDC + IAM Identity Center now; Ory (Hydra) documented** as portable prod rec (ECR→Harbor pattern). First slice tonight. |
| 2 | Toolbox delivery | ✅ **Toolbox container (arm64→ECR) + cloud-init bootstrap VM; Packer AMI documented** as immutable prod path. |
| 3 | `identity` placement | ✅ Top-level **`terraform/identity/`** (account-global, admin-run once, after `bootstrap/`). |
| 4 | Environment isolation model | ✅ **Single AWS account** for the PoC (dev live, prod stub); **AWS Organizations account-per-environment / account-per-customer documented as the prod model**, with the cross-account `assume_role` seam shown in identity HCL (a `prod` provider alias). Reproducibility (TASK eval criterion) > building real multi-account now. |
| 5 | Networking cost posture | ✅ **Managed NAT gateway** (prod-like; single NAT already chosen). NAT-instance / public-subnet-no-NAT noted as descope levers (§8). |
| 6 | Node market | ✅ **Configurable `capacity_type`** ("spot" \| "on-demand") on the compute module: **spot for iteration**, **on-demand `m6g.large` for the delivery demo**. |
| 7 | GitOps topology | ✅ **ArgoCD app-of-apps + sync waves**, scoped by an `brzl-dev` AppProject. One hand-applied root → child Applications ordered by `sync-wave`: argo self-manage (-1), EBS CSI + gp3 default SC (0), then operators (CNPG) + apps. **Bootstrapped once via Helm, then self-managed.** (ADR-0013) |
| 8 | ArgoCD → private repo auth | ✅ **Read-only GitHub deploy key** in a gitignored Secret (`.example` committed). Not a PAT (narrower blast radius), not public (writeup + hygiene). **To change (2026-10-12, Q61):** local uses its own deploy key from the bootstrap source `BRZL_REPO_DEPLOY_KEY`; before any environment beyond local, replace deploy keys with a **GitHub App** credential (BACKLOG gate). |
| 9 | Image sourcing for non-cached upstreams | ✅ **Extend ECR pull-through to quay.io (ArgoCD) + ghcr.io (CNPG) now** — credential-ARN-gated rules mirroring the Docker Hub pattern; node role gains create-on-pull import perms. Charts fetched upstream; only images routed via ECR. (ADR-0008) |
| 10 | Account-id in GitOps manifests | ✅ **`__ECR_REGISTRY_HOST__` sentinel** in committed Helm values (no account id in the delivered repo). Real host published by 40-ecr to **SSM Parameter Store** (`/brzl-dev/ecr/registry_host`); bootstrap reads it (STS fallback) + resolves via `helm --set`. Prod-clean resolutions: ApplicationSet cluster-generator value or Harbor's account-less host. (ADR-0013) |
| 11 | Secret/config store | ✅ **Pull-through creds → Secrets Manager** (ECR requires it; prefix `ecr-pullthroughcache/`), created via `gitops/bootstrap/create-pullthrough-secrets.sh`. **Non-secret config → SSM Parameter Store** (the ECR host). Deploy key → in-cluster k8s Secret. *(GitHub repo Secrets rejected — write-only outside Actions, unusable by ECR pull-through.)* |
| 12 | App ↔ DB credential projection | ✅ **External Secrets Operator** (wave-1 operator). Demo app stays in its own `demo` ns; a least-priv reader SA in `cnpg-demo` + a cluster-scoped `ClusterSecretStore` (k8s provider) + an `ExternalSecret` materialise `demo/pg-app`. DSN **templated with the `pg-rw` FQDN** (CNPG's `uri` uses the short host, unresolvable cross-ns) + `sslmode=require`. CNPG keeps owning/rotating the secret. Same operator generalises to AWS Secrets Manager (the pull-through cred store, §7.11). (ADR-0014) |
| 13 | Local-dev stack parity | ✅ **Design accepted; build deferred** (ADR-0015). Local dev targets **k3d** (k3s-in-Docker → high cloud parity, reinforces ADR-0003). A local overlay flips three things — storage gp3→`local-path`, **retain ECR** via short-lived login secret / `k3d image import`, CNPG backups off — all overlay/values changes, not refactors. Build + `LOCAL.md` deferred **post-delivery / spare buffer only if the AWS spine is solid**; banked now as the portability story for the architecture + leadership docs. Rationale: not a requirement, and a 2nd cluster target would multiply the test surface against the buffer. |
| 14 | ECR host / account-id injection into GitOps (Phase E) | ✅ **ApplicationSet + bootstrap shim** (ADR-0016). `resolve-ecr-host.sh` derives the host from `get-caller-identity`; bootstrap writes host+bucket onto the **in-cluster ArgoCD Secret annotations**; a single **`ApplicationSet`** (clusters generator × inline app list) injects them **at render** — Helm `parameters` for the operator charts, kustomize `images`/`patches` for the workloads. Account id never in git; self-heal-safe (it's part of desired-state, not a post-apply edit). Replaces the app-of-apps root + the PoC sentinel render. |

*Next open questions land here as we iterate.*

### Resolved (implemented 2026-06-04) — Phase E: ECR host injection via ApplicationSet (ADR-0016)

Decision #14 above, built this session. **In-cluster ECR auth keys off the real
`*.dkr.ecr.*` host**, so the host can't be faked — it must be injected at *render*
(self-heal reverts post-apply edits). Mechanism:
- **Shim** `gitops/bootstrap/resolve-ecr-host.sh` → host from `get-caller-identity`.
- **Bootstrap** writes host + bucket onto the **in-cluster ArgoCD Secret**
  annotations (`brzl.dev/ecr-host`, `brzl.dev/backup-bucket`) — not in git.
- **One `ApplicationSet`** (`gitops/clusters/dev/applicationset.yaml`): matrix of a
  `clusters` generator (reads those annotations) x an inline `list` of the 6 apps;
  `templatePatch` injects the host as Helm `parameters` (operator charts) and
  kustomize `images` (demo-app) / `patches` (CNPG `imageName` + barman bucket).
  Replaces the app-of-apps root + the 6 child Applications + the PoC sentinel render.
- **Plain workloads** got a `kustomization.yaml` (demo-app, postgres) so the
  render-time `images`/`patches` apply.

**Validated offline:** kustomize image/patch injection (`kubectl kustomize`); the
`templatePatch` rendered for all 6 elements via a Go `text/template` harness →
valid YAML + correct merge. **Bring-up checkpoints** (need the live
applicationset-controller): the in-cluster Secret + selector (no duplicate of the
implicit in-cluster), `templatePatch` merge semantics, a template without a
pre-patch `source`. *Considered + dropped: a private config repo (2nd repo) and a
CMP envsubst sidecar (Helm-vs-plugin exclusivity).*

---

## 8. Cost & lifecycle posture · non-goals · descope levers

**This is a PoC: bring up → demo → tear down, not a standing system.** Setup is
~$0 (IAM/OIDC free, state bucket ~$0, CMK ~$1/mo prorated). The meter is
per-hour and dominated by two line items:
- **3× compute** — `m6g.large` on-demand ≈ $0.231/hr combined (~$166/mo if left up); **spot ≈ ~70% less** during iteration (decision §7.6).
- **Managed NAT gateway** ≈ $0.045/hr + data (~$32/mo) — the sneaky always-on (decision §7.5).

**Lifecycle discipline (now → delivery):** while iterating, **destroy only the
`50-compute` layer between sessions** (keep network/security/iam/ecr + identity +
state up) to stop the big meter while keeping fast turnaround. **Delivery target:
same-session up/down + an automated reverse-order destroy + cost-leak sweep**
(one script / `make` target, runnable from the toolbox), with a short (7-day)
KMS deletion window so retired CMKs stop billing sooner. Realized in
[`docs/TEARDOWN.md`](docs/TEARDOWN.md).

**✅ RESOLVED (2026-06-04) — EBS CMK moved to a persistent layer.** Was: the
node-root-volume CMK lived *inside* `50-compute`, so "destroy only `50-compute`"
orphaned it into a pending-deletion window each iteration. Now a dedicated
**persistent `dev/15-kms`** foundation layer (reusable `modules/kms` +
`modules/backup`) holds the EBS CMK (30-day window restored), a separate **backup
CMK**, and the **CNPG/Barman backup bucket** (default SSE-KMS, `force_destroy=false`,
deny-wrong-key + deny-insecure-transport bucket policy). `compute` takes
`ebs_kms_key_arn` via `terraform_remote_state`; `30-iam` reads `15-kms` for the
node role's scoped S3 + backup-KMS grants. Apply order: `10 → 15 → 20 → 30 → 40 →
50`. Code-complete + offline-validated; the existing live key migrates via a state
rm/import (no re-encrypt) per [`docs/UPGRADE.md`](docs/UPGRADE.md) at next bring-up.
The 2026-06-03 targeted-destroy stopgap is retired by this move.

**Descope / cost levers (documented tradeoffs, pull if time/cost demands):**
- **Compute market:** spot ↔ on-demand (the `capacity_type` toggle, §7.6).
- **Networking:** managed NAT gateway → NAT instance (t4g.nano ~$3/mo) → public-subnet nodes, no NAT (cheapest, least prod-like — same spirit as the `local-path` lever).
- **Node size:** `m6g.large` (8 GiB) → `m6g.medium` (4 GiB, ~half compute, tighter for CNPG 3-instance + monitoring).
- **Storage:** `local-path` over EBS CSI.
- **Bootstrap:** cloud-init over Packer.
- Skip Ory write-up depth.

**Non-goals:**
- No confidential-computing implementation. CC instance families and attestation stay a guide (§1).
- prod = stubs that prove promotion is a diff, not a full second deployment. The cross-account `assume_role` seam (§7.4) is shown in code/docs but the second account is not created.

---

## 9. Multi-account / org topology — future, directional (NOT built)

The intended trajectory for the conductor + multi-account work (BACKLOG; decided
through the 2026-06-15/17 design discussion). Recorded so it survives compaction;
**none of this is built yet** — today is single-account. It extends §3's model B
rather than replacing it.

- **Per-account conductor deploys that account's env layers.** The temporary,
  single-purpose conductor (§3) is launched **per target account**; model B's per-env
  `<env>.tfvars` gain the target account id + an assume-role for the env's account.
  Several envs may share an account (dev/stage key-separated) or sit alone (prod) —
  the conductor is tied to its account's state either way.
- **State: per-account bucket + CMK, envs key-separated within** (§3). The bootstrap
  state stays separate from the targets.
- **Deploy delivery — clone + pipe, not ship + run-monolith.** The clunky S3 tree-ship
  is replaced by a scoped **git clone** (the one fine-grained PAT, §3). Orchestration
  **emits flattened, pipeable command streams** to the conductor's bare `/bin/bash`
  (GUIDANCE §1.8) rather than running `platform.sh` as a resident on-box monolith. The
  repo is still *cloned* (tofu/Ansible are file-based — piping can't make that go away);
  what travels as a stream is the **command/orchestration layer**. The CI path is
  **non-interactive** (review moves to the plan/PR artifact); the laptop/admin path
  stays interactive-gated (saved-plan).
- **Optional cross-account shared-services — least-privilege central repo/cache (now);
  broader distribution (next pass).** A hub account may host central secrets + a central
  ECR, consumed by **selected** env accounts. The **trust-direction (who-reads-whom) is
  chosen at bootstrap** and recorded. **Rationale: a unified vulnerability-scanning
  regime** — one scan gate (Inspector scan-on-push, fail-on-critical) over centrally
  cached images — explicitly traded against blast radius (a central account is a single
  point of compromise), mitigated by least-privilege cross-account resource policies,
  per-purpose CMKs with explicit cross-account grants, and never flowing prod-sensitive
  material into non-prod.
- **ECR distribution — BOTH push and pull, by purpose (decided 2026-06-17).**
  - **Pull (default, normal operation):** spokes pull selectively via a pull-through
    cache pointed at the hub (a **custom-upstream** ECR cache, or each spoke's own cache)
    — downstream projects stay selective about versions/cadence.
  - **Push (security patches / hotfixes only):** the hub force-propagates a scanned
    patch via **ECR registry replication** so no spoke lags on a vulnerability.
  - Mechanism: a dedicated `hotfix`/`release` repo prefix is the **replication source**
    (repo-prefix-filtered); normal images stay pull-through-only. **Honesty note:**
    replication delivers the *artifact* fast (scanned, hub-provenanced, no cache-miss/
    hub-availability dependence) — *adoption* still needs a GitOps version bump, since
    the repos are immutable + digest-pinned. The scan gate is a **promote** step
    (pull-through → scan → copy passed images into the replication-source repo).

---

## 10. Changelog

- **v0.17 (2026-10-22):** BACKLOG 20 (Q167, Q168, ADR-0025 amendment). A
  failed sync is retried with no limit. Phase 40 names an Application that
  fails 3 times or more. The alert `BrzlSyncFailing` fires at 3 (warning)
  and 5 (critical) failed attempts. No channel sends it yet (BACKLOG 21).
- **v0.16 (2026-10-22):** BACKLOG 4a (Q163–Q166, ADR-0027 and ADR-0036
  amendments). The OTLP receiver uses mutual TLS from the store's CA. Its
  certificate comes from cert-manager, and the client certificate from
  the driver through the client-only PKI role `log-shipper`. The PKI role
  `portal` signs server certificates only. The store's CA is made in phase
  10. gRPC is closed, and workloads never send OTLP to the platform.
  GLOSSARY gains "Roles".
- **v0.15 (2026-10-19):** Pass 6 design round (Q158–Q162, ADR-0027
  amendment). Metrics and Grafana go to every substrate, with one Grafana
  for metrics and logs. Loki and the collector come from Helm charts. The
  local collector beside the cluster sends to the in-cluster collector,
  with a queue on disk. `driver.sh <env> state` moves out of pass 6.
- **v0.14 (2026-10-16):** Pass 5d (Q141–Q147): the example app is
  `tzvat/chofesh` (moved from `ryderdain`) with a server mode and its own manifests and Postgres
  (ADR-0034 built, the credential stays CNPG's). The platform lost
  `apps/demo-app`, the demo-app and postgres GitOps bases and their local
  overlays. The ApplicationSet gained workload elements with their own
  `repo` and `revision`, and (Q148–Q152) the follow policy per environment.
  Local follows the app's `main` through an SCM generator, the others a
  release tag. The app's CI publishes the image. The driver never builds it.
- **v0.13 (2026-10-15):** §1 states the two goals of the local environment
  (try it with nothing public; stand in for production). §3 gains the
  certificate flow and the local stand-ins (ADR-0036); the admin portal line
  loses the store copy of the certificate.
- **v0.12 (2026-10-14):** The objective is a workload-independent platform on
  any substrate (§1; confidential computing a guide). Logs (Q77–Q102,
  ADR-0027, spike on branch `spike-logs`), the admin portal (Q107–Q114,
  ADR-0028), the vendored helpers pinned (Q103, ADR-0029). Plan reordered
  (BACKLOG): 5c portal, 5d example app (chofesh), 6 logs, 6a SSO, 6b
  break-glass, 6c cold storage, 7 `promote platform`, 7h remote harness,
  8 substrate adapters, 9 `promote workloads`.
- **v0.11 (2026-10-13):** Pass 5 (Q66–Q76): the cluster secret store is
  external and persistent on every substrate; local = OpenBao beside Zot,
  seeded by the driver, read by ESO with Kubernetes auth (ADR-0026). ESO
  0.10.7 → 2.12.0 (v1 API). Phases: 10-substrate, 20-images, 25-bootstrap,
  30-gitops, 40-workloads (15-conductor folded in).
- **v0.10 (2026-10-12):** Pass 4 design (Q54–Q65): one platform ApplicationSet
  with the per-environment values and the sync switch on the cluster Secret
  (ADR-0025); **break-glass mode** added beside fast mode (GLOSSARY; BACKLOG
  pass 6b); the repo is private, so local Argo CD reads it with a deploy key
  (phase 25), and a GitHub App is a gate before leaving local (decision 8).
- **v0.9 (2026-10-07):** **Local-first refactor designed** (grilling session, Q1–Q45; passes 0–8 in BACKLOG; vocabulary in `GLOSSARY.md`). §3: the toolbox is renamed **kiesei** and used in two modes — **driver** (outside the cluster) and **conductor** (warm pod in the cluster) — replacing the EC2 conductor (ADR-0021); the **driver execution model** (emit → run sheet → approve → run; idempotent phases; environment definitions) replaces in-place execution (ADR-0022); **local becomes the first environment** with Zot/OpenBao stand-ins (ADR-0023, ADR-0024); **platform-layer portability** rule. ADRs moved to `docs/adr/` (pass 0). `notes/` made local-only. AWS frozen until pass 8. The §9 conductor/multi-account direction predates this and is to be re-assessed against ADR-0021 when AWS unfreezes.
- **v0.8 (2026-06-17):** Captured the **conductor + multi-account direction** (new §9, directional/not-built) from the 2026-06-15/17 design discussion, and sharpened §3: the conductor reclassified from a per-env layer to a **temporary, per-account, single-purpose IaC distributor** (sibling of bootstrap/identity, not hub-and-spoke); state-backend extended to the **per-account** form (bucket+CMK per account, envs key-separated within; conductor tied to its account's state); a **one-fine-grained-PAT** conductor GitHub credential decision (refines "scope to job" = no broader than needed, not one-token-per-call). §9 records: clone+pipe deploy delivery (vs S3 ship + on-box monolith), optional least-priv cross-account shared-services chosen at bootstrap (rationale: a unified vuln-scanning regime), and the **dual-mode ECR** (pull-selective by default + push-for-hotfix via replication). No code yet — the next major pass; gated behind finishing item 3 + a live test.
- **v0.7 (2026-06-15):** Post-delivery refactor begins (BACKLOG items 1–4). **Promoted this SPEC from `notes/` to the repo root as the design source of truth**; CLAUDE.md now delegates standing decisions here (§3) instead of duplicating them — one home (cand-004 SSOT). New/updated §3 decisions: **environment layout model B** (single-source `terraform/stack/aws/<layer>` + per-env tfvars — the promotion gate is separate *instances*, not duplicated source); **state backend** simplified to ONE bucket + ONE CMK, env split by S3 object key, driver-composed at init (the gitignored per-env `backend.hcl` retired); folded the previously CLAUDE-only decisions (GitOps ApplicationSet, CI-agnostic, ops-from-toolbox, saved-plan, account-bearing-values-derived) into §3 and corrected the stale "app-of-apps" wording. Item-1 pass also landed: `operator()` installs EBS CSI+gp3 (was a doc-vs-body lie), driver backend-block preflight + resume-on-failure, standalone/DR path de-pinned from `brzl-dev-*`. `10-network` is the first migrated stack layer (prototype).
- **v0.6 (2026-06-04, late):** Full live arc. AWS bring-up `10→50` + KMS migration + k3s HA (Ansible) + the **ApplicationSet** GitOps (ADR-0016, account-id-free) — all 6 apps Synced/Healthy; **CNPG 3/3 HA, failover drilled** (promote, 0 data loss); **monitoring** (kube-prometheus-stack + CNPG + custom app/DB overview dashboard); **demo-app evolved into a Sefaria search web app** (borrowed `chofesh` client; persists searches/results/api-calls; app-level Prometheus metrics + ServiceMonitor); **backup drilled** (CNPG→S3, CMK, instance-profile). Then a **full teardown as a DR test** (destroyed `10–50` incl. `40-ecr`, kept only `15-kms` backups+CMKs; restore = pending A2). Fixed the **state-bucket TF_VAR fragility** (now derived from caller identity). **Local-dev (k3d) built** (ADR-0015 → built: overlay + `k3d-up.sh`, upstream/imported images, local-path, AWS-free; verified first try). **Operator SSO gateway** (§4.1b) designed then re-targeted to build **local-first** on k3d with **Dex/GitHub**, trusted certs via **Let's Encrypt + FreeDNS DNS-01** over `*.sso.barzel.sh` — in progress.
- **v0.5 (2026-06-04):** Resolved decision 12 (§7): app↔DB credential projection via **External Secrets Operator** (ADR-0014) — demo app moved to its own `demo` namespace; CNPG `pg-app` projected by a least-priv reader SA + `ClusterSecretStore` + `ExternalSecret`, DSN templated to the `pg-rw` FQDN. Built `apps/demo-app` (Go+pgx, arm64 distroless ~19MB, offline-verified end-to-end against PG17) + its GitOps bundle (wave 3). EBS-CMK → `15-kms` state migration **performed** (state rm/import; apply pending next bring-up — UPGRADE.md). Added `SECRETS.md` credential inventory. Resolved decision 13: **local-dev k3d parity — design accepted, build deferred** (ADR-0015) to protect the delivery buffer.
- **v0.4 (2026-06-03):** Resolved decisions 7–10 (§7): ArgoCD app-of-apps + sync waves under an `brzl-dev` AppProject, bootstrapped via Helm then self-managed (ADR-0013); read-only GitHub deploy key for the private repo; ECR pull-through extended to quay.io + ghcr.io (credential-ARN-gated; node role given create-on-pull import perms, ADR-0008); `__ECR_REGISTRY_HOST__` sentinel keeps the account id out of committed GitOps manifests. Scaffolded `gitops/clusters/dev` (root + project + child apps), `gitops/infrastructure/{argocd,ebs-csi}` values, `gitops/bootstrap/` (install script + deploy-key `.example`). EBS CSI + gp3 default SC fold in as the wave-0 infra app. No billable apply run yet (Terraform pull-through/IAM changes + the one-time helm install are gated).
- **v0.3 (2026-06-02):** Resolved decisions 4–6 (§7): single-account PoC + documented account-per-env/customer multi-account (cross-account `assume_role` seam in HCL); managed NAT gateway; configurable `capacity_type` (spot for iteration, on-demand `m6g.large` for demo). Rewrote §8 as cost & lifecycle posture (per-hour cost model, destroy-compute-between-sessions now → automated same-session teardown at delivery, expanded descope/cost levers). Bootstrap state backend + identity trust anchor now **applied & smoke-tested** (prior to §7.4–7.6 work).
- **v0.2 (2026-06-01):** Resolved decisions 1–3 (§7): native AWS OIDC + Identity Center (Ory documented); toolbox container + cloud-init bootstrap VM (Packer documented); `terraform/identity/` top-level.
- **v0.1 (2026-06-01):** Initial spec + scaffolding decisions; added differentiators §4.1 (SSO/OIDC) and §4.2 (toolbox/bootstrap containers); delivery target set to 16:00 CEST Wed 10 Jun.
