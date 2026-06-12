# Read lower layers. The state bucket name is DERIVED from the caller's account
# id at runtime — no TF_VAR to lose, no account id in git (see dev/20-security).
data "aws_caller_identity" "current" {}

locals {
  state_bucket = "brzl-demo-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "prod/10-network.tfstate"
    region = var.aws_region
  }
}
