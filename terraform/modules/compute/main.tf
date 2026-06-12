# The 3 k3s nodes. Graviton/arm64 by default, so the AMI lookup is pinned to
# arm64 — an x86 AMI under an m6g instance would simply fail to boot. Nodes are
# spread one-per-AZ across the subnets the env layer passes in (public in dev,
# private in prod) and carry the cluster SG + instance profile. user_data is
# intentionally minimal: Ansible does the real work. The SSH key_name is
# generated and owned by the env layer (see 50-compute/secrets.tf), so this
# module stays reusable and never writes to an operator's homedir.

# Latest Ubuntu 24.04 LTS (Noble) arm64, published by Canonical (099720109477).
data "aws_ami" "ubuntu_arm64" {
  count = var.ami_id == "" ? 1 : 0

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_arm64[0].id
}

# EBS root volumes are encrypted with the customer-managed key from the
# persistent dev/15-kms layer (passed in as ebs_kms_key_arn). The key used to be
# created here, but a CMK in this churned layer billed through its deletion window
# on every teardown — it now lives in 15-kms and survives compute destroy/recreate
# (ADR-0006).
resource "aws_instance" "this" {
  count = var.node_count

  ami                    = local.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  iam_instance_profile   = var.instance_profile_name
  vpc_security_group_ids = var.security_group_ids

  # Spot while iterating (≈70% cheaper), on-demand for the delivery demo
  # (SPEC §7.6). one-time + terminate keeps it simple: an interrupted node is
  # gone rather than lingering as a persistent request — fine because k3s state
  # doesn't survive compute teardown and we re-run Ansible each round anyway.
  dynamic "instance_market_options" {
    for_each = var.capacity_type == "spot" ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  # Spread nodes across the supplied subnets (one per AZ) round-robin.
  subnet_id                   = element(var.subnet_ids, count.index)
  associate_public_ip_address = var.associate_public_ip_address

  user_data = templatefile("${path.module}/user_data.yaml.tpl", {
    node_name = "${var.name}-node-${count.index + 1}"
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
    kms_key_id  = var.ebs_kms_key_arn
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-node-${count.index + 1}"
    Role = "k3s-server"
  })
}
