# A2 DR-Restore — Run Report

Conductor-driven AWS bring-up + CloudNativePG disaster-recovery restore.
Personal run log for later review (gitignored). Companion to the runbook
`A2_BRINGUP.md` and the delivery-facing `docs/RECOVERY.md`.

- **Run started:** 2026-06-08 (driven remotely; operator hands-off)
- **Driver:** `gitops/tools/a2_restore.sh` on the conductor, via `aws ssm send-command`
- **Acceptance target:** `items=4 · searches=84 · search_results=423 · api_calls=84`
- **Conductor:** `i-0e1c0d3bc9d46af70` (t4g.small, AL2023 arm64), VPC `vpc-0444556ba54a464da`, SSM-only
- **Account / region:** `578456618578` / `eu-central-1`

---

## Phase 0 — Scaffolding committed

- Commit `9191c37` `feat(ops): conductor layer + sourceable A2 DR-restore driver` (pushed to `main`).
- 16 files: 00-conductor layer, runlib, a2_restore driver, recovery renderer, 4 refactored scripts.

## Phase 1 — Conductor apply (00-conductor)  ✅

- `tofu apply tfplan` → **12 added, 0 changed, 0 destroyed**.
- Outputs: instance `i-0e1c0d3bc9d46af70`, public IP `3.79.56.89`, VPC `vpc-0444556ba54a464da`.
- SSM: `PingStatus=Online`, agent `3.3.4108.0`, AL2023.

## Phase 2 — Conductor setup + repo transfer  ✅ (after one snag)

- cloud-init `status: done`; toolchain present: tofu/kubectl/helm/ansible/aws/git/jq/docker.
- **Snag:** repo clone via the ghcr pull-through PAT → **HTTP 403** (token is `read:packages`-scoped,
  not repo-clone). Logged as a follow-up (dedicated read-only repo cred needed).
- **Resolution (one-off):** shipped the committed tree via the state bucket — `git archive HEAD`
  (176 K, 265 files) → `s3://brzl-demo-tfstate-578456618578/conductor-transfer/` → conductor
  downloaded + extracted (194 files) via its instance role. No GitHub cred needed; no secrets in transit.
- `backend.hcl` written (derived bucket); `40-ecr` tfvars auto-populated from the existing ASM
  secrets (`write_arns_to_tfvars`): ghcr + dockerhub credential ARNs.

## Phase 3 — Preflight (FREE)  ✅

- Identity: `arn:aws:sts::578456618578:assumed-role/brzl-dev-conductor/i-0e1c0d3bc9d46af70`
  (instance-role creds; no `AWS_PROFILE` — dual-locus path confirmed).
- **Backups intact:** `s3://brzl-dev-cnpg-backups-578456618578/pg/base/20260604T183915/`
  → `data.tar.gz` (4.1 MB) + `backup.info`. Dataset recoverable.
- `backend.hcl` present; pull-through secrets present.

---

## Phase 4 — Layers (10→50)  💸  ✅

- Driver `layers` (ASSUME_YES, saved-plan per layer) → **Success** (exit 0; all 5 layers applied).
- `TF_VAR_mycurrentip` = conductor egress IP (admin /32); `capacity_type=on-demand`;
  `toolbox_build_enabled=false` (DR drill needs no toolbox image — removes a Docker-Hub-pull risk).
- Verified via AWS describe:
  - **3× m6g.large running, 1/AZ:** 1a `i-038f7eed975f41fde` (10.10.101.139), 1b `i-0d00d88db1ac8eb5d`
    (10.10.102.110), 1c `i-07ca3c8640fa5eda8` (10.10.103.238).
  - NAT `nat-0ea4440e78f705848`; ECR repos `brzl-dev/{demo-app,helm-charts,toolbox}`;
    registry host `578456618578.dkr.ecr.eu-central-1.amazonaws.com`.

## Phase 5 — Images (demo-app build+push)  💸  ✅

- Driver `images` → **Success**. Native arm64 build on the conductor (no QEMU), ECR auth via
  instance role. `demo-app:0.2.0` pushed → digest `sha256:9575fa809bc1311777885dbe6e97aa5a2bf9817a8f53f002d660ec7de852084b`.

## Phase 6 — Cluster (k3s HA via Ansible + kubeconfig)  💸  ✅

- Prep: install `session-manager-plugin` (arm64) on the conductor for the SSH-over-SSM
  ProxyCommand; node key `~/.ssh/brzl-dev-node` present (written by 50-compute on the conductor).
- `AWS_DEFAULT_REGION=eu-central-1` exported (SSM tunnel needs it).
- **Result ✅** — `session-manager-plugin` installed; SSH-over-SSM worked. Ansible PLAY RECAP:
  node-1 `ok=25 failed=0`, node-2/3 `ok=17 failed=0`, `unreachable=0`. k3s HA (3 servers,
  embedded etcd) up; kubeconfig fetched; API endpoint `https://3.66.235.9:6443` (node-1 / 1a).
