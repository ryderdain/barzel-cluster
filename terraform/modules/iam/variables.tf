variable "name" {
  description = "Name prefix for the instance role/profile (e.g. brzl-dev)."
  type        = string
}

variable "backup_bucket_arn" {
  description = <<-EOT
    ARN of the S3 bucket CloudNativePG / Barman Cloud writes backups to.
    Authenticating via this instance profile is deliberate — we do NOT mint a
    second IAM user for backups. Pass "" to omit S3 backup permissions while the
    backup bucket does not yet exist (scaffolding default).
  EOT
  type        = string
  default     = ""
}

variable "backup_kms_key_arn" {
  description = <<-EOT
    ARN of the CMK encrypting the backup bucket (SSE-KMS). The node role needs
    GenerateDataKey + Decrypt on it so Barman can write/read SSE-KMS objects
    under our customer-managed key. Pass "" to omit the grant while no backup
    bucket exists (scaffolding default).
  EOT
  type        = string
  default     = ""
}

variable "enable_ssm" {
  description = <<-EOT
    Grant the node role the minimal AWS Systems Manager permissions for Session
    Manager (Session Manager / SSH-over-SSM access — see docs/ACCESS.md). This
    is the ssmmessages data-channel set + ssm:UpdateInstanceInformation, the
    same effective grant as the AWS-managed AmazonSSMManagedInstanceCore but
    written inline (repo convention) and trimmed to what Session Manager needs.
    Default true: SSM is the primary node-access path.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags merged onto IAM resources."
  type        = map(string)
  default     = {}
}
