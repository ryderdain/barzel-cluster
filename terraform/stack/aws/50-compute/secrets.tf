# Node SSH key pair, generated and managed by OpenTofu (pattern from
# ryderdain/tw-project secrets.tf): no manual key creation, no public key passed in
# as a variable, and the private key is tracked in state so apply is reproducible.
# Owned by this layer rather than the compute module so the operator-homedir side
# effect (writing ~/.ssh/<key>) stays out of the reusable module.
#
# Tradeoff (accepted): the private key lands in remote state, encrypted at rest with
# the customer-managed state CMK (SPEC §3). Because this lives in 50-compute, the key
# is regenerated whenever the compute layer is torn down/reapplied during iteration —
# harmless (k3s state doesn't survive compute teardown; Ansible re-runs each round).
# Break-glass only — SSM (SSH-over-SSM) is the node-access path.

resource "tls_private_key" "node" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "node" {
  key_name   = "${local.name}-node"
  public_key = tls_private_key.node.public_key_openssh
}

resource "local_sensitive_file" "node_private_key" {
  filename             = pathexpand("~/.ssh/${aws_key_pair.node.key_name}")
  file_permission      = "400"
  directory_permission = "700"
  content              = tls_private_key.node.private_key_pem
}
