variable "aws_region" {
  description = "AWS region. Must match ../backend.hcl and every other dev layer."
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = <<-EOT
    Conductor instance type. MUST be arm64/Graviton (t4g.*) — the toolbox image and
    the demo-app/toolbox builds this box drives are linux/arm64. t4g.small is enough
    for tofu/ansible/kubectl/helm; bump to t4g.medium if local image builds (docker
    buildx) need the headroom.
  EOT
  type        = string
  default     = "t4g.small"

  validation {
    condition     = startswith(var.instance_type, "t4g.") || startswith(var.instance_type, "m6g.") || startswith(var.instance_type, "c6g.")
    error_message = "Conductor must be Graviton/arm64 (t4g.*/m6g.*/c6g.*) — the toolchain images are arm64."
  }
}

variable "vpc_cidr" {
  description = "CIDR for the conductor's OWN throwaway VPC (deliberately distinct from the cluster VPC so the two never collide and this layer is independent)."
  type        = string
  default     = "10.99.0.0/16"
}

variable "subnet_cidr" {
  description = "Public subnet CIDR within vpc_cidr (one AZ; the conductor is a single box)."
  type        = string
  default     = "10.99.1.0/24"
}

variable "root_volume_size" {
  description = "Root EBS size (GiB). Holds the toolchain + a repo checkout + tofu plugin cache."
  type        = number
  default     = 30
}

# The conductor holds NO repo credential. The operator's approved working tree is
# shipped to the state bucket from the laptop (gitops/tools/ship_repo.sh) and pulled
# by the conductor's `brzl-fetch` helper via its instance role — so the box runs
# exactly the snapshot the operator pushed over the audited channel, with nothing to
# authenticate to GitHub (CLAUDE.md §1.8). No git_repo_url / repo_read_secret_name var.

variable "tofu_version" {
  description = "Pinned OpenTofu version installed on the conductor (identical-toolchain goal)."
  type        = string
  default     = "1.8.5"
}

variable "kubectl_version" {
  description = "Pinned kubectl version (match the k3s server minor where it matters)."
  type        = string
  default     = "1.31.4"
}

variable "helm_version" {
  description = "Pinned Helm version."
  type        = string
  default     = "3.16.3"
}
