output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "tofu_plan_role_arn" {
  description = "Read-only role for `tofu plan` (CI via OIDC or operator assume-role)."
  value       = aws_iam_role.plan.arn
}

output "tofu_apply_role_arn" {
  description = "Apply role (PowerUser + scoped project IAM)."
  value       = aws_iam_role.apply.arn
}

output "assume_hint" {
  description = "How an operator assumes the plan role locally."
  value       = "aws sts assume-role --role-arn ${aws_iam_role.plan.arn} --role-session-name local-plan"
}
