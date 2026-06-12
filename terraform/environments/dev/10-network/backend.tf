terraform {
  backend "s3" {
    # bucket / region / dynamodb_table / encrypt come from ../backend.hcl
    # via: tofu init -backend-config=../backend.hcl
    key = "dev/10-network.tfstate"
  }
}
