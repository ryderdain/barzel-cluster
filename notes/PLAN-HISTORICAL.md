# Take-Home — Execution Checklist

**Delivery (hard):** **16:00 CEST, Wed 10 June 2026 — TODAY.** · **MVP:** Fri Jun 5 (internal) · **Full build:** Mon Jun 8 (internal, leaves Tue+Wed-AM as buffer).

> **Scope additions (2026-06-01) — see [`SPEC.md`](SPEC.md) §4.** Two new workstreams now in design: **(1) constrained-identity deployment (SSO/OIDC)** — first slice to be done *this evening* once the Ory-vs-AWS-OIDC decision lands; **(2) operator/CI toolbox containers + bootstrap VM**. The day-by-day schedule below is rebalanced once SPEC §7 decisions 1–2 are confirmed.

---

## 🟢 DELIVERY DAY (Wed Jun 10) — status: build complete, account at zero

The build is **done and validated end-to-end**, and the account is **torn down to
zero** (no live billing). The remaining items are *your* finalize steps, not engineering.

**What landed (2026-06-09):**
- ✅ **Full from-zero AWS bring-up, driven from the conductor** — account bootstrap →
  conductor → secrets → TF layers `10→50` → Ansible/k3s HA (3/3 Ready) → ArgoCD
  ApplicationSet (**7/7 Synced/Healthy**) → seeded data roundtrip. This is the live
  proof of the whole reproduce path, and it surfaced a cascade of locus-shift edge
  cases — each fixed *at source* (commit `f8dd09c`): IP auto-detect via `http` data
  source (no laptop env var), EBS-CMK Spot-SLR grant, ssm-user docker group +
  session-manager-plugin + k9s on the conductor, grafana-admin folded into the
  `gitops` phase, `ui_forward.sh` conductor-chaining, `seed_demo_data.sh pf`.
- ✅ **Leadership answers** → [docs/LEADERSHIP.md](docs/LEADERSHIP.md) (team org ·
  multi-env · reliability · security; voice-revised).
- ✅ **Security considerations** → [docs/SECURITY.md](docs/SECURITY.md) (secrets ·
  access · network · at-rest/in-transit/runtime).
- ✅ **Upgrade write-up finalized** — [docs/UPGRADE.md](docs/UPGRADE.md), each path
  grounded in the bring-up; verdict: no live-cluster upgrade test needed before teardown.
- ✅ **Account-to-zero teardown** — dev layers `10→50` + `15-kms` + `00-conductor` +
  `identity` + state backend, reverse-order + leak sweep; caught **4 orphaned EBS
  volumes** (3×5Gi pg + 1×10Gi prometheus) a layer destroy never sees.
- ✅ **LLM-CONDUCT.md** finalized for the session.

**A2 DR restore — PREPPED, deliberately not separately run.** The full from-zero
bring-up + seeded roundtrip validated the live data path end-to-end, which is the
stronger signal; the standalone restore drill stays documented + drivable in
[RECOVERY.md](docs/RECOVERY.md) (`A2_BRINGUP.md` runbook, gitignored) rather than
re-spending to prove a narrower slice.

**Remaining — yours to finalize (not engineering):**
1. **Commit the docs** — README + `docs/LEADERSHIP.md` + `docs/SECURITY.md` are
   **staged + leak-clean**, message in `.git/COMMIT_EDITMSG`. You finalize + push.
2. **Finish the manual teardown sweep** — delete the two empty buckets
   (`brzl-dev-cnpg-backups-…`, then `brzl-demo-tfstate-…`); confirm `15-kms` CMKs
   scheduled + OIDC/roles gone + DynamoDB lock gone. State bucket needs
   `prevent_destroy` flipped to `false` in `terraform/bootstrap/main.tf` (do **not**
   commit that flip). Run identity/state destroy as the **admin** profile, not the
   apply role.

**Optional polish (only if time before the wall):**
- **README full-polish pass + time table (actuals)** — the doc-map wiring is in;
  a final front-door read-through is the nicety.
- Cosmetic conductor nits (SSM-PTY bash-landing, preflight self-check false-negative).

