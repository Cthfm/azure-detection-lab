terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# This provider block must be OUTSIDE the terraform block
provider "azurerm" {
  features {
    # The features block is required, even if empty
  }
}

# Setup Enviroment as well as random password and random strings for unique storage

# Get Azure Client Info
data "azurerm_client_config" "current" {}

# Generate Random Password
resource "random_password" "vm_password" {
  length           = 16
  special          = true
  override_special = "_%@"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Generate a random string for unique storage account name
resource "random_string" "resource_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
  lower   = true
}


#Setup the foundational resource group and associated resources

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_prefix}-rg-${random_string.resource_suffix.result}"
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_prefix}-vnet-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "${var.resource_prefix}-subnet-${random_string.resource_suffix.result}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "log_workspace" {
  name                = "${var.resource_prefix}-logs-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

#Setup KeyVault and Store Windows Password

# Azure Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                = "${var.resource_prefix}-keyvault-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  # Enable purge protection
  purge_protection_enabled = true
  
  # Set access policies via Azure RBAC
  enable_rbac_authorization = false
}


#Setup Access Policies and password for Windows 11 Machine

# Key Vault Access Policy (only applies to the current user deploying the resources)
resource "azurerm_key_vault_access_policy" "current_user_policy" {
  key_vault_id = azurerm_key_vault.keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "Set", "List", "Delete"]
}

# Store Admin Password in Key Vault
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "win11-admin-password-${random_string.resource_suffix.result}"
  value        = random_password.vm_password.result
  key_vault_id = azurerm_key_vault.keyvault.id
  
  depends_on = [
    azurerm_key_vault_access_policy.current_user_policy
  ]
}

# Network Security Group (NSG) - Allow RDP
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.resource_prefix}-nsg-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow_rdp_from_my_ip"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.user_ip
    destination_address_prefix = "*"
  }
}

# Public IP for Windows 11 VM
resource "azurerm_public_ip" "win11_pip" {
  name                = "${var.resource_prefix}-win11-pip-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

# Network Interface for Windows 11 VM
resource "azurerm_network_interface" "win11_nic" {
  name                = "${var.resource_prefix}-win11-nic-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal-${random_string.resource_suffix.result}"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.win11_pip.id
  }
}

# Associate NSG with Windows 11 Network Interface
resource "azurerm_network_interface_security_group_association" "win11_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.win11_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Windows 11 Virtual Machine
resource "azurerm_windows_virtual_machine" "win11_vm" {
  name                  = "${var.resource_prefix}-win11"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B2s"
  admin_username        = "winadmin"
  admin_password        = random_password.vm_password.result
  network_interface_ids = [azurerm_network_interface.win11_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-22h2-pro"
    version   = "latest"
  }

  enable_automatic_updates = true
  timezone                 = "UTC"
}


#Install Related Monitoring and Logging for Windows VM

# Install Azure Monitor Agent on Windows VM
resource "azurerm_virtual_machine_extension" "ama_extension" {
  name                       = "${var.resource_prefix}-AzureMonitorAgent-${random_string.resource_suffix.result}"
  virtual_machine_id         = azurerm_windows_virtual_machine.win11_vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "workspaceId": "${azurerm_log_analytics_workspace.log_workspace.workspace_id}"
    }
  SETTINGS
}

# Install Sysmon via Custom Script Extension


resource "azurerm_virtual_machine_extension" "sysmon_install" {
  name                 = "SysmonInstall-${random_string.resource_suffix.result}"
  virtual_machine_id   = azurerm_windows_virtual_machine.win11_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  depends_on           = [azurerm_virtual_machine_extension.ama_extension]

  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Unrestricted -Command \"Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile 'C:\\Sysmon.zip'; Expand-Archive -Path 'C:\\Sysmon.zip' -DestinationPath 'C:\\Sysmon'; Invoke-WebRequest -Uri '${var.sysmon_config_url}' -OutFile 'C:\\Sysmon\\sysmonconfig.xml'; C:\\Sysmon\\Sysmon64.exe -accepteula -i C:\\Sysmon\\sysmonconfig.xml\""
    }
  SETTINGS

  timeouts {
    create = "30m"
  }
}

# Set Up Data Collection Rule for Windows VM and Sysmon

resource "azurerm_monitor_data_collection_rule" "windows_dcr" {
  name                = "${var.resource_prefix}-windows-dcr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Windows"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.log_workspace.id
      name                  = "loganalytics"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event", "Microsoft-Perf"]
    destinations = ["loganalytics"]
  }

  # Single data_sources block containing both configurations
  data_sources {
    # Windows Event Log configuration
    windows_event_log {
      streams = ["Microsoft-Event"]
      name    = "windows_event_logs"
      x_path_queries = var.event_logs_to_collect
    }
    
    # Performance Counter configuration
    performance_counter {
      streams                     = ["Microsoft-Perf"]
      name                        = "windows_perf_counters"
      counter_specifiers          = var.performance_counters
      sampling_frequency_in_seconds = 15
    }
  }

  depends_on = [
    azurerm_log_analytics_workspace.log_workspace,
    azurerm_virtual_machine_extension.sysmon_install
  ]
}
# Associate DCR with Windows 11 VM
resource "azurerm_monitor_data_collection_rule_association" "dcr_association" {
  name                    = "${var.resource_prefix}-dcr-association-${random_string.resource_suffix.result}"
  target_resource_id      = azurerm_windows_virtual_machine.win11_vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows_dcr.id
  
  depends_on = [
    azurerm_virtual_machine_extension.ama_extension,
    azurerm_virtual_machine_extension.sysmon_install,
    azurerm_monitor_data_collection_rule.windows_dcr
  ]
}

#Generate other logs for Network Watcher and Key Vault

# Network Watcher for flow logs
resource "azurerm_network_watcher" "sec_lab_watcher" {
  name                = "sec-lab-network-watcher-${random_string.resource_suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Storage Account for Network Flow Logs
resource "azurerm_storage_account" "flow_logs_storage" {
  name                     = "${replace(var.resource_prefix, "-", "")}flowlogs${random_string.resource_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    delete_retention_policy {
      days = 30
    }
  }
  tags = {
    purpose = "NetworkFlowLogs"
  }
}

# Network Watcher Flow Logs Configuration
resource "azurerm_network_watcher_flow_log" "nsg_flow_logs" {
  name                 = "${var.resource_prefix}-nsg-flowlog-${random_string.resource_suffix.result}"
  network_watcher_name = azurerm_network_watcher.sec_lab_watcher.name
  resource_group_name  = azurerm_resource_group.rg.name
  
  network_security_group_id = azurerm_network_security_group.nsg.id
  storage_account_id        = azurerm_storage_account.flow_logs_storage.id
  enabled                   = true
  
  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.log_workspace.workspace_id
    workspace_region      = azurerm_resource_group.rg.location
    workspace_resource_id = azurerm_log_analytics_workspace.log_workspace.id
    interval_in_minutes   = 10
  }
}

# Create diagnostic settings for Key Vault
resource "azurerm_monitor_diagnostic_setting" "keyvault_diagnostics" {
  name                       = "${var.resource_prefix}-keyvault-diag-${random_string.resource_suffix.result}"
  target_resource_id         = azurerm_key_vault.keyvault.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_workspace.id

  # Enable Key Vault audit logs
  enabled_log {
    category = "AuditEvent"
  }

  # Enable Key Vault metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}