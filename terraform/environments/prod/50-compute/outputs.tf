output "instance_ids" {
  value = module.compute.instance_ids
}

output "private_ips" {
  value = module.compute.private_ips
}

output "public_ips" {
  description = "Always null per node here (private placement); kept for tooling parity."
  value       = module.compute.public_ips
}

output "demo_app_url" {
  description = "Public URL of the demo-app UI (the only public surface)."
  value       = "http://${aws_lb.demo_app.dns_name}"
}

# Consumed by the Ansible inventory generator (instance-id SSM targets).
output "ansible_inventory" {
  value = module.compute.ansible_inventory
}
