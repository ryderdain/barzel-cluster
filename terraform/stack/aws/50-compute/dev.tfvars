# dev — layer 50 compute. Public nodes (direct operator access, /32-locked), spot
# for cheap iteration, no public NLB. Reproduces environments/dev/50-compute.
env                   = "dev"
public_nodes          = true
capacity_type         = "spot"
enable_public_ingress = false
