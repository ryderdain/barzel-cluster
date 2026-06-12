#cloud-config
# Minimal bootstrap only. k3s install and all node configuration are Ansible's
# job (repo delegation rule: Terraform provisions, Ansible configures). We just
# set a predictable hostname and make sure Python is present for Ansible.
hostname: ${node_name}
preserve_hostname: false
package_update: true
packages:
  - python3