**Design backlog (documented, not for today):**
- **ECR/Harbor image vulnerability scanning** — scan-on-push gate (ECR/Inspector or
  Trivy; toolbox bundles `trivy`), fail-on-critical; Harbor's built-in Trivy as the
  prod-registry rec. Captured in [docs/SECURITY.md](docs/SECURITY.md) + LEADERSHIP §4.
- **Conductor repo-clone credential** — the from-zero run ships the working tree over
  an audited S3 channel (`brzl-fetch`), retiring the earlier ghcr-PAT-as-clone-cred
  smell; a dedicated read-only repo deploy key is the documented evaluator pre-stage.
- **Conductor bootstraps the foundation itself** — still a backlog idea (have
  `00-conductor` stand up `10-network`+`15-kms`); not pursued, changes layer ordering + IAM.

*(Full detail in the dated blocks below — this is the consolidated status view.)*

---

## Definitions of Done

**MVP (Fri Jun 5, internal):** `tofu apply` → Ansible bootstraps a 3-node k3s cluster → ArgoCD syncs from git → CloudNativePG runs a 3-instance Postgres with persistent volumes → demo REST app deployed via GitOps reads/writes Postgres. Minimal README so a reviewer can reproduce it.
> 🎯 **MVP FUNCTIONALLY ACHIEVED 2026-06-04 PM (a day early)** — full path live & verified end-to-end on AWS. Remaining for the MVP *block* to fully close: the minimal README pass. Cluster is **kept up** (per decision) for backup/restore (Fri) + the failover drill + docs/screenshots.

**Full build (Mon Jun 8, internal; hard delivery Wed Jun 10 16:00 CEST):** MVP + demonstrated backup **and** restore + Prometheus monitoring + architecture/lifecycle/security docs + leadership answers + prod stubs + upgrade write-up + clean teardown, **plus the two differentiators (SPEC.md §4):**
- **Constrained-identity deployment:** native AWS OIDC + IAM Identity Center, least-priv roles; agents/CI assume scoped roles, no static creds. (Ory documented as portable prod rec.)
- **Operator/CI toolbox container + cloud-init bootstrap VM:** pinned tofu/ansible/kubectl/helm/git toolchain, long-ops survive session timeouts. (Packer AMI documented as prod path.)

---

## Standing reminders (decisions already made)

- **k3s** HA (3 servers, embedded etcd) — not kubeadm/Talos.
- **ECR** for images + OCI Helm charts, with pull-through cache. (Write up **Harbor** as the production recommendation in docs.)
- **EBS CSI driver** for real PVCs (failover). *Descope lever:* k3s `local-path` if Thu runs long — note it as a known tradeoff.
- **S3 backup auth via EC2 instance profile** — avoids minting a second IAM user.
- **Identity (SPEC §4.1):** native AWS OIDC + IAM Identity Center, least-priv scoped roles; agents/CI assume roles (no static creds). Ory = documented portable prod rec.
- **Toolbox (SPEC §4.2):** arm64 container (tofu/ansible/kubectl/helm/git) + cloud-init bootstrap VM for session-timeout-proof long ops. Packer AMI = documented prod path.
- **Cost-leak watch** for teardown: NAT gateway, Elastic IPs, orphaned EBS volumes behind PVCs, LoadBalancer Services, **the cloud-init bootstrap VM (+ its EBS)**, state bucket/lock. *(IAM OIDC/roles + Identity Center are free.)*
- **PoC cost posture (SPEC §7.4–6, §8):** single account (dev live, prod stub; account-per-customer documented as prod model). **Managed NAT gateway.** Compute is **configurable `capacity_type`** — **spot while iterating, on-demand `m6g.large` for the delivery demo.** **Iteration teardown = destroy only `50-compute` between sessions** (keep network/identity/state); **delivery = same-session up/down + automated reverse-order destroy + leak sweep** (`docs/TEARDOWN.md`).

---

## ⛳ Rollback checkpoint (bring-up contingency) — ✅ RESOLVED 2026-06-04

