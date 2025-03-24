# PowerShell script to set up Azure Storage for Terraform state


# Function to check if user is logged into Azure
function Test-AzureLoggedIn {
  try {
      $context = Get-AzContext
      if ($null -eq $context.Account) {
          return $false
      }
      return $true
  }
  catch {
      return $false
  }
}

# Function to set Azure subscription from current session
function Set-AzureSubscription {
  try {
      # Get current Azure context
      $currentContext = Get-AzContext
      
      if ($null -eq $currentContext -or $null -eq $currentContext.Subscription) {
          Write-Host "No active Azure subscription found. Please log in to Azure first." -ForegroundColor Red
          exit 1
      }
      
      # Get subscription ID from active session
      $SubscriptionId = $currentContext.Subscription.Id
      $SubscriptionName = $currentContext.Subscription.Name
      
      # Set the environment variable for Terraform
      $env:ARM_SUBSCRIPTION_ID = $SubscriptionId
      
      Write-Host "Using active subscription: $SubscriptionName ($SubscriptionId)" -ForegroundColor Green
      Write-Host "Environment variable ARM_SUBSCRIPTION_ID has been set." -ForegroundColor Green
  }
  catch {
      Write-Host "Failed to get or set subscription. Error: $_" -ForegroundColor Red
      exit 1
  }
}

# Function to prompt user to select an Azure region
function Select-AzureRegion {
  # Define commonly used Azure regions with their display names
  $regions = @(
      @{Name = "eastus"; DisplayName = "East US"},
      @{Name = "eastus2"; DisplayName = "East US 2"},
      @{Name = "westus"; DisplayName = "West US"},
      @{Name = "westus2"; DisplayName = "West US 2"},
      @{Name = "westus3"; DisplayName = "West US 3"},
      @{Name = "centralus"; DisplayName = "Central US"},
      @{Name = "northcentralus"; DisplayName = "North Central US"},
      @{Name = "southcentralus"; DisplayName = "South Central US"},
      @{Name = "westcentralus"; DisplayName = "West Central US"},
      @{Name = "canadacentral"; DisplayName = "Canada Central"},
      @{Name = "canadaeast"; DisplayName = "Canada East"},
      @{Name = "northeurope"; DisplayName = "North Europe"},
      @{Name = "westeurope"; DisplayName = "West Europe"},
      @{Name = "uksouth"; DisplayName = "UK South"},
      @{Name = "ukwest"; DisplayName = "UK West"},
      @{Name = "francecentral"; DisplayName = "France Central"},
      @{Name = "australiaeast"; DisplayName = "Australia East"},
      @{Name = "australiasoutheast"; DisplayName = "Australia Southeast"},
      @{Name = "japaneast"; DisplayName = "Japan East"},
      @{Name = "japanwest"; DisplayName = "Japan West"},
      @{Name = "brazilsouth"; DisplayName = "Brazil South"},
      @{Name = "southeastasia"; DisplayName = "Southeast Asia"},
      @{Name = "eastasia"; DisplayName = "East Asia"}
  )

  # Display available regions with numbers
  Write-Host "Available Azure Regions:" -ForegroundColor Cyan
  for ($i = 0; $i -lt $regions.Count; $i++) {
      Write-Host "[$($i+1)] $($regions[$i].DisplayName) ($($regions[$i].Name))" -ForegroundColor White
  }

  # Prompt user to select a region
  $defaultRegion = 1  # East US as default
  $selection = Read-Host "Enter the number for your preferred region [Default: $($regions[$defaultRegion-1].DisplayName)]"
  
  # Use default if nothing entered
  if ([string]::IsNullOrWhiteSpace($selection)) {
      $selection = $defaultRegion
  }
  
  # Validate selection
  try {
      $selectionNum = [int]$selection
      if ($selectionNum -lt 1 -or $selectionNum -gt $regions.Count) {
          Write-Host "Invalid selection. Using default: $($regions[$defaultRegion-1].DisplayName)" -ForegroundColor Yellow
          return $regions[$defaultRegion-1].Name
      }
      
      Write-Host "Selected region: $($regions[$selectionNum-1].DisplayName)" -ForegroundColor Green
      return $regions[$selectionNum-1].Name
  }
  catch {
      Write-Host "Invalid input. Using default: $($regions[$defaultRegion-1].DisplayName)" -ForegroundColor Yellow
      return $regions[$defaultRegion-1].Name
  }
}

