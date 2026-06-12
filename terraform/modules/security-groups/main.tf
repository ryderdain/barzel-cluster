# One security group for the k3s cluster. Node-to-node rules are
# self-referencing (source = this SG) so the 3 servers can run HA embedded etcd
# and the CNI mesh; the Kubernetes API and SSH are reachable from the operator's
# IP only. Separate aws_security_group_rule resources (ryderdain/tw-project style)
# keep each port auditable on its own.

resource "aws_security_group" "cluster" {
  name        = "${var.name}-cluster"
  description = "k3s HA cluster: node-to-node mesh + admin API/SSH"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-cluster" })
}

# --- Egress: allow all outbound (image pulls via NAT, ECR, S3 backups) ---
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "All outbound"
}

# --- Admin access from the operator's IP only ---
# SSH ingress is OPTIONAL: with SSM Session Manager (SSH-over-SSM) the operator
# reaches sshd through the agent's outbound channel, so no inbound :22 is needed.
# Leave this off (enable_ssh_ingress=false) once SSM is the access path; flip it
# on only for break-glass recovery of a node whose SSM agent is down.
resource "aws_security_group_rule" "ssh_admin" {
  count             = var.enable_ssh_ingress ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "SSH from admin IP (break-glass; SSM is the primary path)"
}

resource "aws_security_group_rule" "kube_api_admin" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API from admin IP (kubectl / ArgoCD CLI)"
}

# --- Node-to-node (self-referencing): the k3s HA control plane mesh ---
resource "aws_security_group_rule" "node_kube_api" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.cluster.id
  description              = "Kubernetes API between nodes"
}

resource "aws_security_group_rule" "node_etcd" {
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2380
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.cluster.id
  description              = "Embedded etcd client + peer (HA)"
}

resource "aws_security_group_rule" "node_flannel_vxlan" {
  type                     = "ingress"
  from_port                = 8472
  to_port                  = 8472
  protocol                 = "udp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.cluster.id
  description              = "Flannel VXLAN (default k3s CNI)"
}

resource "aws_security_group_rule" "node_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.cluster.id
  description              = "Kubelet metrics between nodes"
}

resource "aws_security_group_rule" "node_nodeport" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.cluster.id
  description              = "NodePort range between nodes"
}
