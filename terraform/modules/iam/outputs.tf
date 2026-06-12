output "instance_profile_name" {
  description = "Instance profile attached to the k3s nodes (from the compute layer)."
  value       = aws_iam_instance_profile.node.name
}

output "role_arn" {
  description = "ARN of the node role (for trust policies / cross-references)."
  value       = aws_iam_role.node.arn
}

output "role_name" {
  description = "Name of the node role."
  value       = aws_iam_role.node.name
}
