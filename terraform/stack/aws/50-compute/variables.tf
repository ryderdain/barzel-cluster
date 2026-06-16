variable "env" {
  description = "Target environment: dev | prod. Drives the brzl-<env> name prefix, the Environment tag, and the S3 state object key (own + the 10/15/20/30 reads)."
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

variable "instance_type" {
  description = "Graviton instance type. m6g.large default; m6g.medium is the cheaper lever."
  type        = string
  default     = "m6g.large"
}

variable "capacity_type" {
  description = "EC2 purchasing option: \"spot\" (cheap iteration) or \"on-demand\" (stable demo/prod). Set per env in <env>.tfvars."
  type        = string
  default     = "on-demand"

  validation {
    condition     = contains(["spot", "on-demand"], var.capacity_type)
    error_message = "capacity_type must be \"spot\" or \"on-demand\"."
  }
}

variable "public_nodes" {
  description = "Node placement: true = public subnets + public IPs (dev — direct operator access, /32-locked); false = private subnets, no public IP (prod — SSM only)."
  type        = bool
  default     = false
}

variable "enable_public_ingress" {
  description = "Create the Terraform-owned demo-app NLB (ingress.tf). prod true; dev false (off = no idle NLB cost). Flip to adopt the public-ingress pattern in any env."
  type        = bool
  default     = false
}

variable "lb_ingress_cidr" {
  description = "CIDR admitted to the demo-app NLB (:80) when enable_public_ingress. Empty (default) auto-detects the applying host's public /32; set \"0.0.0.0/0\" for a public demo."
  type        = string
  default     = ""
}
