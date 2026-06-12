# Read the persistent foundation layer (15-kms) for the CNPG/Barman backup bucket
# and its CMK, so the node role gets exactly the S3 + KMS grants Barman needs —
# authenticating via this instance profile, never a second IAM user (CLAUDE.md).
# Apply order: 15 before 30. The state bucket name is DERIVED from the caller's
# account id at runtime (a data source) — no TF_VAR to remember/lose, no account id
# in git, and it always matches the `bucket` in ../backend.hcl. (The backend block
# can't reference a data source, which is why ../backend.hcl still carries the
# literal name — set once from backend.hcl.example at bootstrap.)
data "aws_caller_identity" "current" {}

locals {
  state_bucket = "brzl-demo-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "kms" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "dev/15-kms.tfstate"
    region = var.aws_region
  }
}
