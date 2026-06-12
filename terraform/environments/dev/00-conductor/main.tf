# 00-conductor — a self-contained, disposable operator "conductor": one Graviton EC2
# running the pinned toolchain, reached ONLY via SSM Session Manager (no inbound),
# from which the A2 bring-up + DR restore is driven. This layer owns EVERYTHING it
# needs (its own VPC/subnet/IGW/SG/IAM) and reads NO other layer's state, so it can be
# applied and destroyed at any time without touching network/identity/kms/compute.
# DRY is deliberately relaxed here (CLAUDE.md): a throwaway control box, not shared infra.
#
# Cost: just the t4g.small + its gp3 root (~$0.40/day). NO NAT and NO VPC endpoints —
# the SSM agent reaches SSM outbound over the IGW (public IP, egress-only SG); the
# operator enters with `aws ssm start-session` (zero inbound).

data "aws_caller_identity" "current" {}

# Newest Amazon Linux 2023 arm64 AMI (ships the SSM agent; dnf-based).
data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
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

# --- Network (own, throwaway) -------------------------------------------------

resource "aws_vpc" "conductor" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "brzl-dev-conductor" }
}

resource "aws_internet_gateway" "conductor" {
  vpc_id = aws_vpc.conductor.id
  tags   = { Name = "brzl-dev-conductor" }
}

# Single public subnet in the first AZ — the conductor is one box.
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "conductor" {
  vpc_id                  = aws_vpc.conductor.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "brzl-dev-conductor" }
}

resource "aws_route_table" "conductor" {
  vpc_id = aws_vpc.conductor.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.conductor.id
  }
  tags = { Name = "brzl-dev-conductor" }
}

resource "aws_route_table_association" "conductor" {
  subnet_id      = aws_subnet.conductor.id
  route_table_id = aws_route_table.conductor.id
}

# Egress-only SG: NO inbound (SSM needs none). Outbound HTTPS reaches the SSM
# endpoints, ECR, GitHub, package mirrors, and the cluster's public API.
resource "aws_security_group" "conductor" {
  name        = "brzl-dev-conductor"
  description = "Conductor: egress-only; access via SSM Session Manager (no inbound)."
  vpc_id      = aws_vpc.conductor.id

  egress {
    description = "All outbound (SSM, ECR, GitHub, package mirrors, kube API)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "brzl-dev-conductor" }
}

# --- IAM (self-contained: PowerUser + scoped IAM + SSM, mirrors brzl-tofu-apply) ---

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "conductor" {
  name               = "brzl-dev-conductor"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = { Name = "brzl-dev-conductor" }
}

# PowerUserAccess covers s3/dynamodb (state), ec2, ssm, ecr, secretsmanager — i.e.
# everything the dev layers + A2 need EXCEPT IAM. SSM core enables Session Manager.
resource "aws_iam_role_policy_attachment" "poweruser" {
  role       = aws_iam_role.conductor.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.conductor.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The IAM gap PowerUser leaves: the 30-iam layer creates the node role/profile/policies.
# Grant scoped IAM mutate on brzl-* resources + PassRole, plus account-wide IAM READ
# (List/Get need "*"). This duplicates the apply-role's shape, deliberately (DRY relaxed).
data "aws_iam_policy_document" "conductor_iam" {
  statement {
    sid       = "IamReadOnlyAccountWide"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*", "iam:GenerateServiceLastAccessedDetails"]
    resources = ["*"]
  }

  statement {
    sid    = "IamManageEnclvScoped"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
      "iam:CreateServiceLinkedRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/brzl-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/brzl-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/brzl-*",
    ]
  }

  statement {
    sid       = "PassEnclvRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/brzl-*"]
  }
}

resource "aws_iam_role_policy" "conductor_iam" {
  name   = "brzl-conductor-iam-scoped"
  role   = aws_iam_role.conductor.id
  policy = data.aws_iam_policy_document.conductor_iam.json
}

resource "aws_iam_instance_profile" "conductor" {
  name = "brzl-dev-conductor"
  role = aws_iam_role.conductor.name
}

# --- SSH-over-SSM keypair (lifecycle-scoped to this box) ----------------------
# A Terraform-generated keypair created and destroyed WITH the conductor gives a raw
# SSH channel THROUGH the SSM tunnel (an AWS-StartSSHSession ProxyCommand) — for §1.8
# command/data piping from the laptop and a clean shell. This is NOT an inbound
# opening: the SG stays egress-only and SSM forwards to localhost:22 on the box. The
# public half rides the instance's key_name (cloud-init injects it into ec2-user's
# authorized_keys); the private half is written to the operator's ~/.ssh, never to git.
# Well-scoped: it exists only for the throwaway conductor's lifetime.
resource "tls_private_key" "conductor" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "conductor" {
  key_name   = "brzl-dev-conductor"
  public_key = tls_private_key.conductor.public_key_openssh
}

resource "local_sensitive_file" "conductor_private_key" {
  filename             = pathexpand("~/.ssh/${aws_key_pair.conductor.key_name}")
  file_permission      = "400"
  directory_permission = "700"
  content              = tls_private_key.conductor.private_key_pem
}

# --- Instance -----------------------------------------------------------------

resource "aws_instance" "conductor" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.conductor.id
  vpc_security_group_ids = [aws_security_group.conductor.id]
  iam_instance_profile   = aws_iam_instance_profile.conductor.name
  key_name               = aws_key_pair.conductor.key_name # SSH-over-SSM (no inbound)

  user_data = templatefile("${path.module}/cloud-init.yaml.tpl", {
    aws_region      = var.aws_region
    tofu_version    = var.tofu_version
    kubectl_version = var.kubectl_version
    helm_version    = var.helm_version
  })

  # IMDSv2 required (token-bound metadata) — instance-role creds aren't reachable
  # by SSRF-style metadata theft.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = { Name = "brzl-dev-conductor" }
}
