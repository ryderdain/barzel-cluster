# Layer 15 — KMS + durable backup storage. Single source for all AWS environments
# (model B). The PERSISTENT foundation that must outlive the compute layer (50) we
# destroy between iterations:
#   - the EBS CMK that encrypts node root disks + gp3 PVCs (moved here from the
#     compute module so a `tofu destroy` of 50 no longer schedules it for deletion
#     and bills through the window — ADR-0006);
#   - a separate CMK for Postgres backups, and the S3 bucket CNPG/Barman writes to
#     (so backups survive every teardown).
#
# No lower-layer dependency. Apply order: 10-network -> 15-kms -> 20-security ->
# 30-iam (reads this for backup bucket + key) -> 40-ecr -> 50-compute (reads this
# for the EBS key).

locals {
  name = "brzl-${var.env}"
}

data "aws_caller_identity" "current" {}

# The EC2 Spot service-linked role must be able to use the EBS CMK, or spot nodes
# (50-compute capacity_type=spot, the cheap-iteration default) fail to attach their
# encrypted root volume and are terminated on launch. AWS auto-creates this role on
# first spot use; resolve it if present, create it if a from-zero account hasn't yet
# (aws_iam_roles returns [] rather than erroring when it's absent).
data "aws_iam_roles" "ec2_spot" {
  name_regex  = "AWSServiceRoleForEC2Spot"
  path_prefix = "/aws-service-role/spot.amazonaws.com/"
}

resource "aws_iam_service_linked_role" "ec2_spot" {
  count            = length(data.aws_iam_roles.ec2_spot.arns) == 0 ? 1 : 0
  aws_service_name = "spot.amazonaws.com"
}

locals {
  ec2_spot_slr_arn = length(data.aws_iam_roles.ec2_spot.arns) > 0 ? (
    tolist(data.aws_iam_roles.ec2_spot.arns)[0]
  ) : aws_iam_service_linked_role.ec2_spot[0].arn
}

# EBS volume / gp3 PVC encryption. Imported from the old compute-layer key so the
# physical key is preserved (no new key, no re-encrypt) — see UPGRADE.md.
module "kms_ebs" {
  source = "../../../modules/kms"

  alias       = "${local.name}-ebs"
  description = "${local.name} EBS volume encryption (node root disks + gp3 PVCs)"

  # Spot nodes' encrypted root volumes are attached by the EC2 Spot SLR, which can
  # only be granted in the key policy (see modules/kms). On-demand doesn't need it.
  service_grant_principals = [local.ec2_spot_slr_arn]
}

# CloudNativePG / Barman backup encryption (bucket default SSE-KMS).
module "kms_backup" {
  source = "../../../modules/kms"

  alias       = "${local.name}-backup"
  description = "${local.name} CloudNativePG/Barman S3 backup encryption"
}

module "backup" {
  source = "../../../modules/backup"

  # Account id makes the name globally unique without committing it to git.
  bucket_name = "${local.name}-cnpg-backups-${data.aws_caller_identity.current.account_id}"
  kms_key_arn = module.kms_backup.key_arn
}

# Publish the backup bucket name as config (like the ECR registry host): a plain
# SSM String, so the GitOps bootstrap can resolve the __BACKUP_BUCKET__ sentinel
# in the CNPG manifests without the account-bearing name landing in git.
resource "aws_ssm_parameter" "backup_bucket" {
  name        = "/${local.name}/backup/bucket_name"
  description = "CNPG/Barman backup bucket name (resolved by GitOps bootstrap)."
  type        = "String"
  value       = module.backup.bucket_name
}
