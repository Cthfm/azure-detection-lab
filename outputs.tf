# Variable for Windows VM IP
output "win11_vm_ip_var" {
  value       = azurerm_public_ip.win11_pip.ip_address
  description = "Public IP address of the Windows 11 VM"
}
#Log Analytics Workspace ID
output "log_analytics_workspace_id_var" {
  value       = azurerm_log_analytics_workspace.log_workspace.id
  description = "Log Analytics Workspace ID"
}

#Keyvault Name (KV)
output "keyvault_name" {
  value       = azurerm_key_vault.keyvault.name
  description = "Name of the Key Vault containing the admin password"
}

#Associated URI for KV
output "keyvault_uri" {
  value       = azurerm_key_vault.keyvault.vault_uri
  description = "URI of the Key Vault"
}

output "secret_name" {
  value       = azurerm_key_vault_secret.admin_password.name
  description = "Name of the secret in Key Vault containing the admin password"
}

#Workspace ID
output "log_analytics_workspace_url" {
  value       = "https://portal.azure.com/#@/resource${azurerm_log_analytics_workspace.log_workspace.id}/logs"
  description = "URL to access Log Analytics logs in Azure Portal"
}