# ADR-0006 — Customer-managed KMS keys only

**Status:** Accepted · **Date:** 2026-06-01 (amended 2026-06-04)
**Context.** AWS-managed default keys don't allow key-policy control, custom
rotation, or cross-principal grants — needed for a HYOK-friendly posture.
**Decision.** Per-purpose customer-managed CMKs (state / ECR / EBS / backup);
never the AWS-managed defaults. Each is `enable_key_rotation = true` with a
key policy that delegates use to IAM (root-enable), so consumers are granted in
their IAM role, not the key policy.
**Consequences.** Full key control and grantability; ~$1/mo per key and a
teardown step (CMKs bill until their deletion window closes).
**Resolution of the EBS-CMK churn (2026-06-04).** The EBS CMK used to live in
the `50-compute` layer, so the "destroy only compute between sessions" loop
churned it (orphaned into a pending-deletion window while the next bring-up minted
a fresh one). It now lives — alongside the new backup CMK and the backup bucket —
in a dedicated **persistent `15-kms` foundation layer**, passed into the compute
module via `terraform_remote_state`. Destroying `50-compute` no longer touches the
key, so the deletion window is back to the 30-day default. The state and ECR CMKs
already sat in persistent layers; all CMKs now do. Migration of the existing live
key (state `mv`/import, no re-encrypt) is the procedure in [UPGRADE.md](../UPGRADE.md).
