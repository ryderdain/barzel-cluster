# Runbook — Backup & Recovery

Audience: operators handling backups, restores, and failures. Companion:
[BOOTSTRAP.md](BOOTSTRAP.md), [UPGRADE.md](UPGRADE.md).

Status legend: ✅ live · 🔜 pending.

## Database backups (CloudNativePG → S3 / Barman Cloud) ✅ (drilled)
- **Drilled 2026-06-04:** continuous WAL archiving healthy
  (`ContinuousArchivingSuccess`); on-demand `Backup` CRs complete in ~15–20s →
  `pg/base/<ts>/` (`data.tar.gz` + `backup.info`); objects are `aws:kms` with the
  backup CMK; auth via instance profile. `firstRecoverabilityPoint` advances.
- **Auth:** the EC2 **instance profile** (no second IAM user) — see
  [../CLAUDE.md](../CLAUDE.md). The backup bucket is **customer-managed-KMS** encrypted.
- **Scheduled:** a `ScheduledBackup` CR (cron) under `gitops/operators/postgres/`.
- **On-demand:** `kubectl cnpg backup <cluster>` (or a `Backup` CR).
- **Verify a backup exists:**
  ```sh
  kubectl get backups.postgresql.cnpg.io
  aws s3 ls s3://<backup-bucket>/<cluster>/base/ --recursive | tail
  ```
  A backup that hasn't been **restore-tested** is a hope, not a backup.

## Database restore / PITR ✅ (drilled 2026-06-08)
CNPG restores by **bootstrapping a new cluster** from the object store (the
original is left untouched). The full-teardown drill below proved it live.
1. Create a recovery `Cluster` with `bootstrap.recovery` pointing at the backup
   (and a target time for PITR) under `gitops/`. PR → sync.
2. Wait for it to reach the recovery target and become primary; check
   `kubectl get cluster` + `kubectl cnpg status <recovery-cluster>`.
3. **Verify data**, then cut the app over (update the DB host/secret reference in
   `gitops/applications/demo-app/`). PR → sync.
- **Drill cadence:** run a restore drill on a schedule, not just after an incident.

### Full teardown + restore DR test ✅ (passed 2026-06-08)
A complete disaster-recovery exercise, run and **passed 2026-06-08**: everything
below `15-kms` (`10`–`50`, including `40-ecr` and the network) was torn down,
keeping only the persistent `15-kms` foundation (CMKs + the CNPG backup bucket).
The dataset survived **purely through the S3 backups** and was restored on a
freshly rebuilt stack — driven end-to-end from the disposable conductor
(`platform.sh restore`: preflight→layers→images→cluster→operator→recover→verify),
on instance-role credentials with no laptop cluster access.

> **Scope — this is the core operator-lifecycle proof, SSO-independent.** The drill
> exercises the *CloudNativePG operator's* DR path (backup → bootstrap.recovery →
> verified counts) and touches none of the optional operator-SSO layer (Dex/oauth2-proxy/
> cert-manager are local-only; the AWS ApplicationSet never deploys them). Its only
> pre-staging is the **image supply chain** — the quay/ghcr/Docker-Hub ECR pull-through
> creds (Secrets Manager), which the core needs regardless — **not** the SSO pre-staging
> (GitHub OAuth App + FreeDNS). So a reviewer can run and judge the DR story without any
> SSO setup.
- **Pre-teardown capture:** fresh base backup `20260604T183915`
  (`lastSuccessfulBackup` 2026-06-04T18:39:20Z).
- **Acceptance target — the restored `app` DB must match exactly:**

  | table | rows |
  |-------|------|
  | `items` | 4 |
  | `searches` | 84 |
  | `search_results` | 423 |
  | `api_calls` | 84 |

- **Result (2026-06-08): PASS — exact match, 4 / 84 / 423 / 84.** The recovery
  `Cluster pg` bootstrapped from base backup `20260604T183915` to 3/3 instances
  healthy on gp3 PVCs. One gap surfaced and banked: the standalone drill path
  bypasses the wave-0 GitOps storage app, so **EBS CSI + gp3 must be installed
  before the recovery Cluster** (its PVCs hang Pending otherwise) — folded into
  Step 4 below.

**Restore sequence** — *drill = proof-only mode: recover + verify counts, then
re-teardown.* The realized driver is **`platform.sh restore`** run from the conductor
(instance-role creds; from a laptop, `AWS_PROFILE=brzl-apply` works too — the scripts
are dual-locus). The manual steps below are the per-phase reference. Every `tofu apply`
is the saved-plan workflow (`plan -out=tfplan` → review → `apply tfplan`), per-layer
(`cd <layer> && tofu init -backend-config=../backend.hcl`). `15-kms` stays up
throughout — it holds the CMKs + the backup bucket the data lives in.

