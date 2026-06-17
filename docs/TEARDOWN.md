# Runbook — Teardown & cost-leak sweep

Audience: operators decommissioning an environment. Companion:
[BOOTSTRAP.md](BOOTSTRAP.md). `terraform destroy` does **not** catch everything —
the manual sweep below is mandatory ([../CLAUDE.md](../CLAUDE.md) cost-leak watch).

> Destroy in **reverse layer order**. Anything created outside Terraform (PVC-backed
> EBS volumes, LoadBalancer ELBs) is the operator's job to confirm gone.

## 0. Two teardown modes (PoC posture, SPEC §8)
This is a PoC — bring up → demo → tear down, not a standing system. The
per-hour meter is dominated by **compute** (`m6g.large` ≈ $0.231/hr combined;
**spot ≈ ~70% less** during iteration) and the **managed NAT gateway**
(≈ $0.045/hr + data).

- **Iteration mode (now → delivery): destroy only `50-compute` between sessions.**
  Stops the big compute meter while keeping network/`15-kms`/security/iam/ecr +
  identity + state up for fast turnaround. NAT keeps billing — accepted for
  iteration speed; destroy `10-network` too if pausing for longer. The EBS CMK
  lives in the persistent `15-kms` layer now, so this destroy no longer touches it
  (no orphaned pending-deletion key, no targeted-destroy workaround — ADR-0006).
  ```sh
  # compute-only (fast iteration), the single-source 50-compute stack layer, dev state:
  acct="$(aws sts get-caller-identity --query Account --output text)"
  cd terraform/stack/aws/50-compute
  tofu init -reconfigure -backend-config="bucket=brzl-demo-tfstate-${acct}" \
    -backend-config="key=dev/50-compute/terraform.tfstate" -backend-config="region=eu-central-1" \
    -backend-config="dynamodb_table=brzl-demo-tflock" -backend-config="encrypt=true"
  tofu destroy -var-file=dev.tfvars
  ```
  Re-bootstrap next session: re-apply `50-compute` → re-run the Ansible
  `kubernetes` role (k3s state does not survive compute teardown).
- **FULL teardown (account to zero):** reverse-order across every layer (§1–§3)
  **plus the cost-leak sweep (§4) plus the manual finishers (§3a)** — `tofu
  destroy` alone has never gotten this account to zero; both full retirements
  (2026-06-08, 2026-06-10) needed the by-hand steps now written below. Use a
  **7-day KMS deletion window** when retiring so CMKs stop billing sooner
  (default is 30).

## 1. In-cluster first (releases cloud resources k8s created) 🔜
Delete app + CNPG `Cluster` (frees PVC EBS volumes) and any LoadBalancer
Services (frees ELBs), or let ArgoCD prune them. **Confirm** no `kubernetes.io`
EBS volumes or ELBs remain before touching infra.

## 2. Infrastructure layers (reverse order) ✅ 💸
The realized path is the **driver** (gated, saved-plan, reverse-order 50→10, keeps
`15-kms`): `ENV=dev bash gitops/tools/platform.sh teardown` (or `ENV=prod`). Full
retirement (incl. `15-kms` + identity + the state bucket) adds §3/§3a below.
Manual reference — the single-source stack, composing each layer's env-keyed backend:
```sh
acct="$(aws sts get-caller-identity --query Account --output text)"
for layer in 50-compute 40-ecr 30-iam 20-security 15-kms 10-network; do
  ( cd "terraform/stack/aws/$layer" \
      && tofu init -reconfigure -backend-config="bucket=brzl-demo-tfstate-${acct}" \
           -backend-config="key=dev/$layer/terraform.tfstate" -backend-config="region=eu-central-1" \
           -backend-config="dynamodb_table=brzl-demo-tflock" -backend-config="encrypt=true" \
      && tofu destroy -var-file=dev.tfvars )
done
```
> **Next-pass (the live-test loose ends):** an **end-to-end automated full-teardown
> sweep** (driver `teardown` → leak sweep §4 → finishers §3a) is still to be built;
> today the §3/§3a/§4 steps are run by hand. Tracked in BACKLOG.