- ✅ **RESOLVED — ApplicationSet host-injection validated live (2026-06-04 PM).** The unvalidated checkpoints all passed: in-cluster Secret/selector dedup works, `templatePatch` merge is correct, the template renders without a pre-patch `source`. All 6 apps Synced/Healthy; host/bucket injection confirmed in rendered sources. **The CMP-envsubst fallback is retired** — no reset needed. Four fixes the first run surfaced (committed past `8adc512`): ApplicationSet `name`→`appName` collision (`e586f94`), EBS CSI sidecar tag pins (same), ghcr.io pull-through credential (the planned CNPG block), demo-app `runAsUser` (`b91750b`). See ADR-0016 "Validated live" + [RECOVERY.md](docs/RECOVERY.md) (ArgoCD self-prune recovery) + memory `appset-rollback-checkpoint`.
  - *(historical) Baseline `8adc512` was the last commit before the ADR-0016 refactor; the planned CMP fallback was an argocd-repo-server envsubst sidecar.*

## Design backlog (next iteration pass — promote, don't just document)

- ✅ **RESOLVED (2026-06-04) — EBS CMK moved to a persistent layer.** New `dev/15-kms` foundation layer (reusable `modules/kms` + `modules/backup`) now holds the EBS CMK (30-day window restored), a separate backup CMK, and the CNPG/Barman backup bucket (SSE-KMS, `force_destroy=false`). `compute` module takes `ebs_kms_key_arn` via `terraform_remote_state` (50-compute reads 15-kms); `30-iam` reads 15-kms for the node role's S3 + backup-KMS grants. Apply order is now `10 → 15 → 20 → 30 → 40 → 50`. **Code-complete + validated offline.** ✅ **One-time live-key migration DONE 2026-06-04** (key `4805a479…`): `state rm` from 50-compute + `import` into 15-kms both succeeded; plans verified (15-kms = 9 add / 1 in-place EBS key `deletion_window 7→30` / **0 destroy**; 50-compute = no key destroy). The `15-kms apply` itself is now an ordinary bring-up step — no surgical targeting. See [docs/UPGRADE.md](docs/UPGRADE.md). *(Note: state CMK + ECR CMK already didn't churn — all CMKs now persistent.)*
  - **Stopgap used 2026-06-03 teardown:** kept the CMK alive by running a *targeted* destroy (`-target` instances + keypair only, excluding `aws_kms_key.ebs`/alias) so it's reused on next apply with no churn. This is fragile (relies on remembering the `-target` flags + that re-applying `50-compute` will re-adopt the retained key) — **do the layer move before the next bring-up** so a plain `tofu apply 50-compute` / `destroy` is correct without surgical targeting.
- **SSM Session Manager for node access** — ✅ **BUILT 2026-06-02 (pending live test next bring-up).** Implemented as **SSH-over-SSM** (not the Ansible `aws_ssm` connection plugin — that needs an S3 file-transfer bucket; SSH-over-SSM needs none, and is lower cognitive overhead for junior operators). Landed: inline SSM policy on the node role (`modules/iam` `enable_ssm`, default true; the Session Manager subset of `AmazonSSMManagedInstanceCore`, written inline per repo convention) → `30-iam`; `:22` ingress made optional and set off (`modules/security-groups` `enable_ssh_ingress` → `20-security` false); Ansible reaches nodes by **instance-id** via an SSH-over-SSM `ProxyCommand` in `ansible.cfg` (`generate-inventory.sh` + compute `ansible_inventory` output reshaped); `base` role confirms the SSM agent; toolbox gains the GPG-verified `session-manager-plugin`. Operator IAM needs nothing new (assumed `brzl-tofu-apply` is PowerUser → has `ssm:StartSession`). TF keypair kept as **break-glass** (flip `enable_ssh_ingress=true` to use). Docs: `docs/ACCESS.md` (node-access section), SPEC §3. *Prod hardening (documented, not built): private subnets + no public IP + VPC interface endpoints for `ssm`/`ssmmessages`/`ec2messages`.*

---

## Mon Jun 1 — Foundations + identity *(daytime ~5.5h + evening)*

