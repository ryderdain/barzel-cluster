terraform {
  # ONE bucket + ONE state CMK; env split by S3 object key, composed by the driver
  # at init (see terraform/stack/aws/10-network/backend.tf for the full rationale).
  # This layer's key: <env>/30-iam/terraform.tfstate.
  backend "s3" {}
}
