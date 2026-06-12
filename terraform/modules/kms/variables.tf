variable "alias" {
  description = "Alias name WITHOUT the `alias/` prefix (e.g. brzl-dev-ebs)."
  type        = string
}

variable "description" {
  description = "Human-readable key description shown in the KMS console."
  type        = string
}

variable "deletion_window_in_days" {
  description = <<-EOT
    Days a scheduled-for-deletion key waits before it is destroyed (7-30). 30 is
    fine because this key lives in a persistent layer; only keys in the churned
    compute layer needed the 7-day minimum to cap orphan billing (ADR-0006).
  EOT
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags merged onto the key."
  type        = map(string)
  default     = {}
}

variable "service_grant_principals" {
  description = <<-EOT
    AWS service-linked role ARNs allowed to USE this key to attach CMK-encrypted
    resources (e.g. AWSServiceRoleForEC2Spot for spot-backed EBS root volumes).
    Such roles run AWS-managed policies that can't be edited, so the access has to
    be in the key policy. Empty (default) leaves the policy as plain IAM-root
    delegation; only the EBS key sets it.
  EOT
  type        = list(string)
  default     = []
}
