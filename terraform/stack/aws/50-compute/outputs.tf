output "instance_ids" {
  value = module.compute.instance_ids
}

output "private_ips" {
  value = module.compute.private_ips
}

output "public_ips" {
  description = "Public IPs per node, or null when public_nodes = false (private placement)."
  value       = module.compute.public_ips
}

output "demo_app_url" {
  description = "Public URL of the demo-app UI (only when enable_public_ingress; else null)."
  value       = length(aws_lb.demo_app) > 0 ? "http://${aws_lb.demo_app[0].dns_name}" : null
}

# Consumed by the Ansible inventory generator (instance-id SSM targets).
output "ansible_inventory" {
  value = module.compute.ansible_inventory
}
