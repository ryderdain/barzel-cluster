terraform {
  # ONE S3 bucket + ONE state CMK for every environment; environments are split by
  # the S3 OBJECT KEY. Nothing here is committed and there is NO gitignored
  # backend.hcl (the old per-env file is retired): the driver (gitops/tools/platform.sh)
  # composes the backend config at init time —
  #   bucket : DERIVED from the caller's account (brzl-demo-tfstate-<account_id>)
  #   key    : <env>/<layer>/terraform.tfstate   (the env split lives here)
  #   region / dynamodb_table / encrypt : fixed
  # so no account-bearing value or per-env path is kept in git or in operator memory
  # (the repo's derive-don't-remember rule). Manual init reference:
  #   acct="$(aws sts get-caller-identity --query Account --output text)"
  #   tofu init \
  #     -backend-config="bucket=brzl-demo-tfstate-${acct}" \
  #     -backend-config="key=dev/10-network/terraform.tfstate" \
  #     -backend-config="region=eu-central-1" \
  #     -backend-config="dynamodb_table=brzl-demo-tflock" \
  #     -backend-config="encrypt=true"
  backend "s3" {}
}
