# Layer 20 — security groups. Reads the VPC from layer 10.

# Lock SSH + the kube-API ingress to the /32 of WHOEVER applies this layer, fetched
# at plan time. Data sources re-read on every plan, so the rule always reflects the
# applying host's current public egress IP — no external `TF_VAR_mycurrentip` step,
# and it works identically from the conductor (its public IP — which is why the box
# keeps one) or a laptop. Set var.admin_cidr to pin a fixed range instead (e.g. an
# office CIDR); leave it empty (the default) to auto-detect.
data "http" "myip" {
  count = var.admin_cidr == "" ? 1 : 0
  url   = "https://ipv4.icanhazip.com"
}

locals {
  name       = "brzl-dev"
  admin_cidr = var.admin_cidr != "" ? var.admin_cidr : "${chomp(data.http.myip[0].response_body)}/32"
}

module "security_groups" {
  source = "../../../modules/security-groups"

  name       = local.name
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  admin_cidr = local.admin_cidr

  # SSM Session Manager is the node-access path (SSH-over-SSM tunnels to the
  # node's local sshd — no inbound :22). The break-glass key still works over
  # that tunnel; flip this to true only to recover a node with a dead SSM agent.
  # Node-side SSM permissions are granted in 30-iam; see docs/ACCESS.md.
  enable_ssh_ingress = false
}
