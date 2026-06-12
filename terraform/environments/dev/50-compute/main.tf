# Layer 50 — compute. The 3 k3s nodes, wired from layers 10/20/30.
#
# In dev, nodes go in the PUBLIC subnets with public IPs so the operator can SSH
# (Ansible) and reach the API directly — access is still locked to your /32 by
# the layer-20 SG. In prod, place nodes in private subnets, set
# associate_public_ip_address = false, and reach them via a bastion / SSM.

locals {
  name = "brzl-dev"
}

module "compute" {
  source = "../../../modules/compute"

  name          = local.name
  node_count    = 3
  instance_type = var.instance_type
  capacity_type = var.capacity_type

  key_name                    = aws_key_pair.node.key_name
  subnet_ids                  = data.terraform_remote_state.network.outputs.public_subnet_ids
  associate_public_ip_address = true
  security_group_ids          = [data.terraform_remote_state.security.outputs.cluster_security_group_id]
  instance_profile_name       = data.terraform_remote_state.iam.outputs.instance_profile_name
  ebs_kms_key_arn             = data.terraform_remote_state.kms.outputs.ebs_kms_key_arn
}