`40-ecr` destroy **fails on any non-empty repository**
(`RepositoryNotEmptyException` — the repos are deliberately not `force_delete`,
so a destroy can't silently discard images; bit the 2026-06-08 and 2026-06-10
teardowns both). Empty every env repo first — the loop also catches the
**pull-through cache repos** (`brzl-<env>-quay/…` etc.), which were auto-created
on pull, live in **no tofu state**, and would otherwise survive as orphans:
```sh
for repo in $(aws ecr describe-repositories \
    --query "repositories[?starts_with(repositoryName,'brzl-<env>')].repositoryName" --output text); do
  ids="$(aws ecr list-images --repository-name "$repo" --query 'imageIds[]' --output json)"
  [ "$ids" != "[]" ] && aws ecr batch-delete-image --repository-name "$repo" --image-ids "$ids"
done
```

`15-kms` destroy will **refuse to delete a non-empty backup bucket**
(`force_destroy = false`) — by design, so backups aren't lost by accident.
Leave `15-kms` up to retain backups + CMKs (see §5), or **fully retire it** with
the sequence below. There is no shortcut: the bucket is **versioned**, so a plain
`aws s3 rm --recursive` leaves every version + delete marker behind and the
destroy still refuses — purge versions explicitly (bit the 2026-06-08 and
2026-06-10 full teardowns; written down so it stops being tribal knowledge):
```sh
bucket=brzl-<env>-cnpg-backups-<account_id>   # discards ALL backups — be sure
aws s3api list-object-versions --bucket "$bucket" \
  --query '{Objects: [Versions,DeleteMarkers][][].{Key:Key,VersionId:VersionId}}' --output json \
  | jq -c '{Objects: (.Objects // []), Quiet: true}' \
  | aws s3api delete-objects --bucket "$bucket" --delete file:///dev/stdin
# (helper: ryderdain/bash aws/nuke-bucket.sh)
```
Then the layer destroy proceeds; the EBS + backup CMKs go to **PendingDeletion**
and bill ~$1/mo each until the window closes (set a 7-day window when retiring).

## 3. Identity + state backend (last) ✅

**Where the states live — and the catch-22.** Every layer's state lives *in the
state bucket* — except `terraform/bootstrap`'s own, which is deliberately
**local** (`terraform/bootstrap/terraform.tfstate` on the admin's machine): the
layer that manages the bucket can't keep its record inside the thing it deletes.
The catch-22 is everything else: destroy the bucket and any layer not yet
destroyed is **stranded** (state gone, resources alive). Resolution — make the
state local *first*, then the bucket is safe to remove:

```sh
# Per still-live layer that must outlive the bucket: comment out its backend.tf
# `backend "s3"` block, then pull the state down to a local file:
tofu init -migrate-state          # answer "yes" — copies S3 state → local
# the layer can now plan/destroy with no bucket at all
```

```sh
cd ../../identity && tofu destroy   # identity FIRST (its state is in the bucket)
# State bucket (prevent_destroy + VERSIONED) — ONLY if truly retiring:
#   `aws s3 rm --recursive` is NOT enough: versions + delete markers survive it and
#   the bucket delete still refuses (bit the 2026-06-10 retirement). Purge with the
#   version loop in §2 (delete-objects caps at 1000/call — loop until both
#   `length(Versions)` and `length(DeleteMarkers)` are zero), or nuke-bucket.sh.
#   Then flip prevent_destroy=false in terraform/bootstrap/main.tf (do NOT commit),
#   tofu destroy from its LOCAL state, git restore main.tf. The DynamoDB table
#   (incl. digest rows) dies in the same destroy; the state CMK → PendingDeletion.
```

> **Note — this is the bootstrap mechanism, reversed.** Local-first state that
> migrates *into* the backend once it exists is exactly how a full-purpose
> bootstrap-from-zero should work: every layer starts local, `init
> -migrate-state` promotes it to S3 when the bucket is up, and teardown is the
> same move backwards. Today only `terraform/bootstrap` works this way (it has
> no choice); generalizing it would make bring-up and retirement symmetric.

## 3a. FULL teardown only — manual finishers (the part tofu can't do)

These are not optional polish: both full retirements ended here. Run them after
§3, in this order.

- **Remaining buckets** — purge versions + delete markers with the §2 loop
  (`delete-objects` caps at 1000/call; repeat until `[0, 0]`), then delete the
  bucket itself.
- **DynamoDB lock table** — if the bootstrap `tofu destroy` didn't take it (state
  tangled, partial destroy, or it predates the local-state convention), clear the
  rows and delete the table by hand (rows first is not strictly required, but
  proves nothing else is mid-flight):
  ```sh
  table=brzl-demo-tflock
  for id in $(aws dynamodb scan --table-name "$table" \
      --projection-expression LockID --query 'Items[].LockID.S' --output text); do
    aws dynamodb delete-item --table-name "$table" --key "{\"LockID\":{\"S\":\"$id\"}}"
  done
  aws dynamodb delete-table --table-name "$table"   # or the console
  ```
  This also disposes of the stale `*.tfstate-md5` **digest rows** that otherwise
  break the next from-zero `tofu init` (§4).