# Check if logged into Azure
if (-not (Test-AzureLoggedIn)) {
  Write-Host "You are not logged into Azure." -ForegroundColor Yellow
  $login = Read-Host "Would you like to log in now? (Y/N)"
  
  if ($login -eq "Y" -or $login -eq "y") {
      try {
          Connect-AzAccount
          # Verify login was successful
          if (-not (Test-AzureLoggedIn)) {
              Write-Host "Login failed or was cancelled." -ForegroundColor Red
              exit 1
          }
      }
      catch {
          Write-Host "Failed to log in to Azure. Error: $_" -ForegroundColor Red
          exit 1
      }
  }
  else {
      Write-Host "This script requires an active Azure login. Please log in and try again." -ForegroundColor Yellow
      exit 1
  }
}

# Set Azure subscription from current session
Set-AzureSubscription

# Set variables
$RESOURCE_GROUP_NAME = "terraform-state-rg-test"
$STORAGE_ACCOUNT_NAME = "tfstateseclab" + (Get-Random -Minimum 1000 -Maximum 9999)  # Add random digits to ensure uniqueness
$CONTAINER_NAME = "tfstate"

# Prompt user to select a region
$LOCATION = Select-AzureRegion

# Create resource group
Write-Host "Creating resource group: $RESOURCE_GROUP_NAME" -ForegroundColor Cyan
try {
  New-AzResourceGroup -Name $RESOURCE_GROUP_NAME -Location $LOCATION -Force -ErrorAction Stop
}
catch {
  Write-Host "Failed to create resource group. Error: $_" -ForegroundColor Red
  exit 1
}

