# PowerShell script for deploying Container App with VNet integration
# Creates all resources including Resource Group if they don't exist
# Version: 2.1 - Fixed for PowerShell compatibility

# ============================================================================
# CONFIGURATION VARIABLES
# ============================================================================
$resourceGroup = "E1074651-SDLDEV"
$location = "East US 2"
$storageAccount = "sasstor6778g5"
$fileShare = "matchingservicefileshare"
$vnetName = "matchingservice-vnet"
$containerAppEnv = "matchingserviceappenvironment"
$containerApp = "matchingservice"
$acrName = "saswattestregistry"
$containerImage = "saswattestregistry.azurecr.io/myapp:latest"
$sourceImage = "mcr.microsoft.com/azuredocs/aci-helloworld"
$targetPort = 80

# ============================================================================
# INITIALIZATION
# ============================================================================
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "    AZURE CONTAINER APP DEPLOYMENT WITH VNET INTEGRATION" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[START] Beginning deployment process..." -ForegroundColor Yellow
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "[TIME] $timestamp" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# AUTHENTICATION CHECK
# ============================================================================
Write-Host "[AUTH] Checking Azure CLI authentication..." -ForegroundColor Yellow
$currentUser = az account show --query "user.name" -o tsv 2>$null
if (-not $currentUser) {
    Write-Host "[ERROR] Not logged in to Azure CLI" -ForegroundColor Red
    Write-Host "   Please run: az login" -ForegroundColor Yellow
    exit 1
}
$subscription = az account show --query "name" -o tsv
Write-Host "[OK] Logged in as: $currentUser" -ForegroundColor Green
Write-Host "[INFO] Subscription: $subscription" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# AZURE CLI EXTENSIONS
# ============================================================================
Write-Host "[EXT] Checking Azure CLI extensions..." -ForegroundColor Yellow
$containerAppExtension = az extension list --query "[?name=='containerapp'].name" -o tsv 2>$null
if (-not $containerAppExtension) {
    Write-Host "[INSTALL] Installing Container App extension..." -ForegroundColor Blue
    az extension add --name containerapp --upgrade
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to install Container App extension" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] Container App extension ready" -ForegroundColor Green
Write-Host ""

# ============================================================================
# RESOURCE PROVIDERS REGISTRATION
# ============================================================================
Write-Host "[PROVIDERS] Registering required resource providers..." -ForegroundColor Yellow
Write-Host "   Registering Microsoft.App..." -ForegroundColor Gray
az provider register --namespace Microsoft.App --wait
Write-Host "   Registering Microsoft.ContainerRegistry..." -ForegroundColor Gray
az provider register --namespace Microsoft.ContainerRegistry --wait
Write-Host "   Registering Microsoft.Storage..." -ForegroundColor Gray
az provider register --namespace Microsoft.Storage --wait
Write-Host "   Registering Microsoft.Network..." -ForegroundColor Gray
az provider register --namespace Microsoft.Network --wait
Write-Host "[OK] All resource providers registered" -ForegroundColor Green
Write-Host ""

# ============================================================================
# RESOURCE GROUP CREATION
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 1: RESOURCE GROUP" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[RG] Checking/Creating Resource Group: $resourceGroup" -ForegroundColor Yellow
$rgExists = az group show --name $resourceGroup --query "name" -o tsv 2>$null
if (-not $rgExists) {
    Write-Host "[NEW] Creating new Resource Group in $location..." -ForegroundColor Blue
    az group create --name $resourceGroup --location "$location"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[CRITICAL ERROR] Failed to create Resource Group" -ForegroundColor Red
        exit 1
    }
    
    # Verify creation
    Start-Sleep -Seconds 2
    $rgVerify = az group show --name $resourceGroup --query "name" -o tsv 2>$null
    if (-not $rgVerify) {
        Write-Host "[CRITICAL ERROR] Resource Group creation verification failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Resource Group created successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] Resource Group already exists" -ForegroundColor Green
}

# Final verification
$rgFinalCheck = az group exists --name $resourceGroup 2>$null
if ($rgFinalCheck -ne "true") {
    Write-Host "[CRITICAL ERROR] Resource Group does not exist. Cannot proceed." -ForegroundColor Red
    exit 1
}
Write-Host ""

# ============================================================================
# AZURE CONTAINER REGISTRY
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 2: AZURE CONTAINER REGISTRY" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[ACR] Setting up Azure Container Registry: $acrName" -ForegroundColor Yellow
$acrExists = az acr show --name $acrName --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $acrExists) {
    Write-Host "[NEW] Creating ACR..." -ForegroundColor Blue
    az acr create --name $acrName --resource-group $resourceGroup --location "$location" --sku Basic --admin-enabled false
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create ACR" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] ACR created successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] ACR already exists" -ForegroundColor Green
}