**Step 0 — Pre-flight (free):** confirm the foundation + the backup objects survived:

```sh
aws s3 ls "s3://$(aws ssm get-parameter --name /brzl-dev/backup/bucket_name --query Parameter.Value --output text)/pg/base/" --recursive | tail
aws secretsmanager list-secrets --query "SecretList[?starts_with(Name,'ecr-pullthroughcache/')].Name"
```

If the three `ecr-pullthroughcache/brzl-dev-{quay,github,dockerhub}` secrets are gone,
recreate them: `bash gitops/bootstrap/create_pullthrough_secrets.sh | bash` (they feed
`40-ecr`'s `*_credential_arn` tfvars). They are script-created, not `40-ecr`-managed, so
they normally **survive** a `40-ecr` destroy.

**Step 1 — Infra `10`→`50` 💸** (saved-plan, gated, in order): `10-network` →
`20-security` → `30-iam` → `40-ecr` → `50-compute`. `40-ecr`'s `toolbox.tf`
**re-publishes the toolbox image** as part of its apply (needs docker/buildx on the apply
host; `toolbox_build_enabled=false` to skip).

**Step 2 — Re-push demo-app:** `AWS_PROFILE=brzl-apply bash apps/demo-app/build_push.sh | bash`
(ECR login → build arm64 → push → verify). Toolbox already pushed in step 1.

**Step 3 — k3s + kubeconfig:** `ansible-playbook` the `kubernetes` role against the new
nodes (gated — real hosts), then `AWS_PROFILE=brzl-apply bash gitops/tools/kubeconfig_setup.sh`.

**Step 4 — storage + CNPG operator** (standalone for the drill, so the DB is recovered
*before* the ApplicationSet would initdb an empty `pg`). The standalone path bypasses
the wave-0 GitOps storage app, so it must install **EBS CSI + the gp3 default
StorageClass first** — the 2026-06-08 drill confirmed the recovery PVCs hang Pending
without it. The **`operator` phase now does this itself** ([`platform.sh`](../gitops/tools/platform.sh)
sources [`install_ebs_csi.sh`](../gitops/bootstrap/install_ebs_csi.sh) before the CNPG
operator), so the storage prerequisite can't be forgotten. The standalone EBS CSI
install renders the **same committed values** the ApplicationSet wave 0 uses (chart
2.37.0, `gitops/infrastructure/ebs-csi/values.yaml`, sidecars via the `brzl-dev-k8s`
pull-through), so the two paths can't drift. Manual reference:

```sh
bash gitops/bootstrap/install_ebs_csi.sh        # PREVIEW the EBS CSI + gp3 install
bash gitops/bootstrap/install_ebs_csi.sh | bash # run it (gp3 becomes the default class)
helm upgrade --install cnpg-operator cnpg/cloudnative-pg \
  --version 0.28.2 -n cnpg-system --create-namespace
kubectl -n cnpg-system wait --for=condition=Available deploy --all --timeout=300s
kubectl create namespace cnpg-demo
```

**Step 5 — Recover** from the retained store via the standalone recovery manifest
([`cluster-recovery.yaml`](../gitops/operators/postgres/cluster-recovery.yaml) — recovers
from serverName `pg`, archives its own WAL under `pg-restore`, so the originals stay
pristine + the drill is repeatable). Resolve both sentinels at apply:

```sh
bash gitops/operators/postgres/render_recovery_manifest.sh                 # PREVIEW
bash gitops/operators/postgres/render_recovery_manifest.sh | kubectl apply -f -
kubectl -n cnpg-demo wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' cluster/pg --timeout=600s
```

**Step 6 — Verify the acceptance target** on the recovered primary:

```sh
primary="$(kubectl -n cnpg-demo get pod -l cnpg.io/cluster=pg,cnpg.io/instanceRole=primary -o name)"
kubectl -n cnpg-demo exec "$primary" -- psql -U postgres -d app -tAc \
  "select 'items',count(*) from items union all select 'searches',count(*) from searches \
   union all select 'search_results',count(*) from search_results union all select 'api_calls',count(*) from api_calls;"
```

Counts matched the table above on 2026-06-08 → **DR proven**. App-cutover /
full-GitOps adoption is a follow-on: bootstrap ArgoCD as normal — CNPG treats
`spec.bootstrap` as immutable post-create, so the synced initdb manifest shows OutOfSync
but does **not** wipe the recovered data; commit the recovery variant or annotate to settle
the diff. Then re-run [`TEARDOWN.md`](TEARDOWN.md) to stop billing again.

## Node failure & failover ✅ (CNPG failover drilled)
- **Drilled 2026-06-04:** deleted the primary Postgres pod (`pg-1`) → CNPG fired
  `FailingOver`, promoted standby `pg-2` to primary, recreated `pg-1` as a replica,
  and the cluster self-healed to 3/3 in ~47s — **zero data loss** (rows written
  before and after the kill both present), the app's `pg-rw` Service followed the
  new primary, no manual intervention.
- **One k3s server down:** embedded etcd keeps quorum (2 of 3). CNPG promotes a
  standby if the lost node held the primary; PVCs re-attach on the surviving AZ.
- **Recover:** replace the instance via Terraform (bump/replace in `50-compute`,
  `tofu apply`); re-run the Ansible `kubernetes` role to rejoin; confirm
  `kubectl get nodes` = 3 Ready and etcd healthy.
- **Two servers down (quorum lost):** restore etcd from snapshot per k3s docs —
  treat as disaster recovery below.

## State recovery (Terraform/OpenTofu) ✅
- **State lock stuck** <a id="state-lock-stuck"></a>: a crashed run leaves a lock
  item. Confirm no apply is running, then `tofu force-unlock <LOCK_ID>` in that
  layer. (Helper: `ryderdain/bash` → `aws/delete-state-lock.sh`.)
- **Bad/lost state:** the S3 bucket is **versioned** — restore a prior object
  version of the affected layer's `*.tfstate` key. Never hand-edit state; prefer
  `tofu state` subcommands.
- **Drift:** `tofu plan` shows it; reconcile via code, not the console.

## ArgoCD control plane (self-inflicted prune) ✅ <a id="argocd-control-plane-self-inflicted-prune-"></a>

If a misconfigured `ApplicationSet`/`Application` ever **owns and then prunes** the
ArgoCD release itself (e.g. an element that manages the wave -1 self-manage app gets
renamed/removed), the finalizer cascade-deletes ArgoCD's config layer — `argocd-cm`,
`argocd-rbac-cm`, `argocd-secret`, the controller ServiceAccounts. Symptoms: the
application-controller logs `error retrieving argocd-cm: configmap "argocd-cm" not
found` and `failed to list *v1.Secret: Unauthorized` (its SA token is stale after the
SA was recreated). Recover without a rebuild:

1. **Restore the resources** — re-run the idempotent install:
   `helm upgrade --install argocd argo/argo-cd -f gitops/infrastructure/argocd/values.yaml --set global.image.repository=<host>/brzl-dev-quay/argoproj/argocd`
   (recreates `argocd-cm`/RBAC/SAs).
2. **Refresh SA tokens** — the running pods hold tokens bound to the *deleted* SAs:
   `kubectl -n argocd rollout restart statefulset/argocd-application-controller deploy/argocd-server deploy/argocd-repo-server deploy/argocd-applicationset-controller`.
3. Confirm the controller errors clear and the self-manage `argocd` app returns
   Synced/Healthy; the other apps resume by wave. **Prevention:** never let the
   self-manage element be the one a generator can rename/drop (the `appName` keying in
   ADR-0016 ensures this).

- **Stuck sync after a fix (retry budget exhausted):** an auto-synced app that failed
  its retry limit (5) won't re-sync on a hard-refresh alone. Force one:
  `kubectl -n argocd patch application <name> --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main","syncStrategy":{"apply":{}}}}}'`.
  Two nuances from the 2026-06-10 prod bring-up: **(a)** a forced operation does not
  reliably honor `CreateNamespace=true` — pre-create the target namespace when
  force-syncing an app that has never synced; **(b)** the patch is a no-op while an
  operation is already in flight — check `.status.operationState.phase` first.

- **Sync wedged "waiting for completion of hook …" forever:** a Helm-hook Job was
  deleted out from under a running sync (never hand-delete a hook mid-sync) — the
  operation waits on the ghost indefinitely. Terminate it, then re-sync (the fresh
  sync recreates its own hooks):
  `kubectl -n argocd patch application <name> --type json -p '[{"op":"remove","path":"/operation"}]'`
  then the force-sync patch above.

- **Every app `SYNC: Unknown`, empty `REVISION`:** ArgoCD has no credential for the
  private repo — the gitignored deploy-key Secret was never staged/applied on this
  cluster (it has bitten two live runs; see BOOTSTRAP.md "Repo deploy key"). Fix:
  `kubectl apply -f gitops/bootstrap/repo-deploy-key.yaml`; the repo-server picks it
  up within ~3 minutes and the apps move Unknown → OutOfSync → Synced by wave.

## Disaster recovery (region/account) 🔜
1. Re-run [BOOTSTRAP.md](BOOTSTRAP.md) phases 0–2 in the target region/account.
2. Restore Postgres from the S3 backup (above) — cross-region: ensure the backup
   bucket (or a replica) and its KMS key are reachable from the new region.
3. Re-point GitOps at the new cluster; verify end to end.
- **Know your numbers:** define RPO (≈ backup interval + WAL archiving) and RTO
  (restore + resync time) and validate them in a drill.
