# prod environment — layer 10 network. Committed (non-secret: CIDRs + flags). These
# values reproduce the former environments/prod/10-network exactly: its own CIDR (so
# the dev/prod VPCs could peer if ever needed), private-subnet node placement proven
# by 50-compute. azs uses the default. single_nat kept single for the PoC validation
# run (real prod flips to false — one NAT per AZ); the prod placement model is what
# this env proves, not the NAT bill.
env             = "prod"
vpc_cidr        = "10.20.0.0/16"
private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

single_nat_gateway = true
