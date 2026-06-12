# Remote-state backend primitives. Run ONCE per AWS account, before any
# environment layer. Creates the S3 bucket (versioned, encrypted, private) that
# holds all layer state, and the DynamoDB table used for state locking.

data "aws_caller_identity" "current" {}

# Customer-managed KMS key for state-at-rest. We deliberately avoid the AWS-
# managed `aws/s3` key: a generated CMK has a key policy we control, supports
# rotation, and can be granted to other principals/contexts (key portability /
# HYOK posture) — AWS-managed keys cannot. Per-purpose key (state only) for
# blast-radius isolation.
resource "aws_kms_key" "state" {
  description             = "brzl-demo Terraform/OpenTofu state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.state_key.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/brzl-demo-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# Root-enable: delegates authorization to IAM so the plan/apply roles (granted
# in terraform/identity) and admins can use the key via their IAM policies.
data "aws_iam_policy_document" "state_key" {
  statement {
    sid       = "EnableIAMRoot"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # State is the source of truth for every other layer: never let an accidental
  # destroy take it out. Empty + delete by hand during teardown if truly intended.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    # Bucket keys cut KMS API calls (and cost) for the many small state objects.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