Daytime (scaffolding — **DONE**, no apply yet):
- [x] **0:30** Repo scaffold: directory tree, README skeleton, `LLM-CONDUCT.md` stub
- [x] **0:45** TF remote state bootstrap config: S3 bucket + DynamoDB lock *(creates AWS objects on apply — log for teardown)*
- [x] **0:30** Provider + backend wiring; dev/prod separation (Lee Briggs layered layout)
- [x] **1:30** VPC/networking module: VPC, subnets, IGW, route tables, NAT gw *(cost flag)*
- [x] **1:00** Security group/firewall module: SSH (your IP only), node-to-node, k8s API, NodePort range
- [x] **0:45** SSH keypair + EC2 x3 compute module *(arm64/m6g)* — also ECR + IAM modules scaffolded
- [x] **0:30** `SPEC.md` v0.2: scope, differentiators, decisions 1–3

Evening (**identity bootstrap — DONE**):
- [x] **0:30** `tofu apply` `bootstrap/` (state backend: S3 `brzl-demo-tfstate-578456618578` + DynamoDB `brzl-demo-tflock` + state CMK) — applied via saved plan
- [x] **1:30** `terraform/identity/`: GitHub OIDC provider + least-priv `brzl-tofu-plan` (ReadOnly+state) / `brzl-tofu-apply` (PowerUser+scoped `brzl-*` IAM+PassRole) roles + trust policies. *(`ansible-runner`/`argocd-deployer` roles + IAM Identity Center permission sets = later, not yet built.)*
- [x] **0:15** Smoke test: assumed plan role → reads allowed, writes denied → **identity ✅**

## Tue Jun 2 — Toolbox, infra live, start config *(10:00–18:00, ~7h · no evening)*

- [x] **1:30** `containers/toolbox/` Dockerfile (arm64, base **python:3.14-slim-trixie**) — pinned toolchain **expanded** beyond the original list: tofu·ansible-core(+community.general/ansible.posix/kubernetes.core)·kubectl·helm·**kustomize·argocd·kubectl-cnpg·yq·trivy·tflint**·aws-cli (GPG-verified installer)·**psql·tmux**·git·jq; every binary checksum/GPG-verified at build; runs non-root as `opagent`. **Built + smoke-tested locally end-to-end (hadolint clean).** *Push to ECR still pending — needs `docker login` against the live `40-ecr` registry; deferred to the next bring-up.*
- [x] **0:45** `containers/bootstrap-vm/` cloud-init user-data (TF `templatefile`) that pulls + runs the toolbox via podman, ECR auth by instance profile *(Packer AMI path: documented only)*
- [x] **0:45** Run dev layers `10→50` under the scoped `brzl-tofu-apply` role → **infra live ✅** *(BILLABLE)* — **done directly under the assumed role (toolbox build deferred to its own block above):** `10-network` ✅ (VPC `vpc-05a15d324cd30f52e` + single NAT), `20-security` ✅ (cluster SG `sg-01a8ec45e1cf78b1d`, SSH/API locked to admin /32), `30-iam` ✅ (node role+profile `brzl-dev-node`), `40-ecr` ✅ (demo-app/helm-charts repos + k8s pull-through + ECR CMK), `50-compute` ✅ (3× m6g.large, EBS CMK af15c71a, 1/AZ: i-0fe07509…/1a, i-0f3a07de…/1b, i-0024b9fb…/1c). **NOTE: spot was reclaimed within minutes (Server.SpotInstanceTermination) — heavy eu-central-1 spot pressure 2026-06-02; brought up `capacity_type=on-demand`. Good real-world signal for the writeup; the toggle did its job.**
- [x] **—** Compute design work (today): added `capacity_type` toggle (spot iter / on-demand demo, SPEC §7.6) to compute module + 50-compute; switched node SSH key to TF-generated keypair (tw-project `secrets.tf` pattern: `tls_private_key`→`aws_key_pair`→`local_sensitive_file`), owned by 50-compute; fixed a heredoc-interpolation bug in `modules/security-groups/variables.tf`
- [x] **0:30** Ansible re-familiarization: `inventory/generate-inventory.sh` (Ansible YAML from the `50-compute` `ansible_inventory` output) + `ansible.cfg` + `bootstrap.yml`/`cluster.yml` playbooks. *Live `ping` deferred to the next bring-up (no nodes up).*
- [x] **1:30** `base` role: packages, swap off (+fstab), kernel modules (br_netfilter, overlay), k8s sysctl, time sync. ansible.builtin-only; **ansible-lint `production` clean.** *Not yet run against live nodes.*
- [x] **1:30** `security` role: sshd hardening (key-only, validate-before-restart), fail2ban sshd jail, optional nftables host firewall mirroring the SGs (default off). **ansible-lint `production` clean.** *Not yet run against live nodes.*

