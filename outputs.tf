output "kali_public_ip" {
  value       = module.compute.kali_public_ip
  description = "The public IP address of the Kali Linux VM"
}

output "windows_public_ip" {
  value       = module.compute.windows_public_ip
  description = "The public IP address of the Windows VM"
}

output "log_analytics_workspace_id" {
  value       = module.monitoring.log_analytics_workspace_id
  description = "The ID of the Log Analytics Workspace"
}
