variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "windows_vm_id" {
  description = "Windows VM ID"
  type        = string
}

variable "kali_vm_id" {
  description = "Kali VM ID"
  type        = string
}