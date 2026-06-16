# Layer 50 — compute. The 3 k3s nodes, wired from layers 10/15/20/30. Single source
# for all AWS environments (model B); per-env inputs via <env>.tfvars.
#
# Node placement is an input (var.public_nodes): dev puts nodes in the PUBLIC subnets
# with public IPs (operator SSH/API direct, still /32-locked by the layer-20 SG);
# prod puts them PRIVATE with no public IP (reached via SSM; the only public surface
# is the optional demo-app NLB — ingress.tf, var.enable_public_ingress). The same
# stack proves both placement models; an env adopts the other by flipping the input.

locals {
  name = "brzl-${var.env}"
}

module "compute" {
  source = "../../../modules/compute"

  name          = local.name
  node_count    = 3
  instance_type = var.instance_type
  capacity_type = var.capacity_type

  key_name                    = aws_key_pair.node.key_name
  subnet_ids                  = var.public_nodes ? data.terraform_remote_state.network.outputs.public_subnet_ids : data.terraform_remote_state.network.outputs.private_subnet_ids
  associate_public_ip_address = var.public_nodes
  security_group_ids          = [data.terraform_remote_state.security.outputs.cluster_security_group_id]
  instance_profile_name       = data.terraform_remote_state.iam.outputs.instance_profile_name
  ebs_kms_key_arn             = data.terraform_remote_state.kms.outputs.ebs_kms_key_arn
}
