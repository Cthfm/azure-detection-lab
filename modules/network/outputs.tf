output "workload_subnet_id" {
  value = azurerm_subnet.workload_subnet.id
}

output "monitoring_subnet_id" {
  value = azurerm_subnet.monitoring_subnet.id
}

output "nsg_id" {
  value = azurerm_network_security_group.nsg.id
}