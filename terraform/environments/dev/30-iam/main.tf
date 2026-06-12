# Layer 30 — IAM. Node instance role/profile. Reads 15-kms for the backup
# bucket + CMK (apply order: 15 before 30).
#
# The node role also carries the SSM Session Manager grant (module default
# enable_ssm = true) — the node-identity half of the keyless access model whose
# network half is 20-security (enable_ssh_ingress = false). Together: operators
# reach nodes via SSM (SSH-over-SSM), not an open :22. See docs/ACCESS.md.

locals {
  name = "brzl-dev"
}

module "iam" {
  source = "../../../modules/iam"

  name = local.name
  # Backup bucket + its CMK come from the persistent 15-kms layer. The node role
  # gets S3 read/write on the bucket plus the KMS grant Barman needs to write
  # SSE-KMS objects under our customer-managed key.
  backup_bucket_arn  = data.terraform_remote_state.kms.outputs.backup_bucket_arn
  backup_kms_key_arn = data.terraform_remote_state.kms.outputs.backup_kms_key_arn
  enable_ssm         = true
}
