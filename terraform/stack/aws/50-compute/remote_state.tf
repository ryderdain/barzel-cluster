# Read lower layers. Bucket DERIVED from the caller's account (no TF_VAR, no account
# id in git); each lower-layer key is composed from var.env (env-keyed remote_state)
# so this layer reads ITS OWN environment's 10/15/20/30 state.
data "aws_caller_identity" "current" {}

locals {
  state_bucket = "brzl-demo-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${var.env}/10-network/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "kms" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${var.env}/15-kms/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${var.env}/20-security/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${var.env}/30-iam/terraform.tfstate"
    region = var.aws_region
  }
}
