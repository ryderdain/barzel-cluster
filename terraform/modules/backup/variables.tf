variable "bucket_name" {
  description = <<-EOT
    Globally-unique bucket name. Include the account id for uniqueness without
    committing it to git — the env layer composes it from a caller-identity data
    source (e.g. brzl-dev-cnpg-backups-<account>).
  EOT
  type        = string
}

variable "kms_key_arn" {
  description = "CMK ARN for the bucket's default SSE-KMS encryption."
  type        = string
}

variable "force_destroy" {
  description = <<-EOT
    Allow `tofu destroy` to delete the bucket even when it still holds backup
    objects/versions. Default false so backups are not lost by accident; set true
    only for an intentional, total teardown.
  EOT
  type        = bool
  default     = false
}

variable "noncurrent_version_expiration_days" {
  description = "Days before a noncurrent object version is expired (versioning safety net; CNPG owns real retention)."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags merged onto the bucket."
  type        = map(string)
  default     = {}
}
