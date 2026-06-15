# Read lower layers. Bucket DERIVED from the caller's account (no TF_VAR, no account
# id in git); the lower-layer key is composed from var.env so this layer reads ITS
# OWN environment's 10-network state — the env-keyed remote_state pattern every
# upper layer in the stack reuses.
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
