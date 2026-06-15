# Layer 20 — security groups. Reads the VPC from layer 10. Single source for all
# AWS environments (model B); per-env inputs via <env>.tfvars.
#
# Lock the kube-API (and optional SSH) ingress to the /32 of WHOEVER applies this
# layer, fetched at plan time — re-read every plan, so it always reflects the
# applying host's current public egress IP (conductor or laptop), no external
# TF_VAR step. Set var.admin_cidr to pin a fixed range instead. In prod the nodes
# are PRIVATE with no public IP, so this rule is defense-in-depth with no
# internet-reachable surface (the kube-API is reached via an SSM port-forward; the
# only public ingress is the demo-app NLB at 50-compute).
data "http" "myip" {
  count = var.admin_cidr == "" ? 1 : 0
  url   = "https://ipv4.icanhazip.com"
}

locals {
  name       = "brzl-${var.env}"
  admin_cidr = var.admin_cidr != "" ? var.admin_cidr : "${chomp(data.http.myip[0].response_body)}/32"
}

module "security_groups" {
  source = "../../../modules/security-groups"

  name       = local.name
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  admin_cidr = local.admin_cidr

  # SSM Session Manager is the node-access path (SSH-over-SSM; no inbound :22). The
  # break-glass key still works over that tunnel; flip to true only to recover a
  # node with a dead SSM agent. Node-side SSM perms are granted in 30-iam.
  enable_ssh_ingress = var.enable_ssh_ingress
}
