variable "env" {
  description = "Target environment: dev | prod. Drives the brzl-<env> name prefix, the Environment tag, and the S3 state object key (this layer's own + the 15-kms read)."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "aws_region" {
  description = "AWS region. One per account for this PoC; matches the backend region."
  type        = string
  default     = "eu-central-1"
}
