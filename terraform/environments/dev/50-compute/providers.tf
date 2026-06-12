terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Generate the node SSH key pair in-band (see secrets.tf) so there's no
    # manual key step and the key is tracked in state for reproducible apply.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "brzl-demo"
      Environment = "dev"
      ManagedBy   = "OpenTofu"
    }
  }
}
