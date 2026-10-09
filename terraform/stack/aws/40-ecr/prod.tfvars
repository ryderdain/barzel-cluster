# prod — layer 40 ECR. No kiesei (intentional: the conductor carries its own
# toolchain; recorded design choice). repositories + kiesei_build_enabled keep
# their defaults. Reproduces environments/prod/40-ecr. Credential ARNs come from
# credentials.auto.tfvars (account-level, shared with dev).
env = "prod"
