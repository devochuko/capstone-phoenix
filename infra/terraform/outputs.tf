output "control_plane_public_ip" {
  description = "SSH/kubectl entry point for the control-plane node."
  value       = module.compute.control_plane_public_ip
}

output "control_plane_private_ip" {
  description = "Used by workers to join the cluster (k3s server URL)."
  value       = module.compute.control_plane_private_ip
}

output "worker_public_ips" {
  description = "SSH entry points for worker nodes (Ansible target list)."
  value       = module.compute.worker_public_ips
}

output "worker_private_ips" {
  value = module.compute.worker_private_ips
}

output "ansible_inventory_hint" {
  description = "Paste-able snippet for infra/ansible/inventory/hosts.ini"
  value       = <<-EOT
    [control_plane]
    ${module.compute.control_plane_public_ip} private_ip=${module.compute.control_plane_private_ip}

    [workers]
    ${join("\n", [for i, ip in module.compute.worker_public_ips : "${ip} private_ip=${module.compute.worker_private_ips[i]}"])}
  EOT
}
