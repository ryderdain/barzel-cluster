# Runbook — Upgrades

Audience: operators performing version changes. Companion:
[BOOTSTRAP.md](BOOTSTRAP.md), [RECOVERY.md](RECOVERY.md).

> **Always run upgrades from the toolbox container / bootstrap VM**, not a laptop
> SSH session — long rolling operations must survive an expiring auth session
> ([ARCHITECTURE.md](ARCHITECTURE.md) ADR-0007). **Take a backup before any stateful upgrade** ([RECOVERY.md](RECOVERY.md)).

Status legend: ✅ live · 🔜 pending.

## Golden rule — everything is a GitOps change
No imperative `kubectl edit` on managed objects. Change the manifest/values in
git → open a PR → review → merge → ArgoCD syncs. The git history *is* the change
log and the rollback path (`git revert` → ArgoCD re-syncs).

## What the 2026-06-09 from-zero bring-up validated
A complete from-zero bring-up (account bootstrap → conductor → layers →
Ansible/k3s HA → GitOps → seed) exercised the mechanism every procedure below
stands on, so these are grounded, not theoretical:

- **GitOps sync path** — the ApplicationSet brought all 7 apps to Synced/Healthy
  by sync wave (operators before their CRs). An upgrade is the *same* path: change
  the manifest/tag in git → ArgoCD syncs. The golden rule is proven, not asserted.
- **k3s HA quorum + rolling primitive** — 3 servers with embedded etcd came up
  Ready (`v1.31.5+k3s1`); the Ansible `kubernetes` role carries the
  one-server-at-a-time roll-restart task the k3s upgrade reuses.
- **CNPG HA topology** — the 3-instance Postgres cluster (1 primary + 2 streaming
  replicas) is exactly the topology a CNPG rolling minor upgrade switches over.
- **Immutable image flow** — ECR repos are `IMMUTABLE`; demo-app shipped under a
  unique tag (`0.2.0`). "Never reuse a tag" is enforced by the registry, not advice.
- **Immutable node replacement** — the spot→on-demand switch replaced a node via
  `tofu apply`; it rejoined the cluster Ready. That is the OS-patch / AMI-bump path
  in miniature.
- **Layered Terraform apply** — the saved-plan-per-layer workflow ran end to end;
  in-place vs replace was visible in each plan before approval.

**Not executed end-to-end** (and intentionally not — standard controller behaviour,
identical on a throwaway cluster and in prod): an actual CNPG *minor version bump*
and a *k3s version bump*. They are documented below; the controllers' rolling
behaviour is their defined contract, and the topology + primitives they drive are
live-proven above — so they need no bespoke test before teardown. 🔜 below marks
"this version-bump not yet run," not "mechanism unproven."

## PostgreSQL minor upgrade (CloudNativePG) 🔜
CNPG performs minor upgrades as a **rolling update**: replicas first, then a
switchover, then the old primary.
1. Backup + confirm it landed in S3 ([RECOVERY.md](RECOVERY.md)).
2. Bump the `imageName` (minor tag) in the CNPG `Cluster` manifest under
   `gitops/operators/postgres/` (or applications). PR → merge.
3. Watch ArgoCD sync + `kubectl get pods -w`; CNPG cordons/replaces one instance
   at a time, ending with a controlled switchover.
4. **Verify:** `SELECT version();` on the primary; replicas streaming; demo-app healthy.
- **Rollback:** `git revert` the bump (only safe within the same minor line —
  never downgrade across a major catalog version).

## k3s / Kubernetes upgrade 🔜
Upgrade **servers one at a time** to keep the embedded-etcd quorum (need 2 of 3).
1. Snapshot etcd / confirm a recent backup.
2. Drain a node (`kubectl drain --ignore-daemonsets --delete-emptydir-data`).
3. Re-run the Ansible `kubernetes` role pinned to the new k3s version (or the k3s
   upgrade controller) on that node; uncordon; wait Ready.
4. Repeat per server. **Verify** `kubectl get nodes` all Ready on the new version
   after each, before proceeding.

## Operator / Helm chart / app image bumps 🔜
- **Operators (CNPG, EBS CSI, kube-prometheus-stack):** bump the chart/manifest
  version in `gitops/`, mind **sync waves** (operators before their CRs). PR → sync.
- **demo-app:** build the new **arm64** image → push to ECR → bump the tag in
  `gitops/applications/demo-app/`. PR → sync. (Immutable tags: never reuse a tag.)