# Create storage account
Write-Host "Creating storage account: $STORAGE_ACCOUNT_NAME" -ForegroundColor Cyan
try {
  $storageAccount = New-AzStorageAccount `
      -ResourceGroupName $RESOURCE_GROUP_NAME `
      -Name $STORAGE_ACCOUNT_NAME `
      -Location $LOCATION `
      -SkuName "Standard_LRS" `
      -Kind "StorageV2" `
      -EnableHttpsTrafficOnly $true `
      -MinimumTlsVersion "TLS1_2" `
      -AllowBlobPublicAccess $false `
      -ErrorAction Stop
}
catch {
  Write-Host "Failed to create storage account. Error: $_" -ForegroundColor Red
  
  # Check for common errors
  if ($_.Exception.Message -like "*StorageAccountAlreadyExists*") {
      Write-Host "A storage account with this name already exists. Please try running the script again for a different random name." -ForegroundColor Yellow
  }
  
  exit 1
}

# Get storage account key
try {
  $ACCOUNT_KEY = (Get-AzStorageAccountKey -ResourceGroupName $RESOURCE_GROUP_NAME -Name $STORAGE_ACCOUNT_NAME -ErrorAction Stop)[0].Value
  
  # Automatically set the environment variable
  $env:ARM_ACCESS_KEY = $ACCOUNT_KEY
  
  # Save the key to a file for reference
  $keyFile = Join-Path $env:USERPROFILE "terraform_access_key.txt"
  Set-Content -Path $keyFile -Value $ACCOUNT_KEY -Encoding ASCII -Force
  
  # Verify the variable was set properly
  if ($null -eq $env:ARM_ACCESS_KEY) {
      Write-Host "WARNING: Failed to set ARM_ACCESS_KEY environment variable." -ForegroundColor Red
  } else {
      Write-Host "Successfully set ARM_ACCESS_KEY environment variable." -ForegroundColor Green
      Write-Host "Key length: $($env:ARM_ACCESS_KEY.Length) characters" -ForegroundColor Green
      Write-Host "Key has been saved to: $keyFile" -ForegroundColor Green
  }
}
catch {
  Write-Host "Failed to retrieve storage account key. Error: $_" -ForegroundColor Red
  exit 1
}

# Create storage context
try {
  $ctx = New-AzStorageContext -StorageAccountName $STORAGE_ACCOUNT_NAME -StorageAccountKey $ACCOUNT_KEY -ErrorAction Stop
}
catch {
  Write-Host "Failed to create storage context. Error: $_" -ForegroundColor Red
  exit 1
}

# Create blob container
Write-Host "Creating blob container: $CONTAINER_NAME" -ForegroundColor Cyan
try {
  New-AzStorageContainer -Name $CONTAINER_NAME -Context $ctx -Permission Off -ErrorAction Stop
}
catch {
  Write-Host "Failed to create blob container. Error: $_" -ForegroundColor Red
  exit 1
}

# Output the configuration
Write-Host "`nConfiguration completed successfully!" -ForegroundColor Green

# Create terraform backend configuration file using ASCII encoding
$backendFile = "backend.tf"
Set-Content -Path $backendFile -Value "terraform {" -Encoding ASCII
Add-Content -Path $backendFile -Value "  backend `"azurerm`" {" -Encoding ASCII
Add-Content -Path $backendFile -Value "    resource_group_name  = `"$RESOURCE_GROUP_NAME`"" -Encoding ASCII
Add-Content -Path $backendFile -Value "    storage_account_name = `"$STORAGE_ACCOUNT_NAME`"" -Encoding ASCII
Add-Content -Path $backendFile -Value "    container_name       = `"$CONTAINER_NAME`"" -Encoding ASCII
Add-Content -Path $backendFile -Value "    key                  = `"win11-lab.terraform.tfstate`"" -Encoding ASCII
Add-Content -Path $backendFile -Value "    subscription_id      = `"$($env:ARM_SUBSCRIPTION_ID)`"" -Encoding ASCII
Add-Content -Path $backendFile -Value "  }" -Encoding ASCII
Add-Content -Path $backendFile -Value "}" -Encoding ASCII

Write-Host "`nCreated backend configuration file: $backendFile" -ForegroundColor Cyan

# Create a setup script for future sessions with ASCII encoding
$setupFile = "set-terraform-env.ps1"
Set-Content -Path $setupFile -Value "# Run this script to set up the environment variables for Terraform" -Encoding ASCII
Add-Content -Path $setupFile -Value "`$env:ARM_ACCESS_KEY = `"$ACCOUNT_KEY`"" -Encoding ASCII
Add-Content -Path $setupFile -Value "`$env:ARM_SUBSCRIPTION_ID = `"$($env:ARM_SUBSCRIPTION_ID)`"" -Encoding ASCII
Add-Content -Path $setupFile -Value "Write-Host `"Environment variables ARM_ACCESS_KEY and ARM_SUBSCRIPTION_ID have been set.`"" -Encoding ASCII
Add-Content -Path $setupFile -Value "Write-Host `"You can now run: terraform init -reconfigure`"" -Encoding ASCII

Write-Host "Created environment setup script: $setupFile" -ForegroundColor Cyan

# Output instructions for updating main.tf
Write-Host "`n=== TERRAFORM CONFIGURATION INSTRUCTIONS ===" -ForegroundColor Yellow
Write-Host "`nOption 1: Use Separate Backend File (Recommended)" -ForegroundColor Green
Write-Host "1. The backend configuration is already created in: $backendFile" -ForegroundColor White

# Output general Terraform instructions
Write-Host "`n=== NEXT STEPS ===" -ForegroundColor Yellow
Write-Host "1. The ARM_ACCESS_KEY and ARM_SUBSCRIPTION_ID environment variables have been set for this session." -ForegroundColor White
Write-Host "2. Run 'terraform init -reconfigure' to initialize Terraform with the Azure backend." -ForegroundColor White
Write-Host "3. For future PowerShell sessions, run: .\$setupFile" -ForegroundColor White

Write-Host "`n=== STORAGE ACCOUNT INFORMATION ===" -ForegroundColor Yellow
Write-Host "Name: $STORAGE_ACCOUNT_NAME" -ForegroundColor White
Write-Host "Resource Group: $RESOURCE_GROUP_NAME" -ForegroundColor White
Write-Host "Container: $CONTAINER_NAME" -ForegroundColor White
Write-Host "Location: $LOCATION" -ForegroundColor White
Write-Host "Subscription: $($env:ARM_SUBSCRIPTION_ID)" -ForegroundColor White
Write-Host "Access Key Location: $keyFile" -ForegroundColor White