# dev — layer 40 ECR. dev publishes the operator toolbox image (extra repo + build).
# Reproduces environments/dev/40-ecr. Credential ARNs come from credentials.auto.tfvars.
env                   = "dev"
repositories          = ["demo-app", "helm-charts", "toolbox"]
toolbox_build_enabled = true
