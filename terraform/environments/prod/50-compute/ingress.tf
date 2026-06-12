# Public ingress for the demo-app UI — and ONLY the demo-app UI.
#
# Self-managed k3s has no AWS cloud-controller, so a Service of type
# LoadBalancer would sit Pending forever; the NLB is therefore Terraform-owned
# (the same seam ADR-0018 names for promoting SSO to AWS). Path:
#
#   client → NLB :80 (public subnets, SG-gated)
#          → NodePort 30080 on the private nodes (the prod ApplicationSet
#            patches the demo-app Service to NodePort — gitops/clusters/prod)
#
# The node SG admits 30080 only from the NLB's SG; the NLB admits :80 only from
# var.lb_ingress_cidr (auto-detected admin /32 by default — flip to 0.0.0.0/0
# for a public demo). Cost: ~$0.02/hr + LCU (cost-leak watch: an NLB survives
# nothing — it's in this churned layer on purpose).

data "http" "myip" {
  count = var.lb_ingress_cidr == "" ? 1 : 0
  url   = "https://ipv4.icanhazip.com"
}

locals {
  lb_ingress_cidr   = var.lb_ingress_cidr != "" ? var.lb_ingress_cidr : "${chomp(data.http.myip[0].response_body)}/32"
  demo_app_nodeport = 30080
}

resource "aws_security_group" "nlb" {
  name        = "${local.name}-demo-app-nlb"
  description = "demo-app NLB: client :80 in, NodePort to the nodes out"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = { Name = "${local.name}-demo-app-nlb" }
}

resource "aws_security_group_rule" "nlb_http_in" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [local.lb_ingress_cidr]
  security_group_id = aws_security_group.nlb.id
  description       = "demo-app UI (HTTP) from the allowed range"
}

resource "aws_security_group_rule" "nlb_nodeport_out" {
  type              = "egress"
  from_port         = local.demo_app_nodeport
  to_port           = local.demo_app_nodeport
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.network.outputs.vpc_cidr]
  security_group_id = aws_security_group.nlb.id
  description       = "Forward to the demo-app NodePort on the nodes"
}

# The matching hole in the cluster SG: NodePort from the NLB only — not from
# the VPC at large, and never from the internet.
resource "aws_security_group_rule" "node_demo_app_from_nlb" {
  type                     = "ingress"
  from_port                = local.demo_app_nodeport
  to_port                  = local.demo_app_nodeport
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nlb.id
  security_group_id        = data.terraform_remote_state.security.outputs.cluster_security_group_id
  description              = "demo-app NodePort from the NLB"
}

resource "aws_lb" "demo_app" {
  name               = "${local.name}-demo-app"
  load_balancer_type = "network"
  internal           = false
  subnets            = data.terraform_remote_state.network.outputs.public_subnet_ids
  security_groups    = [aws_security_group.nlb.id]
}

resource "aws_lb_target_group" "demo_app" {
  name     = "${local.name}-demo-app"
  port     = local.demo_app_nodeport
  protocol = "TCP"
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  # TCP health check against the NodePort itself: kube-proxy answers on every
  # node (externalTrafficPolicy Cluster), so a node is healthy iff its kube-proxy
  # is — app health stays the cluster's concern (readiness probes).
  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }
}

resource "aws_lb_target_group_attachment" "demo_app" {
  count            = length(module.compute.instance_ids)
  target_group_arn = aws_lb_target_group.demo_app.arn
  target_id        = module.compute.instance_ids[count.index]
  port             = local.demo_app_nodeport
}

resource "aws_lb_listener" "demo_app_http" {
  load_balancer_arn = aws_lb.demo_app.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_app.arn
  }
}
