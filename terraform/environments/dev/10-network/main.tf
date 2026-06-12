# Layer 10 — network. Lowest layer; produces the VPC every other layer reads.

locals {
  name = "brzl-dev"
}

module "network" {
  source = "../../../modules/network"

  name = local.name
  # cidr / azs / subnets use module defaults (10.10.0.0/16, eu-central-1{a,b,c}).
  single_nat_gateway = true # dev cost lever
}
