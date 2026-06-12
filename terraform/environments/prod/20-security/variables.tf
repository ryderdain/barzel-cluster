variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other prod layer."
  type        = string
  default     = "eu-central-1"
}

variable "admin_cidr" {
  description = <<-EOT
    CIDR allowed by the (defense-in-depth) kube-API SG rule. Leave empty (the
    default) to auto-detect the applying host's public /32 at plan time. Nodes
    are private here, so this rule has no internet-reachable surface either way.
  EOT
  type        = string
  default     = ""
}
