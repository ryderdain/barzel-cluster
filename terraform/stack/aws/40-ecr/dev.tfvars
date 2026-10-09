# dev — layer 40 ECR. dev publishes the operator kiesei image (extra repo + build).
# Reproduces environments/dev/40-ecr. Credential ARNs come from credentials.auto.tfvars.
env                   = "dev"
repositories          = ["demo-app", "helm-charts", "kiesei"]
kiesei_build_enabled = true