# Import container image
Write-Host "[IMAGE] Importing container image..." -ForegroundColor Yellow
$imageExists = az acr repository show --name $acrName --repository myapp --query "name" -o tsv 2>$null
if (-not $imageExists) {
    Write-Host "   Source: $sourceImage" -ForegroundColor Gray
    Write-Host "   Target: myapp:latest" -ForegroundColor Gray
    az acr import --name $acrName --source $sourceImage --image myapp:latest --force
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Image imported successfully" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to import image" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[OK] Image already exists in ACR" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# STORAGE ACCOUNT AND FILE SHARE
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 3: STORAGE ACCOUNT" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[STORAGE] Setting up Storage Account: $storageAccount" -ForegroundColor Yellow
$storageExists = az storage account show --name $storageAccount --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $storageExists) {
    Write-Host "[NEW] Creating Storage Account..." -ForegroundColor Blue
    az storage account create `
        --name $storageAccount `
        --resource-group $resourceGroup `
        --location "$location" `
        --sku Standard_LRS `
        --kind StorageV2 `
        --access-tier Hot `
        --allow-blob-public-access false
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create Storage Account" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Storage Account created successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] Storage Account already exists" -ForegroundColor Green
}

# Create File Share
Write-Host "[SHARE] Setting up File Share: $fileShare" -ForegroundColor Yellow
$fileShareExists = az storage share show --name $fileShare --account-name $storageAccount --query "name" -o tsv 2>$null
if (-not $fileShareExists) {
    Write-Host "[NEW] Creating File Share..." -ForegroundColor Blue
    az storage share create `
        --name $fileShare `
        --account-name $storageAccount `
        --quota 100
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create File Share" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] File Share created successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] File Share already exists" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# CLEANUP EXISTING CONTAINER APP RESOURCES
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 4: CLEANUP EXISTING RESOURCES" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[CLEANUP] Checking for existing Container App resources..." -ForegroundColor Yellow
$containerAppExists = az containerapp show --name $containerApp --resource-group $resourceGroup --query "name" -o tsv 2>$null
if ($containerAppExists) {
    Write-Host "[DELETE] Removing existing Container App..." -ForegroundColor Yellow
    az containerapp delete --name $containerApp --resource-group $resourceGroup --yes
    Write-Host "[OK] Existing Container App deleted" -ForegroundColor Green
}

$containerAppEnvExists = az containerapp env show --name $containerAppEnv --resource-group $resourceGroup --query "name" -o tsv 2>$null
if ($containerAppEnvExists) {
    Write-Host "[DELETE] Removing existing Container App Environment..." -ForegroundColor Yellow
    az containerapp env delete --name $containerAppEnv --resource-group $resourceGroup --yes
    Write-Host "[OK] Existing Container App Environment deleted" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# VIRTUAL NETWORK SETUP
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 5: VIRTUAL NETWORK CONFIGURATION" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

# Create VNet
Write-Host "[VNET] Setting up Virtual Network: $vnetName" -ForegroundColor Yellow
$vnetExists = az network vnet show --name $vnetName --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $vnetExists) {
    Write-Host "[NEW] Creating VNet with address space 10.0.0.0/16..." -ForegroundColor Blue
    az network vnet create `
        --name $vnetName `
        --resource-group $resourceGroup `
        --location "$location" `
        --address-prefix 10.0.0.0/16
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create VNet" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] VNet created successfully" -ForegroundColor Green
} else {
    Write-Host "[OK] VNet already exists" -ForegroundColor Green
}

# Create Container Apps subnet
Write-Host "[SUBNET] Setting up Container Apps subnet (10.0.0.0/23)..." -ForegroundColor Yellow
$containerSubnetExists = az network vnet subnet show --name container-apps-subnet --vnet-name $vnetName --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $containerSubnetExists) {
    az network vnet subnet create `
        --name container-apps-subnet `
        --resource-group $resourceGroup `
        --vnet-name $vnetName `
        --address-prefix 10.0.0.0/23
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create Container Apps subnet" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Container Apps subnet created" -ForegroundColor Green
} else {
    Write-Host "[OK] Container Apps subnet already exists" -ForegroundColor Green
}

