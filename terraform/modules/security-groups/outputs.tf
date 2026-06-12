output "cluster_security_group_id" {
  description = "Security group attached to every k3s node (from the compute layer)."
  value       = aws_security_group.cluster.id
}
