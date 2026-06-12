# Layer 15 — KMS + durable backup storage (prod). Mirror of dev/15-kms with the
# prod name: the persistent foundation (EBS CMK, backup CMK, CNPG backup bucket)
# that outlives the churned compute layer. See dev/15-kms/main.tf for the full
# rationale (ADR-0006).

locals {
  name = "brzl-prod"
}

data "aws_caller_identity" "current" {}

# EC2 Spot SLR — resolve-or-create, same as dev (spot nodes can't attach their
# CMK-encrypted root volume without the key-policy grant).
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

module "kms_ebs" {
  source = "../../../modules/kms"

  alias       = "${local.name}-ebs"
  description = "${local.name} EBS volume encryption (node root disks + gp3 PVCs)"

  service_grant_principals = [local.ec2_spot_slr_arn]
}

module "kms_backup" {
  source = "../../../modules/kms"

  alias       = "${local.name}-backup"
  description = "${local.name} CloudNativePG/Barman S3 backup encryption"
}

module "backup" {
  source = "../../../modules/backup"

  bucket_name = "${local.name}-cnpg-backups-${data.aws_caller_identity.current.account_id}"
  kms_key_arn = module.kms_backup.key_arn
}

resource "aws_ssm_parameter" "backup_bucket" {
  name        = "/${local.name}/backup/bucket_name"
  description = "CNPG/Barman backup bucket name (resolved by GitOps bootstrap)."
  type        = "String"
  value       = module.backup.bucket_name
}
