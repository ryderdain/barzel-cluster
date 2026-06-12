# Layer 20 — security groups (prod). Reads the VPC from layer 10.
#
# Nodes here sit in PRIVATE subnets with no public IP, so the admin-/32 API rule
# the module always writes is defense-in-depth with no reachable surface — the
# kube-API is reached via an SSM port-forward (docs/ACCESS.md), and the only
# public ingress in the whole environment is the demo-app NLB (50-compute).

data "http" "myip" {
  count = var.admin_cidr == "" ? 1 : 0
  url   = "https://ipv4.icanhazip.com"
}

locals {
  name       = "brzl-prod"
  admin_cidr = var.admin_cidr != "" ? var.admin_cidr : "${chomp(data.http.myip[0].response_body)}/32"
}

module "security_groups" {
  source = "../../../modules/security-groups"

  name       = local.name
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  admin_cidr = local.admin_cidr

  # SSM is the only node-access path; private nodes have no :22 to open anyway.
  enable_ssh_ingress = false
}
