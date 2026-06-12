variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other dev layer."
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
    EC2 purchasing option, passed to the compute module: "spot" (default, for
    cheap iteration) or "on-demand" (for the delivery demo). SPEC §7.6. Override
    for the demo with: export TF_VAR_capacity_type=on-demand
  EOT
  type        = string
  default     = "spot"

  validation {
    condition     = contains(["spot", "on-demand"], var.capacity_type)
    error_message = "capacity_type must be \"spot\" or \"on-demand\"."
  }
}
