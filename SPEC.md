# SPEC.md — Design Specification (the design source of truth)

> **The design source of truth.** This is the internal home for *what we are
> building* and the **standing technical decisions** (§3) that govern it.
> **New design decisions land here first**, then promote to the delivery-facing
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (curated prose + the ADR log).
> [`CLAUDE.md`](CLAUDE.md) delegates design directives here rather than
> duplicating them — one home, so they can't drift. Originated answering the
> take-home [`notes/TASK.md`](notes/TASK.md); the take-home is delivered and **no
> longer the governing scope** — this doc now tracks the *ongoing* design (the
> refactor in [`BACKLOG.md`](BACKLOG.md)).
>
> **Delivery snapshot (historical):** v0.6 shipped 2026-06-10 — MVP + monitoring +
> backups live, prod env built + validated, full DR restore proven. History in
> [`notes/PLAN-HISTORICAL.md`](notes/PLAN-HISTORICAL.md) + the run reports under
> `notes/`. Decisions §7; cost/lifecycle §8; differentiators §4; multi-account/org topology (future) §9; changelog §10.

---

## 1. Objective (from TASK.md)

A GitOps-driven, reproducible, secure-by-default platform that **provisions
infrastructure (Terraform) → configures nodes & installs Kubernetes (Ansible) →
deploys via GitOps (ArgoCD) → runs an operator-managed stateful service
(CloudNativePG) → proves it with a demo REST app**, plus documentation and
leadership answers. Single cloud chosen: **AWS** (`eu-central-1`).

