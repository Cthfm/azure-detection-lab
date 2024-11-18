# Azure Detection Lab 🧪

This repository contains Terraform configurations for setting up a security detection lab in Azure.

## Prerequisites

- Azure Subscription
- Terraform installed (v1.0.0+)
- Azure CLI installed and configured
- Git installed

## Setup Instructions

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/azure-detection-lab.git
   cd azure-detection-lab

2. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Update terraform.tfvars with your values:
   ```hcl
   windows_admin_password = "YourSecurePassword123!"
   my_ip_address = "YOUR.PUBLIC.IP.ADDRESS"
   ```

4. Initialize Terraform:
   ```bash
   terraform init
   ```

5. Plan and apply:
   ```bash
   terraform plan
   terraform apply
   ```

## Features

- Kali Linux VM for testing
- Windows Desktop VM
- Azure Bastion (Developer SKU)
- Microsoft Sentinel
- Log Analytics Workspace
- Comprehensive logging
- Network security groups
- Key Vault integration

## Security Notes

- Remember to update the NSG rules with your IP address
- Change default passwords
- Enable just-in-time VM access in production

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request
```

### 3. terraform.tfvars.example
```hcl
windows_admin_password = "ChangeMe123!"
my_ip_address = "0.0.0.0"
```
