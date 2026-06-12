output "instance_ids" {
  value = module.compute.instance_ids
}

output "private_ips" {
  value = module.compute.private_ips
}

output "public_ips" {
  value = module.compute.public_ips
}

# Consumed by the Ansible inventory generator (Tue Jun 2 block).
output "ansible_inventory" {
  value = module.compute.ansible_inventory
}