- Note: merged kubeconfig landed at `/.kube/config` (root HOME quirk in the SSM shell) — later
  phases export `KUBECONFIG=ansible/.kube/config-dev.yaml` explicitly.

## Phase 7 — Operator (standalone CNPG)  💸  ✅

- 3 nodes Ready (`v1.31.5+k3s1`, Ubuntu 24.04, all control-plane/etcd/master).
- `cnpg-operator` helm install → deployed; pod `cnpg-operator-cloudnative-pg-…` `1/1 Running`.

## Phase 8 — Storage + Recover (CNPG DR from S3)  💸  ✅

- **Driver gap found:** the standalone `operator` phase doesn't install storage (EBS CSI +
  gp3 is a wave-0 GitOps app), so the recovery `Cluster`'s gp3 PVCs would hang Pending.
  Installed EBS CSI inline (chart 2.37.0, repo `ebs-csi/values.yaml`, sidecars via the
  `brzl-dev-k8s` pull-through, gp3 default; node instance-profile creds). **TODO: fold EBS
  CSI + gp3 into the driver's `operator` phase for the standalone path.**
- Then driver `recover`: `render_recovery_manifest.sh` (resolves ECR host + backup bucket
  from SSM) → `kubectl apply` → wait healthy.
- **Result ✅** — EBS CSI rolled out; `gp3 (default)`, local-path demoted. Recovery `Cluster pg`
  bootstrapped from S3 (`bootstrap.recovery`, serverName `pg`): **3 instances, 3 READY,
  "Cluster in healthy state"**, primary `pg-1`; 3 PVCs Bound on gp3 (EBS via instance profile);
  pods pg-1/2/3 `1/1 Running`. (Cosmetic: driver `printf '--- preview…'` → `printf: --: invalid
  option`; harmless, render ran. **TODO: fix to `printf '%s\n'`.**)

## Phase 9 — Verify (acceptance counts)  ✅  🎯 DR PROVEN

```
OK  items           4
OK  searches        84
OK  search_results  423
OK  api_calls       84
```
`ACCEPTANCE PASS — DR proven (4/84/423/84)`. The dataset survived a full teardown purely via
the S3 backups and was restored onto a freshly rebuilt stack, end-to-end from the conductor.

---

## Outcome

**A2 disaster-recovery exercise: PASS.** Bring-up + restore driven entirely from the disposable
`00-conductor` over SSM (instance-role creds, no laptop cluster access), using the new
`a2_restore.sh` orchestrator + sourceable per-action scripts.

### Follow-ups surfaced during the run
1. **Conductor repo-clone cred** — ghcr pull-through PAT can't clone (403, `read:packages` scope);
   used an S3 tarball transfer as a one-off. Needs a dedicated read-only repo credential.
2. **Driver `operator` phase** should install EBS CSI + gp3 for the standalone path (done inline this run).
3. **Driver cosmetic** — `printf '--- preview…'` must be `printf '%s\n' '--- …'`.
4. **Docs** — flip `docs/RECOVERY.md` "Database restore / PITR" + the DR-test block to ✅; tick
   PLAN.md "Restore: perform + verify".

## Teardown — FULL, zero footprint  ✅

Per "leave nothing behind / zero footprint." Order: apply-role work first, then admin for the
foundation (since the apply role itself is deleted).

- **Dev `50→10`** (laptop, apply role): 50-compute 5✗; 40-ecr stopped on `RepositoryNotEmpty`
  (demo-app held `0.2.0`) → emptied repo via `ecr batch-delete-image` → 40-ecr 2, 30-iam 7,
  20-security 8, 10-network 23 destroyed (NAT/VPC gone).
- **Backup bucket emptied** (all versions → 0; CNPG backups deleted) + state-transfer tarball removed.
- **`15-kms`** destroyed (11; EBS+backup CMKs → PendingDeletion). **`00-conductor`** destroyed (12).
- **identity** destroyed (7, as admin `rdain`). **State bucket** emptied (all versions) →
  **`terraform/bootstrap`** destroyed (7; needed a temporary `prevent_destroy=false` flip, then
  `git restore` so the committed guard stays). State CMK → PendingDeletion.
- **Orphan/leak sweep** caught + removed: **3 CSI-provisioned EBS volumes** (recovery PVCs, not in
  any tofu state) and **6 ECR pull-through cache repos** (auto-created on pull); **3 pull-through
  secrets** force-deleted.
- **Final state:** no EC2/NAT/EIP/EBS/LB/VPC/ECR/S3/DynamoDB/IAM-role/OIDC; all brzl CMKs
  `PendingDeletion` (no charge). Only the `rdain` admin user remains.

### Teardown gotchas worth folding into TEARDOWN.md / the driver
1. ECR repos are **not** `force_delete` — empty before `tofu destroy 40-ecr`.
2. `terraform/bootstrap` state bucket has `prevent_destroy` — flip + restore for a true zero teardown.
3. **Orphans tofu never sees:** CSI-dynamic EBS volumes + ECR **pull-through cache** repos +
   the script-created pull-through **secrets**. A leak sweep must target these explicitly.

