variable "env" {
  description = "Target environment: dev | prod. Drives the brzl-<env> name prefix, the Environment tag, and the S3 state object key (this layer's own + the lower-layer reads)."
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

variable "admin_cidr" {
  description = "CIDR allowed to reach the kube-API (and SSH if enabled). Empty (default) = auto-detect the applying host's public /32 at plan time. Pin a range to override."
  type        = string
  default     = ""
}

variable "enable_ssh_ingress" {
  description = "Open inbound :22 on the node SG. Default false (SSM/SSH-over-SSM is the path); flip true only as break-glass."
  type        = bool
  default     = false
}
