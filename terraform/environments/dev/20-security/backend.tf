terraform {
  backend "s3" {
    # bucket / region / dynamodb_table / encrypt come from ../backend.hcl
    key = "dev/20-security.tfstate"
  }
}
