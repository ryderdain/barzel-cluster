# Identity / trust anchor (account-global, admin-run once after bootstrap).
#
# Establishes federated, least-privilege deployment without static credentials:
#   - a GitHub Actions OIDC provider (CI assumes roles via web identity), and
#   - scoped PLAN (read-only) and APPLY roles, assumable by CI (OIDC) and/or
#     named human operators.
# IAM Identity Center (human SSO) requires AWS Organizations + console enablement
# and is documented as a manual prerequisite in README.md, not managed here.
#
# Ory (Hydra) is the documented portable production alternative to GitHub/AWS
# OIDC for bare-metal / private-cloud substrate (see SPEC.md §4.1).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  # DERIVED from the caller's account id, never a TF var (CLAUDE.md §1.7) — identical
  # pattern to every dev layer's remote_state.tf. The bucket name is account-bearing,
  # so it must not depend on an operator's shell memory (TF_VAR_state_bucket).
  state_bucket     = "brzl-demo-tfstate-${local.account_id}"
  state_bucket_arn = "arn:aws:s3:::${local.state_bucket}"
  lock_table_arn   = "arn:aws:dynamodb:${data.aws_region.current.name}:${local.account_id}:table/${var.lock_table_name}"

  # Resource scopes for the apply role's IAM management (project-prefixed only).
  iam_role_scope    = "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-*"
  iam_policy_scope  = "arn:aws:iam::${local.account_id}:policy/${var.name_prefix}-*"
  iam_profile_scope = "arn:aws:iam::${local.account_id}:instance-profile/${var.name_prefix}-*"
}

# State CMK (created in bootstrap) — looked up so we can grant the plan role
# explicit decrypt rights. The apply role already has kms via PowerUserAccess.
data "aws_kms_alias" "state" {
  name = "alias/brzl-demo-tfstate"
}

# --- GitHub Actions OIDC provider -------------------------------------------
# Thumbprint fetched live so we never pin a fingerprint that can rotate.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = data.tls_certificate.github.certificates[*].sha1_fingerprint
}

# --- Assume-role trust documents --------------------------------------------
data "aws_iam_policy_document" "plan_assume" {
  statement {
    sid     = "GitHubOidcPlan"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.plan_subjects
    }
  }

  dynamic "statement" {
    for_each = length(var.operator_principal_arns) > 0 ? [1] : []
    content {
      sid     = "OperatorAssumePlan"
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = var.operator_principal_arns
      }
    }
  }
}

data "aws_iam_policy_document" "apply_assume" {
  statement {
    sid     = "GitHubOidcApply"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.apply_subjects
    }
  }

  dynamic "statement" {
    for_each = length(var.operator_principal_arns) > 0 ? [1] : []
    content {
      sid     = "OperatorAssumeApply"
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = var.operator_principal_arns
      }
    }
  }
}

# --- PLAN role: read-only infra + state read + lock -------------------------
resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-tofu-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [local.lock_table_arn]
  }
  statement {
    sid       = "StateKmsDecrypt"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [data.aws_kms_alias.state.target_key_arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "${var.name_prefix}-tofu-plan-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# --- APPLY role: PowerUser (no IAM) + scoped IAM for project resources ------
resource "aws_iam_role" "apply" {
  name                 = "${var.name_prefix}-tofu-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_assume.json
  max_session_duration = 3600
}

# PowerUserAccess = everything EXCEPT iam/organizations/account. Covers ec2,
# vpc, ecr, s3, dynamodb the layers manage.
resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# The IAM that PowerUser deliberately omits — scoped to project-prefixed names
# so apply can manage the node role/instance-profile (layer 30-iam) but not
# arbitrary account IAM.
data "aws_iam_policy_document" "apply_iam" {
  statement {
    sid = "ManageProjectIam"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
      "iam:ListInstanceProfilesForRole", "iam:ListInstanceProfileTags",
    ]
    resources = [local.iam_role_scope, local.iam_policy_scope, local.iam_profile_scope]
  }

  statement {
    sid       = "PassNodeRoleToEc2"
    actions   = ["iam:PassRole"]
    resources = [local.iam_role_scope]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "${var.name_prefix}-tofu-apply-iam"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}
