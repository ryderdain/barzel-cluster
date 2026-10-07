# ADR-0010 — CNPG backups via the EC2 instance profile, no second IAM user

**Status:** Accepted · **Date:** 2026-06-01 (amended 2026-06-04)
**Context.** Object-store backups need S3 credentials; a standing IAM user is a
static-secret liability.
**Decision.** CloudNativePG → S3 via Barman Cloud, authenticated by the **EC2
instance profile** (`barmanObjectStore.s3Credentials.inheritFromIAMRole: true`).
Demonstrate backup *and* restore. The bucket lives in the persistent `15-kms`
layer with **default SSE-KMS** under a customer-managed key; the node role
(`30-iam`) carries scoped S3 read/write **and** `kms:GenerateDataKey`/`Decrypt`
on that one key. The bucket name is account-bearing, so it's published to SSM
(`/brzl-dev/backup/bucket_name`) and reaches the Cluster manifest through a
`__BACKUP_BUCKET__` sentinel resolved at bootstrap (same pattern as the ECR host,
ADR-0013) — no account id in git.
**Consequences.** No long-lived backup credentials; backup auth is tied to node
identity. Backups survive every compute teardown (persistent layer). A bucket
policy rejects any non-SSE-KMS or wrong-key upload, and non-TLS access. (IRSA via
a cluster OIDC issuer is the documented finer-grained future.)
