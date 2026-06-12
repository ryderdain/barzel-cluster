variable "name" {
  description = "Name prefix for the VPC and its resources (e.g. brzl-dev)."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.10.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across (one node per AZ)."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs (k3s nodes live here). One per AZ."
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs (NAT gateway, future LoadBalancers). One per AZ."
  type        = list(string)
  default     = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
}

variable "single_nat_gateway" {
  description = <<-EOT
    Use one NAT gateway for all private subnets instead of one per AZ.
    true keeps dev cost down (one NAT ~ one EIP); flip to false in prod for
    AZ-independent egress. COST + cost-leak watch item.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags merged onto all network resources."
  type        = map(string)
  default     = {}
}
