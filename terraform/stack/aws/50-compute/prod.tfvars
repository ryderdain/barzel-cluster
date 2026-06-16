# prod — layer 50 compute. Private nodes (SSM only), on-demand, demo-app NLB on
# (only public surface; lb_ingress_cidr auto-detects the admin /32 — set 0.0.0.0/0
# for a public demo). Reproduces environments/prod/50-compute.
env                   = "prod"
public_nodes          = false
capacity_type         = "on-demand"
enable_public_ingress = true
