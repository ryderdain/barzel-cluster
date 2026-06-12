# VPC built on the community module (same pattern as ryderdain/tw-project),
# rather than hand-rolling IGW / route tables / NAT. 3-AZ public + private
# subnets; k3s nodes should run in the private subnets and egress via NAT.

# Dedicated EIP so the NAT gateway's public address is stable and explicitly
# tracked (cost-leak watch: release this on teardown).
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat" })
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Single NAT keeps dev cheap; one stable EIP we control. See var docs.
  enable_nat_gateway  = true
  single_nat_gateway  = var.single_nat_gateway
  reuse_nat_ips       = true
  external_nat_ip_ids = [aws_eip.nat.id]

  # Tags that let Kubernetes / the AWS cloud-controller discover subnets later.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}
