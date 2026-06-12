# Reusable customer-managed KMS key + alias. One small module, instantiated once
# per purpose (EBS volume encryption, S3 backup encryption, ...) so each key has
# its own rotation, alias, and blast radius. The key policy is the standard
# "enable IAM root" delegation: the account root gets kms:* and all *grant* of
# actual use is then expressed in IAM (the node role's inline policies), so this
# module needs no knowledge of which principals consume the key.
#
# Lives in a PERSISTENT layer (dev/15-kms) — these keys must outlive the compute
# layer we destroy between iterations, otherwise a scheduled-for-deletion CMK
# bills through its whole window every teardown (ADR-0006). Hence the 30-day
# default deletion window is safe again here.

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.this.json
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "EnableIAMRoot"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Let named AWS service-linked roles USE this key to attach CMK-encrypted
  # resources — e.g. AWSServiceRoleForEC2Spot, which launches spot nodes and must
  # decrypt/attach their encrypted root volume. SLRs run AWS-managed policies we
  # cannot edit, so (unlike our node role) this can ONLY be granted in the key
  # policy. Empty by default — only the EBS key sets it. Mirrors AWS's documented
  # Auto Scaling / Spot CMK policy: a "use" statement + a CreateGrant statement
  # scoped to AWS-resource grants.
  dynamic "statement" {
    for_each = length(var.service_grant_principals) > 0 ? [1] : []
    content {
      sid       = "AllowServiceLinkedRoleUse"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.service_grant_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.service_grant_principals) > 0 ? [1] : []
    content {
      sid       = "AllowServiceLinkedRoleGrant"
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.service_grant_principals
      }
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}
