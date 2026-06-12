# Instance role + profile attached to every k3s node. ONE role carries all the
# AWS access the nodes need — image pulls, EBS volume lifecycle for the CSI
# driver, and S3 access for Postgres backups — so we never mint a second IAM
# user (CLAUDE.md). Pattern follows ryderdain/tw-project (assume-role doc +
# inline role policies + instance profile).

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-node"
  role = aws_iam_role.node.name
}

# --- SSM Session Manager: keyless / SSH-over-SSM node access ---------------
# The node's SSM agent holds an OUTBOUND data channel to the SSM service; the
# operator's `aws ssm start-session` (and the Ansible SSH-over-SSM ProxyCommand)
# rides it — so no inbound :22 and no public IP are required. These actions do
# not support resource-level scoping, hence "*". This is the Session Manager
# subset of AmazonSSMManagedInstanceCore (no ec2messages legacy, no S3/KMS — we
# use SSH-over-SSM, not the Ansible aws_ssm S3-transfer plugin, so no bucket).
data "aws_iam_policy_document" "ssm_core" {
  count = var.enable_ssm ? 1 : 0

  statement {
    sid = "SsmSessionManager"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ssm_core" {
  count  = var.enable_ssm ? 1 : 0
  name   = "${var.name}-ssm-core"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.ssm_core[0].json
}

# --- ECR: pull images + OCI Helm charts (pull-through cache included) ---
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
  # Pull-through create-on-pull: the first pull of an upstream image must create
  # the cache repo and import the manifest. Scoped to the pull-through prefixes
  # (brzl-dev-k8s / -quay / -github / -docker-hub) — our own repos (brzl-dev/*)
  # already exist and don't need these. GetImageCopyStatus polls the async copy.
  statement {
    sid = "EcrPullThroughImport"
    actions = [
      "ecr:CreateRepository",
      "ecr:BatchImportUpstreamImage",
      "ecr:GetImageCopyStatus",
    ]
    resources = [
      "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/${var.name}-*",
    ]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${var.name}-ecr-pull"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

# --- EBS CSI driver: dynamic provisioning of gp3 PVCs + snapshots ---
data "aws_iam_policy_document" "ebs_csi" {
  statement {
    sid = "EbsCsi"
    actions = [
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:ModifyVolume",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
      "ec2:DescribeInstances",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeTags",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ebs_csi" {
  name   = "${var.name}-ebs-csi"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.ebs_csi.json
}

# --- S3 backups for CloudNativePG / Barman Cloud (optional until bucket exists) ---
data "aws_iam_policy_document" "s3_backup" {
  count = var.backup_bucket_arn == "" ? 0 : 1

  statement {
    sid       = "ListBackupBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.backup_bucket_arn]
  }
  statement {
    sid = "ReadWriteBackupObjects"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.backup_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_backup" {
  count  = var.backup_bucket_arn == "" ? 0 : 1
  name   = "${var.name}-s3-backup"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.s3_backup[0].json
}

# --- KMS: let Barman write/read SSE-KMS backup objects under our CMK ---
# The backup bucket's default encryption is SSE-KMS with a customer-managed key,
# so every PutObject/GetObject Barman issues needs GenerateDataKey/Decrypt on
# that key. Scoped to the single backup CMK (not "*").
data "aws_iam_policy_document" "backup_kms" {
  count = var.backup_kms_key_arn == "" ? 0 : 1

  statement {
    sid = "BackupBucketKms"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [var.backup_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "backup_kms" {
  count  = var.backup_kms_key_arn == "" ? 0 : 1
  name   = "${var.name}-backup-kms"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.backup_kms[0].json
}