Framing note: the task is written for the person who will **lead a team of 3
DevOps engineers**. So the design favours choices that scale to a team and to
the vendor's real substrate mix (bare metal / private / public clouds), not just
a one-off demo.

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
- **CI:** keep all pipeline/runner definitions **CI-system agnostic** (must work on GitHub Actions or GitLab CI).
- **Node access:** **SSM Session Manager (SSH-over-SSM)** is the access path — no inbound `:22` (`20-security` `enable_ssh_ingress=false`), node role granted SSM (`30-iam` `enable_ssm=true`), Ansible tunnels via a ProxyCommand using the EC2 instance-id. IAM-gated + audited; the TF-generated key is break-glass only. *Chosen over the Ansible `aws_ssm` connection plugin specifically to avoid its S3 file-transfer bucket — SSH-over-SSM needs none.* Prod hardening (documented): private subnets, no public IP, VPC interface endpoints for `ssm`/`ssmmessages`/`ec2messages`.
- **Operations run from the toolbox, not the laptop.** From pre-flight onward the standard execution locus for infra/cluster ops is the pinned `containers/toolbox/` image — in-cluster, or on a "conductor" reached via SSM (no inbound SSH). Three goals: identical toolchain across operators (reproducible/traceable errors), IAM-gateable operator entry, audited activity. Scripts are **dual-locus** — run with `AWS_PROFILE` on a laptop AND with instance-role creds on the conductor; **never hard-require `AWS_PROFILE`**. AWS envs run from the conductor via `platform.sh` (it rejects `local`); the laptop is only for the admin trust-anchor bootstrap, launching the conductor, and the local-dev (k3d) environment.
- **Conductor — temporary, per-account, single-purpose IaC distributor.** The conductor is a **disposable bootstrap/deploy engine** (CI-runner-like), **one per target account** — *not* hub-and-spoke, so its IAM perimeter stays inside a single account (minimal footprint, single-purpose, torn down after the deploy). It is a **sibling of `terraform/bootstrap` + `terraform/identity`** (account/perimeter primitives), **not** a per-env stack layer. From inside the perimeter it has line-of-sight to both private-VPC and public network changes, and it composes its account's state backend from its own caller identity. *(Current shape — `environments/dev/00-conductor`, repo shipped via S3 — is the take-home snapshot; the relocation + clean git-clone delivery + the multi-account form are §9, a future pass.)*
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
- Graviton/arm64 end-to-end (cost + perf; vendor-relevant).
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
| 8 | ArgoCD → private repo auth | ✅ **Read-only GitHub deploy key** in a gitignored Secret (`.example` committed). Not a PAT (narrower blast radius), not public (writeup + hygiene). |
| 9 | Image sourcing for non-cached upstreams | ✅ **Extend ECR pull-through to quay.io (ArgoCD) + ghcr.io (CNPG) now** — credential-ARN-gated rules mirroring the Docker Hub pattern; node role gains create-on-pull import perms. Charts fetched upstream; only images routed via ECR. (ADR-0008) |
| 10 | Account-id in GitOps manifests | ✅ **`__ECR_REGISTRY_HOST__` sentinel** in committed Helm values (no account id in the delivered repo). Real host published by 40-ecr to **SSM Parameter Store** (`/brzl-dev/ecr/registry_host`); bootstrap reads it (STS fallback) + resolves via `helm --set`. Prod-clean resolutions: ApplicationSet cluster-generator value or Harbor's account-less host. (ADR-0013) |
| 11 | Secret/config store | ✅ **Pull-through creds → Secrets Manager** (ECR requires it; prefix `ecr-pullthroughcache/`), created via `gitops/bootstrap/create_pullthrough_secrets.sh`. **Non-secret config → SSM Parameter Store** (the ECR host). Deploy key → in-cluster k8s Secret. *(GitHub repo Secrets rejected — write-only outside Actions, unusable by ECR pull-through.)* |
| 12 | App ↔ DB credential projection | ✅ **External Secrets Operator** (wave-1 operator). Demo app stays in its own `demo` ns; a least-priv reader SA in `cnpg-demo` + a cluster-scoped `ClusterSecretStore` (k8s provider) + an `ExternalSecret` materialise `demo/pg-app`. DSN **templated with the `pg-rw` FQDN** (CNPG's `uri` uses the short host, unresolvable cross-ns) + `sslmode=require`. CNPG keeps owning/rotating the secret. Same operator generalises to AWS Secrets Manager (the pull-through cred store, §7.11). (ADR-0014) |
| 13 | Local-dev stack parity | ✅ **Design accepted; build deferred** (ADR-0015). Local dev targets **k3d** (k3s-in-Docker → high cloud parity, reinforces ADR-0003). A local overlay flips three things — storage gp3→`local-path`, **retain ECR** via short-lived login secret / `k3d image import`, CNPG backups off — all overlay/values changes, not refactors. Build + `LOCAL.md` deferred **post-delivery / spare buffer only if the AWS spine is solid**; banked now as the portability story for the architecture + leadership docs. Rationale: not a TASK requirement, and a 2nd cluster target would multiply the test surface against the buffer. |
| 14 | ECR host / account-id injection into GitOps (Phase E) | ✅ **ApplicationSet + bootstrap shim** (ADR-0016). `resolve_ecr_host.sh` derives the host from `get-caller-identity`; bootstrap writes host+bucket onto the **in-cluster ArgoCD Secret annotations**; a single **`ApplicationSet`** (clusters generator × inline app list) injects them **at render** — Helm `parameters` for the operator charts, kustomize `images`/`patches` for the workloads. Account id never in git; self-heal-safe (it's part of desired-state, not a post-apply edit). Replaces the app-of-apps root + the PoC sentinel render. |

*Next open questions land here as we iterate.*

### Resolved (implemented 2026-06-04) — Phase E: ECR host injection via ApplicationSet (ADR-0016)

Decision #14 above, built this session. **In-cluster ECR auth keys off the real
`*.dkr.ecr.*` host**, so the host can't be faked — it must be injected at *render*
(self-heal reverts post-apply edits). Mechanism:
- **Shim** `gitops/bootstrap/resolve_ecr_host.sh` → host from `get-caller-identity`.
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
- No confidential-computing specifics (TASK: "works now ⇒ works with CC"). We *nod* to CC instance families + attestation in the security doc only.
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
- **v0.8 (2026-06-17):** Captured the **conductor + multi-account direction** (new §9, directional/not-built) from the 2026-06-15/17 design discussion, and sharpened §3: the conductor reclassified from a per-env layer to a **temporary, per-account, single-purpose IaC distributor** (sibling of bootstrap/identity, not hub-and-spoke); state-backend extended to the **per-account** form (bucket+CMK per account, envs key-separated within; conductor tied to its account's state); a **one-fine-grained-PAT** conductor GitHub credential decision (refines "scope to job" = no broader than needed, not one-token-per-call). §9 records: clone+pipe deploy delivery (vs S3 ship + on-box monolith), optional least-priv cross-account shared-services chosen at bootstrap (rationale: a unified vuln-scanning regime), and the **dual-mode ECR** (pull-selective by default + push-for-hotfix via replication). No code yet — the next major pass; gated behind finishing item 3 + a live test.
- **v0.7 (2026-06-15):** Post-delivery refactor begins (BACKLOG items 1–4). **Promoted this SPEC from `notes/` to the repo root as the design source of truth**; CLAUDE.md now delegates standing decisions here (§3) instead of duplicating them — one home (cand-004 SSOT). New/updated §3 decisions: **environment layout model B** (single-source `terraform/stack/aws/<layer>` + per-env tfvars — the promotion gate is separate *instances*, not duplicated source); **state backend** simplified to ONE bucket + ONE CMK, env split by S3 object key, driver-composed at init (the gitignored per-env `backend.hcl` retired); folded the previously CLAUDE-only decisions (GitOps ApplicationSet, CI-agnostic, ops-from-toolbox, saved-plan, account-bearing-values-derived) into §3 and corrected the stale "app-of-apps" wording. Item-1 pass also landed: `operator()` installs EBS CSI+gp3 (was a doc-vs-body lie), driver backend-block preflight + resume-on-failure, standalone/DR path de-pinned from `brzl-dev-*`. `10-network` is the first migrated stack layer (prototype).
- **v0.6 (2026-06-04, late):** Full live arc. AWS bring-up `10→50` + KMS migration + k3s HA (Ansible) + the **ApplicationSet** GitOps (ADR-0016, account-id-free) — all 6 apps Synced/Healthy; **CNPG 3/3 HA, failover drilled** (promote, 0 data loss); **monitoring** (kube-prometheus-stack + CNPG + custom app/DB overview dashboard); **demo-app evolved into a Sefaria search web app** (borrowed `chofesh` client; persists searches/results/api-calls; app-level Prometheus metrics + ServiceMonitor); **backup drilled** (CNPG→S3, CMK, instance-profile). Then a **full teardown as a DR test** (destroyed `10–50` incl. `40-ecr`, kept only `15-kms` backups+CMKs; restore = pending A2). Fixed the **state-bucket TF_VAR fragility** (now derived from caller identity). **Local-dev (k3d) built** (ADR-0015 → built: overlay + `k3d_up.sh`, upstream/imported images, local-path, AWS-free; verified first try). **Operator SSO gateway** (§4.1b) designed then re-targeted to build **local-first** on k3d with **Dex/GitHub**, trusted certs via **Let's Encrypt + FreeDNS DNS-01** over `*.sso.barzel.sh` — in progress.
- **v0.5 (2026-06-04):** Resolved decision 12 (§7): app↔DB credential projection via **External Secrets Operator** (ADR-0014) — demo app moved to its own `demo` namespace; CNPG `pg-app` projected by a least-priv reader SA + `ClusterSecretStore` + `ExternalSecret`, DSN templated to the `pg-rw` FQDN. Built `apps/demo-app` (Go+pgx, arm64 distroless ~19MB, offline-verified end-to-end against PG17) + its GitOps bundle (wave 3). EBS-CMK → `15-kms` state migration **performed** (state rm/import; apply pending next bring-up — UPGRADE.md). Added `SECRETS.md` credential inventory. Resolved decision 13: **local-dev k3d parity — design accepted, build deferred** (ADR-0015) to protect the delivery buffer.
- **v0.4 (2026-06-03):** Resolved decisions 7–10 (§7): ArgoCD app-of-apps + sync waves under an `brzl-dev` AppProject, bootstrapped via Helm then self-managed (ADR-0013); read-only GitHub deploy key for the private repo; ECR pull-through extended to quay.io + ghcr.io (credential-ARN-gated; node role given create-on-pull import perms, ADR-0008); `__ECR_REGISTRY_HOST__` sentinel keeps the account id out of committed GitOps manifests. Scaffolded `gitops/clusters/dev` (root + project + child apps), `gitops/infrastructure/{argocd,ebs-csi}` values, `gitops/bootstrap/` (install script + deploy-key `.example`). EBS CSI + gp3 default SC fold in as the wave-0 infra app. No billable apply run yet (Terraform pull-through/IAM changes + the one-time helm install are gated).
- **v0.3 (2026-06-02):** Resolved decisions 4–6 (§7): single-account PoC + documented account-per-env/customer multi-account (cross-account `assume_role` seam in HCL); managed NAT gateway; configurable `capacity_type` (spot for iteration, on-demand `m6g.large` for demo). Rewrote §8 as cost & lifecycle posture (per-hour cost model, destroy-compute-between-sessions now → automated same-session teardown at delivery, expanded descope/cost levers). Bootstrap state backend + identity trust anchor now **applied & smoke-tested** (prior to §7.4–7.6 work).
- **v0.2 (2026-06-01):** Resolved decisions 1–3 (§7): native AWS OIDC + Identity Center (Ory documented); toolbox container + cloud-init bootstrap VM (Packer documented); `terraform/identity/` top-level.
- **v0.1 (2026-06-01):** Initial spec from TASK.md + scaffolding decisions; added differentiators §4.1 (SSO/OIDC) and §4.2 (toolbox/bootstrap containers); delivery target set to 16:00 CEST Wed 10 Jun.
