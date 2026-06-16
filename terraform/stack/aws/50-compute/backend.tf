terraform {
  # ONE bucket + ONE state CMK; env split by S3 object key, composed by the driver
  # at init (see terraform/stack/aws/10-network/backend.tf for the full rationale).
  # This layer's key: <env>/50-compute/terraform.tfstate.
  backend "s3" {}
}
