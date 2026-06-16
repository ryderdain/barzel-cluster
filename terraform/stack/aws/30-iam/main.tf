# Layer 30 — IAM. Node instance role/profile. Reads 15-kms for the backup bucket +
# CMK (apply order: 15 before 30). Single source for all AWS environments (model B).
#
# The node role carries the SSM Session Manager grant (module default enable_ssm =
# true) — the node-identity half of the keyless access model whose network half is
# 20-security (enable_ssh_ingress = false): operators reach nodes via SSM
# (SSH-over-SSM), not an open :22. Pull-through create-on-pull perms are scoped to
# this env's brzl-<env>-* cache prefixes by the module (var.name).

locals {
  name = "brzl-${var.env}"
}

module "iam" {
  source = "../../../modules/iam"

  name = local.name
  # Backup bucket + its CMK come from the persistent 15-kms layer. The node role
  # gets S3 read/write on the bucket plus the KMS grant Barman needs to write
  # SSE-KMS objects under our customer-managed key — authenticating via this
  # instance profile, never a second IAM user.
  backup_bucket_arn  = data.terraform_remote_state.kms.outputs.backup_bucket_arn
  backup_kms_key_arn = data.terraform_remote_state.kms.outputs.backup_kms_key_arn
  enable_ssm         = true
}
