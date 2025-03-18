# PowerShell script to set up Azure Storage for Terraform state
# With improved error checking and proper file encoding for Terraform compatibility

# Function to check if required modules are installed
function Test-ModuleInstalled {
    param (
        [string]$ModuleName
    )
    
    if (Get-Module -ListAvailable -Name $ModuleName) {
        return $true
    }
    return $false
  }
  
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
  
  # Check if Az modules are installed
  if (-not (Test-ModuleInstalled -ModuleName "Az")) {
    Write-Host "Azure PowerShell modules are not installed." -ForegroundColor Red
    $installModules = Read-Host "Would you like to install them now? (Y/N)"
    
    if ($installModules -eq "Y" -or $installModules -eq "y") {
        Write-Host "Installing Az modules (this may take a few minutes)..." -ForegroundColor Yellow
        try {
            Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
            Write-Host "Az modules installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install Az modules. Error: $_" -ForegroundColor Red
            Write-Host "Please install the Az modules manually using: Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force" -ForegroundColor Yellow
            exit 1
        }
    }
    else {
        Write-Host "This script requires the Az modules. Please install them and try again." -ForegroundColor Yellow
        Write-Host "You can install them using: Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force" -ForegroundColor Yellow
        exit 1
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
  $RESOURCE_GROUP_NAME = "terraform-state-rg"
  $STORAGE_ACCOUNT_NAME = "tfstateseclab" + (Get-Random -Minimum 1000 -Maximum 9999)  # Add random digits to ensure uniqueness
  $CONTAINER_NAME = "tfstate"
  $LOCATION = "eastus"  # Change to your preferred region
  
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
  Write-Host "Subscription: $($env:ARM_SUBSCRIPTION_ID)" -ForegroundColor White
  Write-Host "Access Key Location: $keyFile" -ForegroundColor White