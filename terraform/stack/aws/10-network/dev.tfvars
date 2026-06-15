# dev environment — layer 10 network. Committed (non-secret: CIDRs + flags). These
# values reproduce the former environments/dev/10-network exactly (which relied on
# the network module's defaults). azs uses the module/stack default.
env             = "dev"
vpc_cidr        = "10.10.0.0/16"
private_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
public_subnets  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]

# dev cost lever — one shared NAT.
single_nat_gateway = true
