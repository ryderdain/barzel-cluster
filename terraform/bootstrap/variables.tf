variable "aws_region" {
  description = "Region for the state bucket and lock table. Match every environment's backend.hcl."
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally-unique S3 bucket name for Terraform/OpenTofu remote state.
    Suggested form: brzl-demo-tfstate-<account_id>. This MUST match the
    `bucket` value in every environments/<env>/backend.hcl.
  EOT
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking. Must match backend.hcl `dynamodb_table`."
  type        = string
  default     = "brzl-demo-tflock"
}
