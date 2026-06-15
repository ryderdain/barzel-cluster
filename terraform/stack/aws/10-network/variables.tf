variable "env" {
  description = "Target environment: dev | prod. Drives the brzl-<env> name prefix, the Environment tag, and the S3 state object key (composed by the driver at init)."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

variable "aws_region" {
  description = "AWS region. One region per account for this PoC; matches the backend region."
  type        = string
  default     = "eu-central-1"
}

# Per-env network shape — set explicitly in <env>.tfvars (no default, so each
# environment declares its own; the values are the per-env diff you review).
variable "vpc_cidr" {
  description = "VPC CIDR. Per-env so the dev/prod VPCs could peer if ever needed."
  type        = string
}

variable "private_subnets" {
  description = "Private subnet CIDRs (k3s nodes live here). One per AZ."
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet CIDRs (NAT gateway, LoadBalancers). One per AZ."
  type        = list(string)
}

# Same across envs unless an env overrides — defaults kept here, not in tfvars.
variable "azs" {
  description = "Availability zones to spread subnets across (one node per AZ)."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "single_nat_gateway" {
  description = "One shared NAT (dev/PoC cost lever) vs one per AZ (real prod, AZ-independent egress)."
  type        = bool
  default     = true
}
