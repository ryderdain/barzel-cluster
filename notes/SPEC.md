# SPEC.md — End-Design Specification

> **Living document.** This is our current target for *what we are building* to
> answer [`TASK.md`](TASK.md). It is the design/scope counterpart to
> [`PLAN.md`](PLAN.md) (the timeboxed *how/when*). We iterate on this together
> and re-check it against `TASK.md` as we go.
>
> **Delivery target:** **16:00 CEST, Wednesday 10 June 2026** (hard).
> **Status:** v0.6 — MVP + monitoring + backups **live**; AWS torn down after a full DR test; **local-dev (k3d) built**; **operator SSO gateway (Dex/GitHub) in progress on local**. Decisions §7; cost/lifecycle §8; differentiators §4.

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

Carried from [`CLAUDE.md`](CLAUDE.md), plus those made during scaffolding:

- **Kubernetes:** k3s HA (3 servers, embedded etcd).
- **Terraform state:** layered by rate of change (network→security→iam→ecr→compute); strict dev/prod separation; S3 + DynamoDB lock.
- **Compute:** **AWS Graviton / arm64** (`m6g.large` default). Forces arm64 across AMI, k3s, all images/Helm charts, ECR pull-through manifests.
- **Registry:** ECR for images + OCI Helm charts + pull-through cache. **Harbor** = documented production recommendation.
- **Storage:** EBS CSI + gp3 default StorageClass. `local-path` only as a documented descope lever.
- **Backups:** CNPG → S3 (Barman Cloud), authenticated by the **EC2 instance profile** — no second IAM user.
- **Node access:** **SSM Session Manager (SSH-over-SSM)** is the access path — no inbound `:22` (`20-security` `enable_ssh_ingress=false`), node role granted SSM (`30-iam` `enable_ssm=true`), Ansible tunnels via a ProxyCommand using the EC2 instance-id. IAM-gated + audited; the TF-generated key is break-glass only. *Chosen over the Ansible `aws_ssm` connection plugin specifically to avoid its S3 file-transfer bucket — SSH-over-SSM needs none.* Prod hardening (documented): private subnets, no public IP, VPC interface endpoints for `ssm`/`ssmmessages`/`ec2messages`.
- **Encryption:** **customer-managed KMS keys only** (per-purpose: state / ECR / EBS) — never the AWS-managed default keys, for key-policy control, rotation, and grantability (HYOK posture). ~$1/mo per key.
- **Secrets hygiene:** account-id-bearing values (real `backend.hcl`, `*.tfvars`) gitignored; only `.example` templates committed; real values injected at runtime via `TF_VAR_*`.
- **Tooling:** OpenTofu (`tofu`); HCL kept Terraform-compatible.
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

## 9. Changelog
- **v0.6 (2026-06-04, late):** Full live arc. AWS bring-up `10→50` + KMS migration + k3s HA (Ansible) + the **ApplicationSet** GitOps (ADR-0016, account-id-free) — all 6 apps Synced/Healthy; **CNPG 3/3 HA, failover drilled** (promote, 0 data loss); **monitoring** (kube-prometheus-stack + CNPG + custom app/DB overview dashboard); **demo-app evolved into a Sefaria search web app** (borrowed `chofesh` client; persists searches/results/api-calls; app-level Prometheus metrics + ServiceMonitor); **backup drilled** (CNPG→S3, CMK, instance-profile). Then a **full teardown as a DR test** (destroyed `10–50` incl. `40-ecr`, kept only `15-kms` backups+CMKs; restore = pending A2). Fixed the **state-bucket TF_VAR fragility** (now derived from caller identity). **Local-dev (k3d) built** (ADR-0015 → built: overlay + `k3d_up.sh`, upstream/imported images, local-path, AWS-free; verified first try). **Operator SSO gateway** (§4.1b) designed then re-targeted to build **local-first** on k3d with **Dex/GitHub**, trusted certs via **Let's Encrypt + FreeDNS DNS-01** over `*.sso.barzel.sh` — in progress.
- **v0.5 (2026-06-04):** Resolved decision 12 (§7): app↔DB credential projection via **External Secrets Operator** (ADR-0014) — demo app moved to its own `demo` namespace; CNPG `pg-app` projected by a least-priv reader SA + `ClusterSecretStore` + `ExternalSecret`, DSN templated to the `pg-rw` FQDN. Built `apps/demo-app` (Go+pgx, arm64 distroless ~19MB, offline-verified end-to-end against PG17) + its GitOps bundle (wave 3). EBS-CMK → `15-kms` state migration **performed** (state rm/import; apply pending next bring-up — UPGRADE.md). Added `SECRETS.md` credential inventory. Resolved decision 13: **local-dev k3d parity — design accepted, build deferred** (ADR-0015) to protect the delivery buffer.
- **v0.4 (2026-06-03):** Resolved decisions 7–10 (§7): ArgoCD app-of-apps + sync waves under an `brzl-dev` AppProject, bootstrapped via Helm then self-managed (ADR-0013); read-only GitHub deploy key for the private repo; ECR pull-through extended to quay.io + ghcr.io (credential-ARN-gated; node role given create-on-pull import perms, ADR-0008); `__ECR_REGISTRY_HOST__` sentinel keeps the account id out of committed GitOps manifests. Scaffolded `gitops/clusters/dev` (root + project + child apps), `gitops/infrastructure/{argocd,ebs-csi}` values, `gitops/bootstrap/` (install script + deploy-key `.example`). EBS CSI + gp3 default SC fold in as the wave-0 infra app. No billable apply run yet (Terraform pull-through/IAM changes + the one-time helm install are gated).
- **v0.3 (2026-06-02):** Resolved decisions 4–6 (§7): single-account PoC + documented account-per-env/customer multi-account (cross-account `assume_role` seam in HCL); managed NAT gateway; configurable `capacity_type` (spot for iteration, on-demand `m6g.large` for demo). Rewrote §8 as cost & lifecycle posture (per-hour cost model, destroy-compute-between-sessions now → automated same-session teardown at delivery, expanded descope/cost levers). Bootstrap state backend + identity trust anchor now **applied & smoke-tested** (prior to §7.4–7.6 work).
- **v0.2 (2026-06-01):** Resolved decisions 1–3 (§7): native AWS OIDC + Identity Center (Ory documented); toolbox container + cloud-init bootstrap VM (Packer documented); `terraform/identity/` top-level.
- **v0.1 (2026-06-01):** Initial spec from TASK.md + scaffolding decisions; added differentiators §4.1 (SSO/OIDC) and §4.2 (toolbox/bootstrap containers); delivery target set to 16:00 CEST Wed 10 Jun.
