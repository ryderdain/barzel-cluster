# Read lower layers; bucket name derived from the caller's account id.
data "aws_caller_identity" "current" {}

locals {
  state_bucket = "brzl-demo-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "kms" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "prod/15-kms.tfstate"
    region = var.aws_region
  }
}
