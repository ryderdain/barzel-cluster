# Layer 50 — compute (prod). The 3 k3s nodes, wired from layers 10/15/20/30.
#
# This is the prod placement model dev documents: nodes in the PRIVATE subnets,
# no public IPs, egress via NAT. Operators reach nodes via SSM (SSH-over-SSM,
# unchanged — the agent's channel is outbound) and the kube-API via an SSM
# port-forward (docs/ACCESS.md). The only public surface is the demo-app NLB
# (ingress.tf).

locals {
  name = "brzl-prod"
}

module "compute" {
  source = "../../../modules/compute"

  name          = local.name
  node_count    = 3
  instance_type = var.instance_type
  capacity_type = var.capacity_type

  key_name                    = aws_key_pair.node.key_name
  subnet_ids                  = data.terraform_remote_state.network.outputs.private_subnet_ids
  associate_public_ip_address = false
  security_group_ids          = [data.terraform_remote_state.security.outputs.cluster_security_group_id]
  instance_profile_name       = data.terraform_remote_state.iam.outputs.instance_profile_name
  ebs_kms_key_arn             = data.terraform_remote_state.kms.outputs.ebs_kms_key_arn
}
