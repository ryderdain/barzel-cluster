# S3 bucket CloudNativePG / Barman Cloud writes Postgres backups to (base
# backups + continuous WAL archive). It is PERSISTENT by design: backups must
# survive the compute teardown we do between iterations, so this lives in the
# durable foundation layer (dev/15-kms), not alongside compute.
#
# Auth is the node EC2 instance profile (CNPG barmanObjectStore
# s3Credentials.inheritFromIAMRole) — no second IAM user (CLAUDE.md). The S3
# read/write + KMS grants are attached to the node role in the iam module.
#
# Encryption is SSE-KMS with a customer-managed key, enforced as the bucket
# DEFAULT so Barman doesn't have to send any SSE header (it can't name our CMK
# explicitly): an un-headered PutObject inherits aws:kms with our key. A bucket
# policy denies any upload that tries to override it with the wrong key.

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  # force_destroy stays false by default: a `tofu destroy` must NOT silently
  # delete backups. Flip it (via the env layer) only for a deliberate teardown.
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    # S3 Bucket Keys cut KMS GenerateDataKey calls (and cost) by deriving a
    # bucket-level data key — material for high-object-count backup workloads.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Belt-and-suspenders: refuse any object that isn't SSE-KMS under OUR key, and
# refuse non-TLS access. Keeps a misconfigured client from writing plaintext or
# default-key objects into the backup set.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyIncorrectEncryptionKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [var.kms_key_arn]
    }
    # Only catch requests that DID set aws:kms but with the wrong key; un-headered
    # PutObjects fall through to the bucket default (our key) and are fine.
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Reclaim storage from interrupted multipart uploads (Barman uploads large WAL
  # / base-backup parts; a crashed upload otherwise lingers and bills).
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Backup RETENTION proper is CNPG's job (spec.backup.retentionPolicy drives
  # Barman to delete obsolete backups). Versioning here only guards against
  # accidental overwrite/delete, so expire noncurrent versions promptly to keep
  # that safety net from growing unbounded.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}
