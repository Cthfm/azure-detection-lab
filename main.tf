resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  
  tags = {
    Environment = var.environment
    Purpose     = "Security Testing"
  }
}

module "network" {
  source              = "./modules/network"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  environment         = var.environment
}

module "compute" {
  source              = "./modules/compute"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = module.network.workload_subnet_id
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  ssh_public_key_path = var.ssh_public_key_path
  environment         = var.environment
  depends_on          = [module.network]
}

module "monitoring" {
  source                    = "./modules/monitoring"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  environment               = var.environment
  windows_vm_id            = module.compute.windows_vm_id
  kali_vm_id              = module.compute.kali_vm_id
  depends_on               = [module.compute]
}

module "security" {
  source                    = "./modules/security"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  environment               = var.environment
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  depends_on                = [module.monitoring]
}
