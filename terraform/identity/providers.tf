terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Used to fetch the GitHub OIDC endpoint's CA thumbprint at plan time, so we
    # never hardcode a fingerprint that can rotate.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "brzl-demo"
      ManagedBy = "OpenTofu"
      Component = "identity"
    }
  }
}
