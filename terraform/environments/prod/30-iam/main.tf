# Layer 30 — IAM (prod). Node instance role/profile; reads prod 15-kms for the
# backup bucket + CMK. Pull-through create-on-pull perms are scoped to the
# brzl-prod-* cache prefixes by the module (var.name).

locals {
  name = "brzl-prod"
}

module "iam" {
  source = "../../../modules/iam"

  name               = local.name
  backup_bucket_arn  = data.terraform_remote_state.kms.outputs.backup_bucket_arn
  backup_kms_key_arn = data.terraform_remote_state.kms.outputs.backup_kms_key_arn
  enable_ssm         = true
}
