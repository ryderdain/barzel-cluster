output "vpc_id" {
  description = "VPC id (consumed by the security-groups and compute layers)."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet ids — k3s nodes are placed here, one per AZ."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet ids (NAT, future LoadBalancers)."
  value       = module.vpc.public_subnets
}

output "azs" {
  description = "Availability zones in use."
  value       = var.azs
}

output "nat_public_ip" {
  description = "NAT gateway public IP (cost-leak watch: an EIP)."
  value       = aws_eip.nat.public_ip
}
