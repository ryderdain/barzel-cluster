# Node SSH key pair, generated and managed by OpenTofu — same pattern and
# tradeoffs as dev/50-compute/secrets.tf (key in CMK-encrypted state;
# regenerated with every compute teardown; break-glass only, SSM is the path).

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