## OS / node patching 🔜
Rolling, one node at a time: drain → patch (Ansible `base`) or replace the
instance (immutable: bump the AMI in `50-compute`, `tofu apply`, let the node
rejoin) → uncordon → verify.

## Infrastructure (Terraform) changes ✅
`tofu plan` under the **plan** role (read-only) for review in CI; apply under the
**apply** role on merge to `main`. Layered state means most changes touch one
layer — apply only that layer. Review the plan for **replacements** of stateful
resources (e.g. anything forcing EC2/EBS recreation) before approving.

## One-time state migrations

### Move the EBS CMK from `50-compute` → `15-kms` (ADR-0006) ✅ (one-time state-op 2026-06-04; foundation applied since)

> **Resolved 2026-06-09.** The "remaining `15-kms` apply" below has landed: a
> from-zero bring-up applied `15-kms` as an ordinary layer, creating both CMKs +
> the backup bucket/SSM param. On a **fresh account there is no migration at all** —
> `15-kms` owns the EBS key from the first apply; the state rm/import dance was a
> one-time refactor of the *then-live* state and is kept here as the pattern for
> moving a live CMK between layers without re-creation/re-encryption.

The EBS CMK moved out of the churned compute layer into the persistent `15-kms`
foundation. Migrate the **existing live key** into the new state with a state
remove/import — **no key re-creation and no volume re-encryption**. The key
id/arn are unchanged throughout. Run under the apply role; the driver composes each
stack layer's backend from the caller's account + `<env>/<layer>` key (no `backend.hcl`,
no `TF_VAR_state_bucket` — the account-bearing bucket name is never a per-run env var,
SPEC §3).

> **Performed 2026-06-04** (key `4805a479-f62d-4835-a720-9eba7c0f5545`): `state rm`
> from `50-compute` + `import` into `15-kms` (`module.kms_ebs`) both succeeded.
> Verified plans: `15-kms` = 9 add / 1 in-place (EBS key `deletion_window 7→30` +
> description; **0 destroy**), `50-compute` = no key destroy. The remaining
> `15-kms apply` (in-place EBS key update + backup bucket/key/SSM CREATEs) lands
> as the ordinary `15` step of the next bring-up — no longer a surgical operation.

> Do this while `50-compute`'s compute is destroyed (the key was retained by the
> iteration teardown). It must happen **before** the next `50-compute` apply —
> otherwise, with the CMK now removed from the compute module's code, that apply
> would plan to **destroy** the live key.

```sh
# Historical migration (performed 2026-06-04: EBS CMK 50-compute → 15-kms), recorded
# for reference. Layers are now the single-source stack; per-layer dirs below are
# under terraform/stack/aws/, each init'd with the §3 driver-composed backend.
cd terraform/stack/aws

# 0. Note the existing key id (from the layer that still owns it in state).
( cd 50-compute && tofu state show module.compute.aws_kms_key.ebs | grep -E 'key_id|arn' )

# 1. Drop the key + alias from 50-compute state (leaves the AWS resource alive,
#    just unmanaged for a moment).
( cd 50-compute && tofu state rm module.compute.aws_kms_key.ebs module.compute.aws_kms_alias.ebs )

# 2. Import the same live key + alias into 15-kms.
( cd 15-kms && tofu init -reconfigure \
    -backend-config="bucket=brzl-demo-tfstate-<account>" \
    -backend-config="key=dev/15-kms/terraform.tfstate" \
    -backend-config="region=eu-central-1" -backend-config="dynamodb_table=brzl-demo-tflock" \
    -backend-config="encrypt=true" \
  && tofu import module.kms_ebs.aws_kms_key.this   <key_id> \
  && tofu import module.kms_ebs.aws_kms_alias.this alias/brzl-dev-ebs )

# 3. Verify. 15-kms plan should show only an in-place deletion_window 7→30 on the
#    imported key, plus CREATES for the NEW backup key/alias/bucket/SSM param — no
#    EBS-key replacement. 50-compute plan should show no destroy of the key.
( cd 15-kms && tofu plan )
( cd 50-compute && tofu plan )
```

After this, `15-kms` owns both CMKs + the backup bucket; `30-iam` and `50-compute`
read them via `terraform_remote_state`. Subsequent bring-ups are the ordinary
layered apply (`10 → 15 → 20 → 30 → 40 → 50`).
