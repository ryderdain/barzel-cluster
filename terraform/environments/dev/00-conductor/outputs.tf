output "conductor_instance_id" {
  description = "Conductor instance id — the SSM Session Manager target."
  value       = aws_instance.conductor.id
}

output "ssm_session_command" {
  description = "Copy-paste to open a shell on the conductor (no SSH, no inbound)."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.conductor.id}"
}

output "conductor_ssh_command" {
  description = "SSH to the conductor THROUGH the SSM tunnel (raw channel for §1.8 piping; no inbound port)."
  value       = "ssh -i ${pathexpand("~/.ssh/${aws_key_pair.conductor.key_name}")} -o ProxyCommand='aws ssm start-session --region ${var.aws_region} --target ${aws_instance.conductor.id} --document-name AWS-StartSSHSession --parameters portNumber=%p' ec2-user@${aws_instance.conductor.id}"
}

output "conductor_ssh_key_path" {
  description = "Local path to the conductor's private key (in ~/.ssh, gitignored; destroyed with the box)."
  value       = local_sensitive_file.conductor_private_key.filename
}

output "conductor_public_ip" {
  description = "Public IP (informational: used only for outbound SSM/ECR/GitHub; nothing listens inbound)."
  value       = aws_instance.conductor.public_ip
}

output "conductor_vpc_id" {
  description = "The conductor's own throwaway VPC id."
  value       = aws_vpc.conductor.id
}