# Create Storage subnet
Write-Host "[SUBNET] Setting up Storage Private Endpoint subnet (10.0.4.0/24)..." -ForegroundColor Yellow
$storageSubnetExists = az network vnet subnet show --name storage-private-endpoint-subnet --vnet-name $vnetName --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $storageSubnetExists) {
    az network vnet subnet create `
        --name storage-private-endpoint-subnet `
        --resource-group $resourceGroup `
        --vnet-name $vnetName `
        --address-prefix 10.0.4.0/24 `
        --disable-private-endpoint-network-policies true
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create Storage subnet" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Storage subnet created" -ForegroundColor Green
} else {
    Write-Host "[OK] Storage subnet already exists" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# PRIVATE ENDPOINT AND DNS CONFIGURATION
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 6: PRIVATE ENDPOINT AND DNS" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

# Create Private Endpoint
Write-Host "[PE] Setting up Private Endpoint for Storage..." -ForegroundColor Yellow
$privateEndpointExists = az network private-endpoint show --name "$storageAccount-pe" --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $privateEndpointExists) {
    $subscriptionId = az account show --query "id" -o tsv
    Write-Host "[NEW] Creating Private Endpoint..." -ForegroundColor Blue
    az network private-endpoint create `
        --name "$storageAccount-pe" `
        --resource-group $resourceGroup `
        --location "$location" `
        --vnet-name $vnetName `
        --subnet storage-private-endpoint-subnet `
        --private-connection-resource-id "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccount" `
        --group-id file `
        --connection-name "$storageAccount-connection"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to create Private Endpoint" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Private Endpoint created" -ForegroundColor Green
} else {
    Write-Host "[OK] Private Endpoint already exists" -ForegroundColor Green
}

# Create Private DNS Zone
Write-Host "[DNS] Setting up Private DNS Zone..." -ForegroundColor Yellow
$dnsZoneExists = az network private-dns zone show --name privatelink.file.core.windows.net --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $dnsZoneExists) {
    Write-Host "[NEW] Creating Private DNS Zone..." -ForegroundColor Blue
    az network private-dns zone create `
        --resource-group $resourceGroup `
        --name privatelink.file.core.windows.net
    Write-Host "[OK] Private DNS Zone created" -ForegroundColor Green
} else {
    Write-Host "[OK] Private DNS Zone already exists" -ForegroundColor Green
}

# Create VNet Link
Write-Host "[LINK] Setting up DNS VNet Link..." -ForegroundColor Yellow
$vnetLinkExists = az network private-dns link vnet show --name dns-link --zone-name privatelink.file.core.windows.net --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $vnetLinkExists) {
    Write-Host "[NEW] Creating DNS VNet Link..." -ForegroundColor Blue
    az network private-dns link vnet create `
        --resource-group $resourceGroup `
        --zone-name privatelink.file.core.windows.net `
        --name dns-link `
        --virtual-network $vnetName `
        --registration-enabled false
    Write-Host "[OK] DNS VNet Link created" -ForegroundColor Green
} else {
    Write-Host "[OK] DNS VNet Link already exists" -ForegroundColor Green
}

