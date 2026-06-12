variable "name" {
  description = "Name prefix for security groups (e.g. brzl-dev)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster security group belongs to (from the network layer)."
  type        = string
}

variable "admin_cidr" {
  description = <<-EOT
    CIDR allowed to reach the nodes from the operator's IP — one /32, normally.
    The env layer derives this: the 20-security layer auto-detects the applying
    host's public /32 at plan time (an http data source — works from the conductor
    or a laptop), or pins a fixed range via its own var.admin_cidr. Defaulting to
    0.0.0.0/0 is intentionally disallowed (see validation). Gates the Kubernetes
    API rule always, and the SSH rule when enable_ssh_ingress is true.
  EOT
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must not be 0.0.0.0/0 — lock access to your own /32."
  }
}

variable "enable_ssh_ingress" {
  description = <<-EOT
    Open inbound TCP/22 (SSH) from admin_cidr. Default true for a plain
    SSH/bastion workflow. Set FALSE once SSM Session Manager is the access path:
    SSH-over-SSM tunnels to the node's *local* sshd via the SSM agent's outbound
    data channel, so no inbound :22 is needed (see docs/ACCESS.md). The
    break-glass key still works over that tunnel; re-enable this only to recover
    a node whose SSM agent is down.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags merged onto the security group."
  type        = map(string)
  default     = {}
}
