variable "name" {
  description = "Name prefix for compute resources (e.g. brzl-dev)."
  type        = string
}

variable "node_count" {
  description = "Number of k3s nodes. 3 for HA (3 servers, embedded etcd)."
  type        = number
  default     = 3
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type. Defaults to Graviton (arm64). m6g.large = 2 vCPU / 8 GiB,
    comfortable for an HA k3s server + a CloudNativePG instance + the monitoring
    stack added later. Cheaper lever: m6g.medium (1 vCPU / 4 GiB).
    NOTE: must be an arm64 family to match the arm64 AMI below.
  EOT
  type        = string
  default     = "m6g.large"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB (gp3)."
  type        = number
  default     = 30
}

variable "ami_id" {
  description = "Override AMI id. Empty = look up latest Ubuntu 24.04 LTS arm64."
  type        = string
  default     = ""
}

variable "key_name" {
  description = <<-EOT
    Name of an existing EC2 key pair to attach to every node. The env layer
    generates the key pair (tls_private_key + aws_key_pair) and owns the private
    key file, then passes its name here — keeping this module reusable and free
    of any operator-homedir side effects. Ansible connects over this key.
  EOT
  type        = string
}

variable "capacity_type" {
  description = <<-EOT
    EC2 purchasing option: "spot" (≈70% cheaper, for iteration) or "on-demand"
    (stable, for the delivery demo). See SPEC §7.6. When "spot", nodes are
    launched with instance_market_options (one-time, terminate-on-interrupt).
  EOT
  type        = string
  default     = "spot"

  validation {
    condition     = contains(["spot", "on-demand"], var.capacity_type)
    error_message = "capacity_type must be \"spot\" or \"on-demand\"."
  }
}

variable "subnet_ids" {
  description = "Subnet ids to place nodes in, one per AZ (from network layer)."
  type        = list(string)
}

variable "associate_public_ip_address" {
  description = <<-EOT
    Give each node a public IP. true in dev for direct, SG-locked admin SSH +
    kubectl reachability without standing up a bastion. In prod set false and
    place nodes in PRIVATE subnets, reaching them via a bastion or SSM Session
    Manager. SSH/API exposure is still constrained to admin_cidr by the SG.
  EOT
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "Security groups attached to every node (from security layer)."
  type        = list(string)
}

variable "instance_profile_name" {
  description = "IAM instance profile attached to every node (from iam layer)."
  type        = string
}

variable "ebs_kms_key_arn" {
  description = <<-EOT
    CMK ARN encrypting node EBS root volumes, from the persistent dev/15-kms
    layer. Kept out of this (churned) layer so a compute teardown never schedules
    the key for deletion (ADR-0006). The same key backs the gp3 StorageClass.
  EOT
  type        = string
}

variable "tags" {
  description = "Tags merged onto compute resources."
  type        = map(string)
  default     = {}
}
