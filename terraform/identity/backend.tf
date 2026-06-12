terraform {
  backend "s3" {
    # bucket / region / dynamodb_table / encrypt come from ./backend.hcl
    # via: tofu init -backend-config=backend.hcl
    # Account-global (not per-env): its own top-level state key.
    key = "identity/terraform.tfstate"
  }
}
