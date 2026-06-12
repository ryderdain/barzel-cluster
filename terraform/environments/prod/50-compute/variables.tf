variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other prod layer."
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "Graviton instance type. m6g.large default; m6g.medium is the cheaper lever."
  type        = string
  default     = "m6g.large"
}

variable "capacity_type" {
  description = <<-EOT
    EC2 purchasing option: "on-demand" (prod default — stable) or "spot" (cheap
    validation runs; the 15-kms Spot-SLR grant makes it safe to flip).
  EOT
  type        = string
  default     = "on-demand"

  validation {
    condition     = contains(["spot", "on-demand"], var.capacity_type)
    error_message = "capacity_type must be \"spot\" or \"on-demand\"."
  }
}

variable "lb_ingress_cidr" {
  description = <<-EOT
    CIDR admitted to the demo-app NLB (:80). Empty (the default) auto-detects
    the applying host's public /32 — the safe validation posture. Set
    "0.0.0.0/0" deliberately to make the demo UI public.
  EOT
  type        = string
  default     = ""
}
