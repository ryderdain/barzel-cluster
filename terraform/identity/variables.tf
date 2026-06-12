variable "aws_region" {
  description = "AWS region. Must match backend.hcl."
  type        = string
  default     = "eu-central-1"
}

variable "name_prefix" {
  description = "Prefix for IAM roles/policies created here."
  type        = string
  default     = "brzl"
}

variable "github_repo" {
  description = "owner/repo that GitHub Actions OIDC tokens are scoped to."
  type        = string
  default     = "ryderdain/barzel-cluster"
}

variable "plan_subjects" {
  description = <<-EOT
    GitHub OIDC `sub` patterns allowed to assume the read-only PLAN role.
    Any ref of the repo may plan.
  EOT
  type        = list(string)
  default     = ["repo:ryderdain/barzel-cluster:*"]
}

variable "apply_subjects" {
  description = <<-EOT
    GitHub OIDC `sub` patterns allowed to assume the APPLY role. Restricted to
    the default branch by default; widen to a GitHub Environment
    (e.g. "repo:owner/repo:environment:production") if you gate prod that way.
  EOT
  type        = list(string)
  default     = ["repo:ryderdain/barzel-cluster:ref:refs/heads/main"]
}

variable "operator_principal_arns" {
  description = <<-EOT
    IAM principal ARNs (human operators) allowed to assume the plan/apply roles
    locally via `aws sts assume-role`. Kept out of git (carries account id) —
    set via a gitignored terraform.tfvars or TF_VAR_operator_principal_arns.
    Empty = OIDC-only (CI) assumption.
  EOT
  type        = list(string)
  default     = []
}

# NOTE: the state bucket name is NOT a variable — it is DERIVED in main.tf from
# data.aws_caller_identity (local.state_bucket = "brzl-demo-tfstate-<account_id>"),
# the same pattern every dev layer uses. Account-bearing names never ride in a
# per-run env var (CLAUDE.md §1.7), so there is no TF_VAR_state_bucket to set.

variable "lock_table_name" {
  description = "DynamoDB lock table name (for state-lock permissions)."
  type        = string
  default     = "brzl-demo-tflock"
}
