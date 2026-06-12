# Layer 10 — network (prod). Same module as dev, prod inputs: its own CIDR so
# the two VPCs could peer if ever needed, and nodes live in the PRIVATE subnets
# (the 50-compute layer here never assigns a public IP).

locals {
  name = "brzl-prod"
}

module "network" {
  source = "../../../modules/network"

  name            = local.name
  cidr            = "10.20.0.0/16"
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

  # Real prod flips this to false (one NAT per AZ, AZ-independent egress). Kept
  # single for the PoC validation run — the prod *placement model* (private
  # nodes, NLB ingress) is what this environment proves, not the NAT bill.
  single_nat_gateway = var.single_nat_gateway
}