- **KMS CMKs** — confirm every `brzl-*` key shows **PendingDeletion**; that is
  the terminal state you can reach (KMS will not hard-delete on demand — the
  window is the point). They bill ~$1/mo each until the window closes.
- **Final audit** — no EC2/EBS/EIP/NAT/ELB/VPC, no ECR repos, no S3 buckets, no
  DynamoDB tables, no `brzl-*` IAM roles/OIDC providers, no Secrets Manager
  `ecr-pullthroughcache/*` secrets. Only PendingDeletion CMKs (and the admin
  user) remain.

## 4. Manual cost-leak sweep (verify each is gone)
- [ ] **NAT gateway** (hourly + data) — destroyed with `10-network`? confirm in VPC console.
- [ ] **Elastic IPs** — the NAT EIP; any released, none left **allocated/unassociated** (charged when idle).
- [ ] **EBS volumes** behind PVCs — orphaned `available` volumes after CNPG teardown.
- [ ] **LoadBalancer Services** — ELB/NLB created by k8s.
- [ ] **The cloud-init bootstrap VM** (+ its EBS) if launched.
- [ ] **KMS CMKs** (state / ECR / EBS / backup) — all live in persistent layers
      (`15-kms` for EBS + backup), so an iteration `50-compute` destroy no longer
      schedules any for deletion. On a **full** teardown `tofu destroy` schedules
      them (30-day window); they **still bill ~$1/mo each until deleted**. Confirm
      "pending deletion" in KMS, or shorten the window if retiring for good.
- [ ] **State bucket + DynamoDB lock table** — only when fully retiring the env.
- [ ] **Stale state DIGEST rows in the lock table** — if the lock table outlives
      the state objects (e.g. buckets swept manually while the table survives),
      every `<bucket>/<key>.tfstate-md5` item left behind makes the **next**
      from-zero `tofu init` fail with "state data in S3 does not have the
      expected content" (observed 2026-06-10). Scan and delete them:
      `aws dynamodb scan --table-name brzl-demo-tflock --projection-expression LockID`
      → `aws dynamodb delete-item … --key '{"LockID":{"S":"<row>"}}'` per stale row.
- [ ] **CloudWatch log groups**, leftover snapshots, unused security groups.

## 5. Intentionally-left artifacts (document, don't delete blindly)
- **ECR images** — retained for re-deploy unless explicitly purged.
- **S3 Postgres backups** — the `15-kms` backup bucket (`force_destroy = false`)
  is retained per retention policy (deleting it forfeits PITR/DR). The bucket + its
  CMK + the EBS CMK are kept alive on purpose (persistent `15-kms` layer).

## Quick audit helpers (`ryderdain/bash`)
`aws/list_instances.sh`, `aws/review_lbs.sh`, `aws/nuke-bucket.sh`,
`aws/delete-state-lock.sh`.