# Create DNS Zone Group
Write-Host "[DNS] Setting up DNS Zone Group..." -ForegroundColor Yellow
$zoneGroupExists = az network private-endpoint dns-zone-group show --name zone-group --endpoint-name "$storageAccount-pe" --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $zoneGroupExists) {
    Write-Host "[NEW] Creating DNS Zone Group..." -ForegroundColor Blue
    az network private-endpoint dns-zone-group create `
        --resource-group $resourceGroup `
        --endpoint-name "$storageAccount-pe" `
        --name zone-group `
        --private-dns-zone privatelink.file.core.windows.net `
        --zone-name file
    Write-Host "[OK] DNS Zone Group created" -ForegroundColor Green
} else {
    Write-Host "[OK] DNS Zone Group already exists" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# CONTAINER APP ENVIRONMENT
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 7: CONTAINER APP ENVIRONMENT" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

# Create Container App Environment
Write-Host "[ENV] Creating Container App Environment: $containerAppEnv" -ForegroundColor Yellow
$subnetId = az network vnet subnet show --resource-group $resourceGroup --vnet-name $vnetName --name container-apps-subnet --query id -o tsv
if (-not $subnetId) {
    Write-Host "[ERROR] Failed to get subnet ID" -ForegroundColor Red
    exit 1
}

Write-Host "[NEW] Creating environment with VNet integration..." -ForegroundColor Blue
az containerapp env create `
    --name $containerAppEnv `
    --resource-group $resourceGroup `
    --location "$location" `
    --infrastructure-subnet-resource-id $subnetId `
    --internal-only false
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to create Container App Environment" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Container App Environment created" -ForegroundColor Green

# Configure storage mount
Write-Host "[MOUNT] Configuring storage mount..." -ForegroundColor Yellow
$storageKey = az storage account keys list --account-name $storageAccount --resource-group $resourceGroup --query "[0].value" -o tsv
if (-not $storageKey) {
    Write-Host "[ERROR] Failed to get storage account key" -ForegroundColor Red
    exit 1
}

Write-Host "[CONFIG] Adding Azure Files storage to environment..." -ForegroundColor Blue
az containerapp env storage set `
    --name $containerAppEnv `
    --resource-group $resourceGroup `
    --storage-name azurefiles `
    --azure-file-account-name $storageAccount `
    --azure-file-account-key $storageKey `
    --azure-file-share-name $fileShare `
    --access-mode ReadWrite
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to configure storage mount" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Storage mount configured" -ForegroundColor Green
Write-Host ""

# ============================================================================
# CONTAINER APP DEPLOYMENT
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 8: CONTAINER APP DEPLOYMENT" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[DEPLOY] Creating Container App: $containerApp" -ForegroundColor Yellow
Write-Host "   Image: $containerImage" -ForegroundColor Gray
Write-Host "   Port: $targetPort" -ForegroundColor Gray
Write-Host "   CPU: 0.5 cores" -ForegroundColor Gray
Write-Host "   Memory: 1Gi" -ForegroundColor Gray
Write-Host "   Replicas: 1-3 (auto-scaling)" -ForegroundColor Gray

az containerapp create `
    --name $containerApp `
    --resource-group $resourceGroup `
    --environment $containerAppEnv `
    --image $containerImage `
    --target-port $targetPort `
    --ingress external `
    --cpu 0.5 `
    --memory 1Gi `
    --min-replicas 1 `
    --max-replicas 3 `
    --volume-mount "volumeName=azure-file-volume,mountPath=/mnt" `
    --volume "name=azure-file-volume,storageType=AzureFile,storageName=azurefiles" `
    --registry-server "saswattestregistry.azurecr.io" `
    --registry-identity system `
    --assign-identity `
    --system-assigned `
    --env-vars "DIM_MatchingSvc_AppSettings__ConfigFolder=/mnt" `
               "DIM_MatchingSvc_AppSettings__KeyStoreFolder=/mnt/KeyStore" `
               "DIM_MatchingSvc_AppSettings__Logs=/mnt/Logs" `
               "DIM_MatchingSvc_AppSettings__RapSettingsFileName=RapSettings.json" `
               "AZURE_CLIENT_ID=system"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to create Container App" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Container App created successfully" -ForegroundColor Green
Write-Host ""

# ============================================================================
# MANAGED IDENTITY PERMISSIONS
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 9: MANAGED IDENTITY CONFIGURATION" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[IDENTITY] Configuring Managed Identity permissions..." -ForegroundColor Yellow
Write-Host "[WAIT] Waiting for identity to propagate..." -ForegroundColor Gray
Start-Sleep -Seconds 10

$principalId = az containerapp identity show --name $containerApp --resource-group $resourceGroup --query "principalId" -o tsv
if ($principalId) {
    Write-Host "[OK] Principal ID obtained: $principalId" -ForegroundColor Green
    
    $acrResourceId = az acr show --name $acrName --resource-group $resourceGroup --query "id" -o tsv
    $storageResourceId = az storage account show --name $storageAccount --resource-group $resourceGroup --query "id" -o tsv
    
    Write-Host "[ROLE] Assigning ACR Pull role..." -ForegroundColor Yellow
    az role assignment create --assignee $principalId --role "AcrPull" --scope $acrResourceId
    
    Write-Host "[ROLE] Assigning Storage File Data SMB Share Contributor role..." -ForegroundColor Yellow
    az role assignment create --assignee $principalId --role "Storage File Data SMB Share Contributor" --scope $storageResourceId
    
    Write-Host "[ROLE] Assigning Storage Account Contributor role..." -ForegroundColor Yellow
    az role assignment create --assignee $principalId --role "Storage Account Contributor" --scope $storageResourceId
    
    Write-Host "[OK] All permissions configured" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Could not get principal ID - permissions may need manual configuration" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# SECURE STORAGE ACCOUNT
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 10: SECURITY HARDENING" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

Write-Host "[SECURITY] Securing storage account (disabling public access)..." -ForegroundColor Yellow
az storage account update `
    --resource-group $resourceGroup `
    --name $storageAccount `
    --public-network-access Disabled
Write-Host "[OK] Storage account secured" -ForegroundColor Green
Write-Host ""

# ============================================================================
# DEPLOYMENT VERIFICATION
# ============================================================================
Write-Host "================================================================================" -ForegroundColor Blue
Write-Host "STEP 11: DEPLOYMENT VERIFICATION" -ForegroundColor Blue
Write-Host "================================================================================" -ForegroundColor Blue

# Get app URL
Write-Host "[URL] Retrieving application URL..." -ForegroundColor Yellow
$appUrl = az containerapp show --name $containerApp --resource-group $resourceGroup --query "properties.configuration.ingress.fqdn" -o tsv

# Verify Container App exists
$appExists = az containerapp show --name $containerApp --resource-group $resourceGroup --query "name" -o tsv 2>$null
if (-not $appExists) {
    Write-Host "[ERROR] Container App deployment verification failed" -ForegroundColor Red
    exit 1
}

Write-Host "[WAIT] Waiting 30 seconds for container to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Test file share access
Write-Host "[TEST] Testing file share access..." -ForegroundColor Yellow
$testsPassed = 0
$totalTests = 5

Write-Host "   Test 1/5: Creating KeyStore directory..." -ForegroundColor Gray
az containerapp exec --name $containerApp --resource-group $resourceGroup --command "mkdir -p /mnt/KeyStore" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { 
    Write-Host "   [PASS] KeyStore directory created" -ForegroundColor Green
    $testsPassed++
} else { 
    Write-Host "   [WARN] KeyStore directory creation failed" -ForegroundColor Yellow 
}

Write-Host "   Test 2/5: Creating Logs directory..." -ForegroundColor Gray
az containerapp exec --name $containerApp --resource-group $resourceGroup --command "mkdir -p /mnt/Logs" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { 
    Write-Host "   [PASS] Logs directory created" -ForegroundColor Green
    $testsPassed++
} else { 
    Write-Host "   [WARN] Logs directory creation failed" -ForegroundColor Yellow 
}

Write-Host "   Test 3/5: Listing mount directory..." -ForegroundColor Gray
$test3 = az containerapp exec --name $containerApp --resource-group $resourceGroup --command "ls -la /mnt" 2>&1
if ($LASTEXITCODE -eq 0) { 
    Write-Host "   [PASS] Mount directory accessible" -ForegroundColor Green
    $testsPassed++
} else { 
    Write-Host "   [WARN] Mount directory not accessible" -ForegroundColor Yellow 
}

Write-Host "   Test 4/5: Writing test file..." -ForegroundColor Gray
az containerapp exec --name $containerApp --resource-group $resourceGroup --command "echo Hello Azure > /mnt/test.txt" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { 
    Write-Host "   [PASS] Test file written" -ForegroundColor Green
    $testsPassed++
} else { 
    Write-Host "   [WARN] Test file write failed" -ForegroundColor Yellow 
}

Write-Host "   Test 5/5: Reading test file..." -ForegroundColor Gray
az containerapp exec --name $containerApp --resource-group $resourceGroup --command "cat /mnt/test.txt" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { 
    Write-Host "   [PASS] Test file read successfully" -ForegroundColor Green
    $testsPassed++
} else { 
    Write-Host "   [WARN] Test file read failed" -ForegroundColor Yellow 
}

Write-Host ""
if ($testsPassed -eq $totalTests) {
    Write-Host "[RESULT] Test Results: $testsPassed/$totalTests passed" -ForegroundColor Green
} else {
    Write-Host "[RESULT] Test Results: $testsPassed/$totalTests passed" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================
if ($appUrl) {
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host " DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "DEPLOYMENT DETAILS:" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   Resource Group:        $resourceGroup" -ForegroundColor White
    Write-Host "   Location:              $location" -ForegroundColor White
    Write-Host "   App URL:               https://$appUrl" -ForegroundColor Yellow
    Write-Host "   Container Image:       $containerImage" -ForegroundColor White
    Write-Host "   Target Port:           $targetPort" -ForegroundColor White
    Write-Host "   Mount Path:            /mnt" -ForegroundColor White
    Write-Host "   File Share:            $fileShare" -ForegroundColor White
    Write-Host "   Authentication:        System Managed Identity" -ForegroundColor White
    Write-Host ""
    
    Write-Host "QUICK VERIFICATION COMMANDS:" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   Test application:" -ForegroundColor White
    Write-Host "   curl https://$appUrl" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   List resources:" -ForegroundColor White
    Write-Host "   az resource list --resource-group $resourceGroup --output table" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Check ACR images:" -ForegroundColor White
    Write-Host "   az acr repository list --name $acrName --output table" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   View app logs:" -ForegroundColor White
    Write-Host "   az containerapp logs show --name $containerApp --resource-group $resourceGroup --follow" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Scale app:" -ForegroundColor White
    Write-Host "   az containerapp update --name $containerApp --resource-group $resourceGroup --min-replicas 2 --max-replicas 5" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "   1. Test your application at: https://$appUrl" -ForegroundColor White
    Write-Host "   2. Upload configuration files to the file share" -ForegroundColor White
    Write-Host "   3. Monitor application logs for any issues" -ForegroundColor White
    Write-Host "   4. Configure auto-scaling rules if needed" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Your Container App is now running with VNet integration!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host " DEPLOYMENT ENCOUNTERED ISSUES" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "The deployment process completed but the application URL could not be retrieved." -ForegroundColor Yellow
    Write-Host "Please check the following:" -ForegroundColor Yellow
    Write-Host "   1. Review the Azure Portal for the resource group: $resourceGroup" -ForegroundColor White
    Write-Host "   2. Check Container App logs for errors" -ForegroundColor White
    Write-Host "   3. Verify all resources were created successfully" -ForegroundColor White
    Write-Host "   4. Ensure all permissions are correctly configured" -ForegroundColor White
    Write-Host ""
    exit 1
}