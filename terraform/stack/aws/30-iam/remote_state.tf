# Read the persistent foundation (15-kms) for the CNPG/Barman backup bucket + its
# CMK, so the node role gets exactly the S3 + KMS grants Barman needs (instance
# profile, no second IAM user). Apply order: 15 before 30. Bucket DERIVED from the
# caller's account; the lower-layer key is composed from var.env (env-keyed
# remote_state) so this layer reads ITS OWN env's 15-kms state.
data "aws_caller_identity" "current" {}

locals {
  state_bucket = "brzl-demo-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "terraform_remote_state" "kms" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "${var.env}/15-kms/terraform.tfstate"
    region = var.aws_region
  }
}