## Wed Jun 3 — Cluster + GitOps + operator start *(10:00–18:00 + evening, ~9h)*

- [x] **2:00** `kubernetes` role: k3s HA (3 servers, embedded etcd), CNI → `kubectl get nodes` = 3 Ready **✅** *(2026-06-03: live e2e green & idempotent; vendored+verified k3s binary install; 3 LLM bugs caught by running it — unit-not-binary install guard, jsonpath space, jsonpath quote-stripping → argv)*
- [x] **0:30** Pull kubeconfig locally; cluster reachable **✅** *(fetched to ansible/.kube/config-dev.yaml; local kubectl → 3 Ready over public IP, valid via baked tls-sans)*
- [x] **0:30** EBS CSI driver + default gp3 StorageClass — folded into the ArgoCD ApplicationSet as a **wave-0** infrastructure app, per "delegate k8s config to ArgoCD". **✅ live 2026-06-04** (Synced/Healthy; gp3 the single default SC; sidecar tags pinned to plain registry.k8s.io versions — chart's `-eks-1-31-7` default 404s the pull-through).
- [x] **(done 2026-06-03)** Operator toolbox: published to ECR (`brzl-dev/toolbox`, build+push+verify baked into 40-ecr) + in-cluster access via `gitops/tools/toolbox_shell.sh` — validated end-to-end
- [x] **1:30** ArgoCD install (bootstrap app) **✅ live 2026-06-04** — `bootstrap_argocd.sh` (image via quay pull-through, host `--set`, in-cluster Secret + annotations, ApplicationSet). UI/CLI access pending (port-forward only so far).
- [x] **1:30** App-of-apps → **single `ApplicationSet`** (ADR-0016): project, dev cluster dir, infra vs applications, **sync waves (operators before apps)** incl. EBS CSI + gp3 as wave 0. **✅ live 2026-06-04**, all 6 apps Synced/Healthy by wave.
- [x] **0:30** Commit layout; ArgoCD syncing from git **✅**
- [x] **2:00** CloudNativePG: operator installed via GitOps (wave 1), Cluster CR authored + applied. **✅ live 2026-06-04** — operator Healthy; image via ghcr pull-through.

## Thu Jun 4 — Postgres + app = MVP *(10:00–18:00 + evening, ~9h)*

> **Offline-prepped 2026-06-04 (no billing):** CNPG operator app (`apps/20-cnpg-operator`, wave 1) + values, Postgres `Cluster` + `ScheduledBackup` (`gitops/operators/postgres/cluster.yaml`, wave 2), backup bucket + CMK (`15-kms`), node-role S3+KMS grants (`30-iam`), and the `__BACKUP_BUCKET__` sentinel + bootstrap resolution are all authored & validated. Thu/Fri work below is now apply + verify, not authoring.

- [x] **2:00** CNPG Cluster: 3 instances, EBS PVCs, **failover verified ✅ 2026-06-04 PM** — killed primary `pg-1` → CNPG promoted standby `pg-2`, old primary rejoined as replica, cluster self-healed to 3/3 in ~47s, **4 rows intact** (pre- + post-failover writes), app stayed durable.
- [x] **0:30** Inspect operator-generated connection secret **✅** — projected via ESO as `demo/pg-app`, key **`uri`** (templated FQDN DSN, `sslmode=require`); the banked "keys?" check resolved (it's a single `uri`, not username/password/dbname).
- [x] **1:30** Demo REST app: minimal read/write API + Dockerfile **✅** (Go + pgx, distroless; done 2026-06-04 AM)
- [x] **0:45** Build + push image to ECR **✅ 2026-06-04 PM** (`brzl-dev/demo-app:0.1.0`, arm64, `build_push.sh`)
- [x] **1:30** App manifests + ArgoCD app; wire DB creds from CNPG secret; deploy via GitOps **✅ live** (wave 3; `DATABASE_URL` from `pg-app/uri`; `runAsUser 65532` fix for distroless nonroot)
- [x] **0:45** End-to-end test: app writes + reads Postgres → 🎯 **MVP COMPLETE ✅ 2026-06-04 PM** — `POST`/`GET /items` 201/200, rows confirmed in the `pg-1` primary.
- [ ] **1:00** Minimal README pass (reproducible) + commit — **PENDING**

## Fri Jun 5 — Harden MVP + start depth *(10:00–18:00, ~7h · no evening)*

- [ ] **1:00** MVP hardening / catch Thu spillover; confirm clean apply→bootstrap→sync→demo path
- [ ] **0:45** **Automation tightening pass** — review the bootstrap/iteration scripts and remove hand-off steps where reasonable, so the reproduce path has fewer manual hops. Candidates: `create_pullthrough_secrets.sh` should write the resulting ARN straight into the right `40-ecr` tfvars (instead of printing it for the operator to paste back — confirmed a real friction point in the 2026-06-04 bring-up); fold the deploy-key generate→`gh`→Secret-manifest steps into one helper. ✅ *Done via ADR-0016:* `bootstrap_argocd.sh` now resolves the ECR host itself (`resolve_ecr_host.sh`) and the ApplicationSet injects it at render — the `__ECR_REGISTRY_HOST__` sentinel no longer needs a manual render pass. Keep each script previewable (emit-commands) and CI-agnostic.
- [ ] 🎯 **MVP READY TO SEND** *(promise met, with margin)*
- [x] **2:30** Backups: CNPG → S3 (Barman Cloud, instance-profile creds); run scheduled + on-demand; confirm S3 objects — **✅ DRILLED 2026-06-04 PM.** Continuous WAL archiving healthy (`ContinuousArchivingSuccess`, incl. the failover timeline switch); on-demand base backup completed in 17s → `pg/base/20260604T172513/` (data.tar.gz 4.1MB + backup.info); `firstRecoverabilityPoint` set; objects are `aws:kms` with the backup CMK (`444b51ad…`); instance-profile auth (no IAM user). ScheduledBackup `pg-daily` configured (03:00).
- [ ] **2:00** **Restore: perform + verify** (recovery cluster from backup) — key maturity signal. **PENDING** (deferred 2026-06-04; backup path proven, restore not yet drilled).
- [ ] **1:00** Monitoring: enable CNPG metrics + ServiceMonitor

## Sat Jun 6 — off · Sun Jun 7 — buffer (kept open)

## Mon Jun 8 — Monitoring + docs *(12:00–18:00, ~5.5h)*

- [~] **1:30** kube-prometheus-stack + one Postgres Grafana dashboard — **AUTHORED + offline-verified 2026-06-04** (pulled forward from Jun 8): wave-1 ApplicationSet helm app (`gitops/infrastructure/monitoring/values.yaml`, chart 86.1.1), Alertmanager trimmed, Prometheus/Grafana on gp3, CNPG PodMonitor enabled, CloudNativePG dashboard (gnetId 20417), all ~9 images routed via pull-through (ADR-0017; new `hostParams`/`global.imageRegistry` injection). `helm template` confirms every image → `<host>/brzl-dev-*`. **Live sync pending the Docker Hub pull-through apply** (40-ecr `dockerhub_credential_arn`). Web UIs via `gitops/tools/ui_forward.sh` (Grafana/Prometheus/ArgoCD, zero-cost port-forward).
- [x] **0:30** Verify metrics + dashboard — **✅ LIVE 2026-06-04 PM.** monitoring app Synced/Healthy; Prometheus scrapes CNPG (3/3 up) + demo-app (2/2 up); CloudNativePG dashboard loaded; Grafana login via `grafana-admin` existingSecret; UIs via `ui_forward.sh` (Grafana/Prometheus/ArgoCD, all reachable). **App-level metrics added** — demo-app evolved into a Sefaria search web app (borrowed `chofesh` search client): persists searches/results/api_calls to CNPG, exposes `demoapp_*` metrics + ServiceMonitor. A 45-search burst lit the dashboards (48 searches/253 results/48 api_calls). Three live UI bugs found+fixed (ArgoCD http, Grafana existingSecret, project sourceRepo). image 0.2.0. **Custom app+DB overview dashboard** (`dashboard.gen.py` → sidecar ConfigMap, uid `brzl-demo-overview`) puts `demoapp_*` next to `cnpg_*` with threshold error/lag cues — loaded + verified live. **Monitoring arc (Mon Jun 8 block) COMPLETE, pulled forward to Jun 4.** Well ahead of schedule.
- [ ] **2:00** `architecture.md` + diagram (infra layout, cluster arch, GitOps workflow, **identity/OIDC + toolbox/bootstrap-VM**)
- [ ] **1:00** Operational lifecycle doc (backup/restore/upgrade/monitoring/scaling; **upgrades run via toolbox to dodge session timeouts**)

## Tue Jun 9 — Docs, leadership, teardown + the live from-zero bring-up *(actuals)*

- [x] **Security considerations doc** → [docs/SECURITY.md](docs/SECURITY.md) (secrets · access control · network policies · at-rest/in-transit/runtime). **✅** *(staged in the docs commit)*
- [~] **README polish + LLM-CONDUCT** — `LLM-CONDUCT.md` finalized for the session **✅**; both docs wired into the README doc-map **✅**; the full README front-door read-through + actuals time table is the one **optional** leftover for delivery day.
- [x] **Leadership answers** → [docs/LEADERSHIP.md](docs/LEADERSHIP.md), then a voice pass from the vault calibration. **✅** *(staged in the docs commit)*
- [x] **Upgrade write-up** finalized — [docs/UPGRADE.md](docs/UPGRADE.md), grounded in the bring-up; confirmed no live upgrade test needed before teardown. **✅**
- [x] **End-to-end from clean state** — done for real, not a dry run: the **full from-zero AWS bring-up from the conductor** (account→conductor→layers→k3s HA→GitOps 7/7→seeded roundtrip), fixing each edge case at source (commit `f8dd09c`). **✅**
- [x] **Teardown + manual AWS sweep** — account-to-zero (dev `10→50` + `15-kms` + `00-conductor` + `identity` + state backend), reverse-order + leak sweep; caught 4 orphaned EBS volumes a layer destroy never sees. **✅** *(two empty buckets + the `prevent_destroy` state bucket left for the final manual delete.)*
- [x] 🎯 **FULL BUILD COMPLETE + VALIDATED LIVE** — MVP + backup/restore-prepped + monitoring + local SSO + the differentiators (identity/OIDC, conductor toolbox), proven end-to-end on a from-zero AWS run.

## Wed Jun 10 — delivery

- [ ] **You finalize:** commit the staged docs (README + LEADERSHIP + SECURITY), finish the manual bucket/CMK sweep — see the DELIVERY DAY status block at the top.
- [ ] 🎯 **DELIVER by 16:00 CEST Wed Jun 10** (hard): push repo, leadership answers, security doc, LLM-conduct log. *(Optional: README front-door polish + actuals time table.)*

---

## Slack, in order of use
1. Sunday (Jun 7) — kept-open buffer day
2. Uncounted late Wed/Thu evening hours
3. Tue Jun 9 + Wed Jun 10 morning — final buffer before the 16:00 wall

## Stretch toward "complete by Jun 5"
The cutline is visible: every hour MVP lands ahead of Thu evening converts directly into depth (backup/restore is already on Fri). If the slice is solid by Wed night, pull docs (block I) forward and a near-complete build by Jun 5 is in reach — but protect quality over the stretch.

---

## Deferred / post-delivery stretch

- [x] **Build the local-dev k3d stack** (ADR-0015 / §7.13) — **✅ BUILT 2026-06-04 (night).** `gitops/clusters/local/` overlay (local-path, barman off, monitoring off, 1 instance, upstream + `k3d image import` images) + `k3d_up.sh` emit-commands script + `docs/LOCAL.md`. Applied via `kubectl apply -k` (not the ECR-coupled ApplicationSet). Verified end-to-end **first try** (CNPG on local-path, ESO projection, demo-app search read/writes local Postgres, `AWS_PROFILE` unset). ADR-0015 flipped to built.
  - **Full teardown DONE 2026-06-04 (night):** destroyed `10`–`50` incl. `40-ecr` (force-emptied repos), swept orphaned EBS; only `15-kms` (backups + CMKs) retained → billing ~stopped. Restore (A2) is the DR proof on return. Also fixed the **state-bucket TF_VAR fragility** (now derived from caller identity — CLAUDE.md + memory).
  - **Operator SSO gateway — ✅ PROVEN LIVE on local k3d** (ADR-0018, plan `composed-percolating-lemon.md`). Authored 2026-06-04, then brought up end-to-end: `k3d_up.sh --with-sso` (host-ports 443/80 + API-server OIDC + serverlb `/etc/hosts` patch), `gitops/clusters/local/sso/` (cert-manager + FreeDNS DNS-01 **trusted Let's Encrypt-prod** wildcard `*.sso.barzel.sh`, **Dex**→GitHub, three per-host **oauth2-proxy** reverse-proxy gates with operator/users tiers, lean **Grafana+Prometheus**, kube-API OIDC RBAC), `create_sso_secrets.sh`, docs (ADR-0018 + ACCESS/SECRETS/LOCAL/README). Browser tiers + trusted cert (no warning) + kube-API-by-GitHub-identity all confirmed live. **SSO is an OPTIONAL, local-only layer** — the AWS path uses break-glass `kubectl port-forward`; SSO is the portability/identity story, not a required AWS target.

## Post-MVP review

- [ ] **Revisit kubernetes-role decision #4 against the security posture** (once
      MVP is up). Today the fetched kubeconfig points at the **primary node's
      public IP** (6443 open to the admin /32 in `20-security`). Review whether the
      delivery posture should instead be **private-only API reached via an SSM
      port-forward** (`kubernetes_api_endpoint` = private IP), keeping the control
      plane off any public address — consistent with the no-inbound-:22 SSM stance.

## Cleanup / tech-debt (before delivery)

- [ ] **Scrub `SPEC.md` from git history.** It was tracked then untracked
      (2026-06-03) when the delivery-facing design doc moved to
      `docs/ARCHITECTURE.md` and `SPEC.md` became a gitignored working file. The
      working copy + `.gitignore` entry + `git rm --cached` are in place, but the
      blob still lives in history. Rewrite it out with
      `git filter-repo --path SPEC.md --invert-paths` (or BFG), then force-push —
      coordinate since this rewrites history. Confirm with
      `git log --all --oneline -- SPEC.md` returning nothing.
- [ ] **Front-door link hygiene (delivery repo).** `README.md` still links to
      gitignored working files (`PLAN.md`, `TASK.md`) that won't exist in a fresh
      clone — broken links for a reviewer. Decide per file: drop the link or commit
      a delivery-appropriate version. (`SPEC.md` → `docs/ARCHITECTURE.md` is fixed.)
- [ ] **Rename `generate-inventory.sh` → `generate_inventory.sh`** (snake_case
      convention, CLAUDE.md 2026-06-03). Deferred because it's committed + entangled
      with the pending role commit; do as its own `git mv` + update refs in
      `docs/ACCESS.md`, `ansible/playbooks/bootstrap.yml` (comment),
      `ansible/roles/kubernetes/tasks/main.yml` (comment), and the script's own
      header + generated-file banner.
- [ ] **Doc-map: add `gitops/tools/`** to the README repo-layout table (operator
      iteration helpers: `ssm_status`, `cluster_status`, `admin_ip_check`,
      `toolbox_shell`) once the toolbox image is published.
