output "instance_ids" {
  description = "EC2 instance ids of the k3s nodes."
  value       = aws_instance.this[*].id
}

output "private_ips" {
  description = "Private IPs of the k3s nodes (in-VPC / Ansible over bastion)."
  value       = aws_instance.this[*].private_ip
}

output "public_ips" {
  description = "Public IPs of the k3s nodes (null when not associated)."
  value       = aws_instance.this[*].public_ip
}

output "ami_id" {
  description = "AMI the nodes booted from (resolved arm64 Ubuntu unless overridden)."
  value       = local.ami_id
}

output "ebs_kms_key_arn" {
  description = "CMK encrypting node EBS root volumes (passthrough from 15-kms; reuse for the gp3 StorageClass)."
  value       = var.ebs_kms_key_arn
}

# Pre-shaped for an Ansible inventory: one entry per node with the address
# Ansible should connect to (public IP when present, else private) plus useful
# facts. The compute env layer renders this into the inventory file.
# Ansible connects via SSM (SSH-over-SSM), so the connection target is the EC2
# instance-id, NOT an IP — the generator maps instance_id onto ansible_host. The
# IPs are informational (private for in-VPC reference; public, when present, for
# kubectl/API only).
output "ansible_inventory" {
  description = "Per-node facts for the Ansible inventory. Connection is by instance_id via SSM, not by IP."
  value = [
    for i, inst in aws_instance.this : {
      name        = "${var.name}-node-${i + 1}"
      instance_id = inst.id
      private_ip  = inst.private_ip
      public_ip   = inst.public_ip # null when not associated
      az          = inst.availability_zone
    }
  ]
}
