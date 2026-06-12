terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bootstrap intentionally uses LOCAL state: it is the chicken-and-egg that
  # creates the S3 bucket + DynamoDB table every other layer's backend depends
  # on. The local state file is gitignored. After apply, you may optionally
  # migrate this state into the bucket it just created.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "brzl-demo"
      ManagedBy = "OpenTofu"
      Component = "tf-state-backend"
    }
  }
}
