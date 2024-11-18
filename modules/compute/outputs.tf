# modules/compute/outputs.tf
output "kali_public_ip" {
  value = azurerm_public_ip.kali_pip.ip_address
}

output "windows_public_ip" {
  value = azurerm_public_ip.windows_pip.ip_address
}

output "windows_vm_id" {
  value = azurerm_windows_virtual_machine.windows.id
}

output "kali_vm_id" {
  value = azurerm_linux_virtual_machine.kali.id
}
Last edited 33 minutes a