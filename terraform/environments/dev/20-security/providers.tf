terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Fetches the applying host's public IP at plan time (main.tf data.http.myip),
    # so the admin /32 needs no external TF_VAR — works on the conductor or a laptop.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
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
