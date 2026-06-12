variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other prod layer."
  type        = string
  default     = "eu-central-1"
}

variable "single_nat_gateway" {
  description = "One shared NAT (PoC validation) vs one per AZ (real prod). See main.tf."
  type        = bool
  default     = true
}
