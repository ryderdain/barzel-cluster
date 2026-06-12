terraform {
  backend "s3" {
    # bucket / region / dynamodb_table / encrypt come from ../backend.hcl
    # via: tofu init -backend-config=../backend.hcl
    # Distinct key — this layer's state is independent; destroying it touches no
    # other layer's state or resources (the self-contained-conductor requirement).
    key = "dev/00-conductor.tfstate"
  }
}
