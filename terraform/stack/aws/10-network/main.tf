# Layer 10 — network. Lowest layer; produces the VPC every other layer reads.
#
# SINGLE SOURCE for all AWS environments (model B). One definition; per-env inputs
# arrive via `<env>.tfvars` (-var-file). The dev→prod promotion gate is preserved by
# what stays SEPARATE — distinct state (its own S3 object key) and an independent
# apply per env — not by duplicating this source. The only per-env edit surface is
# the committed `dev.tfvars` / `prod.tfvars`; real env differences are explicit there.

locals {
  name = "brzl-${var.env}"
}

module "network" {
  source = "../../../modules/network"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = var.azs
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  single_nat_gateway = var.single_nat_gateway
}
