#Where you want the resources deployed. 

variable "location" {
  type        = string
  description = "Enter the Azure region for deployment (e.g., East US, West US, Central US)."
}

#Prefix to associate all resources with the lab

variable "resource_prefix" {
  type        = string
  default     = "sec-lab4"
  description = "Prefix for all resources in Azure."
}

#Confirm your associated external IP. This can be done in the azure portal under security groups.
variable "user_ip" {
  type        = string
  description = "Enter your public IP address (used for NSG RDP access)."
}

variable "environment" {
  type        = string
  default     = "Dev-Detection-Lab"
  description = "Environment name (dev, test, prod)"
}

# Variables for VM Monitoring

variable "sysmon_config_url" {
  type        = string
  default     = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"
  description = "URL to the Sysmon configuration XML file"
}

variable "event_logs_to_collect" {
  description = "List of Windows event log XPath queries to collect"
  type        = list(string)
  default     = [
    "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
    "Security!*[System[(band(Keywords,13510798882111488))]]",
    "System!*[System[(Level=1 or Level=2 or Level=3)]]",
    "Microsoft-Windows-Sysmon/Operational!*"
  ]
}

variable "performance_counters" {
  description = "List of Windows performance counters to collect"
  type        = list(string)
  default     = [
    "\\Processor Information(_Total)\\% Processor Time",
    "\\Memory\\Available Bytes",
    "\\LogicalDisk(_Total)\\Free Megabytes"
  ]
}