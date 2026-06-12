variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other dev layer."
  type        = string
  default     = "eu-central-1"
}

variable "admin_cidr" {
  description = <<-EOT
    CIDR allowed to reach SSH + the Kubernetes API. Leave empty (the default) to
    auto-detect the applying host's public /32 at plan time via the http data
    source in main.tf — works from the conductor or a laptop with no external
    step. Set it only to pin a fixed range, e.g. "203.0.113.0/24".
  EOT
  type        = string
  default     = ""
}
