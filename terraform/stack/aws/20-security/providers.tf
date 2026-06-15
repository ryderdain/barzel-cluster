terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Auto-detects the applying host's public /32 (main.tf data.http.myip) — no
    # external TF_VAR step; works from the conductor or a laptop.
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
      Environment = var.env
      ManagedBy   = "OpenTofu"
    }
  }
}
