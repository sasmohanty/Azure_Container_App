# Azure Container App deployment with VNet + Azure Files (idempotent)
# Version: 3.7 (annotated) — adds comments throughout without changing logic

# =============================
# CONFIGURATION (do not change)
# These variables define names, locations, and image references used everywhere.
# =============================
$resourceGroup   = "E1074651-SDLDEV"         # Resource group that holds all resources
$location        = "East US 2"                # Azure region
$storageAccount  = "sasstor6778g5"            # Storage account for Azure Files
$fileShare       = "matchingservicefileshare" # Azure File Share name
$vnetName        = "matchingservice-vnet"     # Virtual Network name
$containerAppEnv = "matchingserviceappenvironment" # Container Apps Environment name
$containerApp    = "matchingservice"          # Container App name (also container name)
$acrName         = "saswattestregistry"       # Azure Container Registry name
$containerImage  = "saswattestregistry.azurecr.io/myapp:latest" # Private image tag
$sourceImage     = "mcr.microsoft.com/azuredocs/aci-helloworld" # Public bootstrap image
$targetPort      = 80                          # App listening port exposed by ingress

# Stats for a friendly summary at the end.
$created = 0; $skipped = 0

Write-Host ""; Write-Host "=== AZURE CONTAINER APP DEPLOYMENT START ===" -ForegroundColor Cyan

# =============================
# AUTH
# Confirm the user is logged in to Azure CLI. We only read the username here.
# =============================
$currentUser = az account show --query "user.name" -o tsv 2>$null
if (-not $currentUser) { Write-Host "Login required. Run az login" -ForegroundColor Red; exit 1 }
Write-Host "Logged in as $currentUser" -ForegroundColor Green

# =============================
# HELPER FUNCTIONS
# Each helper performs an idempotent step: create if missing, otherwise skip.
# =============================
function Ensure-ExtAndProviders {
  # Make sure the Container Apps CLI extension is installed and up to date
  if (-not (az extension list --query "[?name=='containerapp']" -o tsv 2>$null)) { az extension add -n containerapp --upgrade | Out-Null }
  # Register required resource providers so ARM can provision resources
  $providers = @("Microsoft.App","Microsoft.ContainerRegistry","Microsoft.Storage","Microsoft.Network","Microsoft.OperationalInsights")
  foreach ($p in $providers) {
    if ((az provider show --namespace $p -o tsv --query registrationState) -ne "Registered") {
      az provider register --namespace $p --wait | Out-Null
    }
  }
}
function Ensure-Group { param($rg,$loc)
  # Create the resource group if it does not exist
  if (-not (az group show -n $rg -o tsv --query name 2>$null)) {
    az group create -n $rg -l $loc | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-ACR { param($name,$rg,$loc)
  # Create ACR registry used to host the private image
  if (-not (az acr show -n $name -g $rg -o tsv --query name 2>$null)) {
    az acr create -n $name -g $rg -l $loc --sku Basic --admin-enabled false | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-AcrImage { param($acr,$src,$image)
  # Import a public sample image into the ACR if the repo is missing
  $repo = ($image.Split(":")[0].Split("/")[-1])
  if (-not (az acr repository show -n $acr --repository $repo -o tsv --query name 2>$null)) {
    az acr import -n $acr --source $src --image $image.Split("/",2)[1] --force | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-Storage { param($rg,$name,$loc)
  # Create the Azure Storage account (general purpose v2) for Azure Files
  if (-not (az storage account show -g $rg -n $name -o tsv --query name 2>$null)) {
    az storage account create -g $rg -n $name -l $loc --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-Share { param($rg,$acct,$share)
  # Create the Azure File Share using ARM (RBAC) API so it works without account keys
  if (-not (az storage share-rm show --resource-group $rg --storage-account $acct --name $share -o tsv --query name 2>$null)) {
    az storage share-rm create --resource-group $rg --storage-account $acct --name $share --quota 512 --enabled-protocols SMB | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-VNet { param($rg,$vnet,$loc)
  # Create a VNet for the Container Apps environment and private endpoints
  if (-not (az network vnet show -g $rg -n $vnet -o tsv --query name 2>$null)) {
    az network vnet create -g $rg -n $vnet -l $loc --address-prefix 10.0.0.0/16 | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-Subnet-CA { param($rg,$vnet)
  # Ensure a subnet delegated to Container Apps exists. Recreate if missing delegation.
  $ok = az network vnet subnet show -g $rg --vnet-name $vnet -n container-apps-subnet --query "delegations[0].serviceName" -o tsv 2>$null
  if ($ok -ne "Microsoft.App/environments") {
    if ($ok) { az network vnet subnet delete -g $rg --vnet-name $vnet -n container-apps-subnet | Out-Null }
    az network vnet subnet create -g $rg --vnet-name $vnet -n container-apps-subnet --address-prefix 10.0.0.0/23 --delegations Microsoft.App/environments | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-Subnet-StoragePE { param($rg,$vnet)
  # Subnet for Storage private endpoint, with network policies disabled as required
  if (-not (az network vnet subnet show -g $rg --vnet-name $vnet -n storage-private-endpoint-subnet -o tsv --query name 2>$null)) {
    az network vnet subnet create -g $rg --vnet-name $vnet -n storage-private-endpoint-subnet --address-prefix 10.0.4.0/24 --disable-private-endpoint-network-policies true | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-StoragePEandDNS { param($rg,$acct,$vnet,$loc)
  # Create a Private Endpoint to the storage account (file service) and wire up DNS
  $peName = "$acct-pe"
  if (-not (az network private-endpoint show -g $rg -n $peName -o tsv --query name 2>$null)) {
    $subId = az account show --query id -o tsv
    az network private-endpoint create -g $rg -n $peName -l $loc --vnet-name $vnet --subnet storage-private-endpoint-subnet --private-connection-resource-id "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$acct" --group-id file --connection-name "$acct-connection" | Out-Null; $script:created++
  } else { $script:skipped++ }
  # Private DNS zone for Azure Files
  if (-not (az network private-dns zone show -g $rg -n privatelink.file.core.windows.net -o tsv --query name 2>$null)) {
    az network private-dns zone create -g $rg -n privatelink.file.core.windows.net | Out-Null; $script:created++
  } else { $script:skipped++ }
  # Link the VNet to the zone
  if (-not (az network private-dns link vnet show -g $rg --zone-name privatelink.file.core.windows.net -n dns-link -o tsv --query name 2>$null)) {
    az network private-dns link vnet create -g $rg --zone-name privatelink.file.core.windows.net -n dns-link --virtual-network $vnet --registration-enabled false | Out-Null; $script:created++
  } else { $script:skipped++ }
  # Attach the zone to the private endpoint
  if (-not (az network private-endpoint dns-zone-group show -g $rg --endpoint-name $peName -n zone-group -o tsv --query name 2>$null)) {
    az network private-endpoint dns-zone-group create -g $rg --endpoint-name $peName -n zone-group --private-dns-zone privatelink.file.core.windows.net --zone-name file | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-Env { param($rg,$envName,$loc,$vnet)
  # Create a Container Apps environment on the delegated subnet
  if (-not (az containerapp env show -g $rg -n $envName -o tsv --query name 2>$null)) {
    $subnetId = az network vnet subnet show -g $rg --vnet-name $vnet -n container-apps-subnet --query id -o tsv
    az containerapp env create -g $rg -n $envName -l $loc --infrastructure-subnet-resource-id $subnetId --internal-only false | Out-Null; $script:created++
  } else { $script:skipped++ }
}
function Ensure-EnvStorage { param($rg,$envName,$acct,$share)
  # Register the Azure Files share as environment storage named "azurefiles"
  $exists = az containerapp env storage show -g $rg -n $envName --storage-name azurefiles -o tsv --query name 2>$null
  if (-not $exists) {
    $key = az storage account keys list -g $rg -n $acct -o tsv --query "[0].value"
    az containerapp env storage set -g $rg -n $envName --storage-name azurefiles --azure-file-account-name $acct --azure-file-account-key $key --azure-file-share-name $share --access-mode ReadWrite | Out-Null; $script:created++
  } else { $script:skipped++ }
}

# =============================
# CREATE PREREQUISITES
# The following sequence creates or verifies all required infrastructure.
# =============================
Ensure-ExtAndProviders
Ensure-Group $resourceGroup $location
Ensure-ACR $acrName $resourceGroup $location
Ensure-AcrImage $acrName $sourceImage $containerImage
Ensure-Storage $resourceGroup $storageAccount $location
Ensure-Share $resourceGroup $storageAccount $fileShare
Ensure-VNet $resourceGroup $vnetName $location
Ensure-Subnet-CA $resourceGroup $vnetName
Ensure-Subnet-StoragePE $resourceGroup $vnetName
Ensure-StoragePEandDNS $resourceGroup $storageAccount $vnetName $location
Ensure-Env $resourceGroup $containerAppEnv $location $vnetName
Ensure-EnvStorage $resourceGroup $containerAppEnv $storageAccount $fileShare

# =============================
# CONTAINER APP
# We bootstrap with a public image so the app exists before configuring ACR auth.
# Then we assign system identity, grant AcrPull, set the registry, and switch image.
# =============================
$appExists = az containerapp show -g $resourceGroup -n $containerApp -o tsv --query name 2>$null
if (-not $appExists) {
  Write-Host "Creating Container App with public image to bootstrap identity" -ForegroundColor Yellow
  az containerapp create -g $resourceGroup -n $containerApp --environment $containerAppEnv --image $sourceImage --target-port $targetPort --ingress external --cpu 0.5 --memory 1Gi --min-replicas 1 --max-replicas 3 | Out-Null; $created++
} else { $skipped++ }

# Assign a system managed identity to the app
az containerapp identity assign -g $resourceGroup -n $containerApp --system-assigned | Out-Null
# Grant the app permission to pull from ACR and wire up the registry using the identity
$principalId = az containerapp identity show -g $resourceGroup -n $containerApp -o tsv --query principalId
if ($principalId) {
  $acrId = az acr show -g $resourceGroup -n $acrName -o tsv --query id
  az role assignment create --assignee $principalId --role AcrPull --scope $acrId | Out-Null
  az containerapp registry set -g $resourceGroup -n $containerApp --server "$acrName.azurecr.io" --identity system | Out-Null
}
# Switch the running image to your private image in ACR
az containerapp update -g $resourceGroup -n $containerApp --image $containerImage | Out-Null

# =============================
# AZURE FILES VOLUME + MOUNT
# Some CLI versions do not support --add for nested arrays, so we patch via YAML.
# The patch adds a named volume that points to env storage "azurefiles" and mounts it at /mnt.
# =============================
$patchPath = Join-Path $env:TEMP "mount-$containerApp.yaml"
@"
properties:
  template:
    containers:
    - name: $containerApp
      image: $containerImage
      volumeMounts:
      - volumeName: azure-file-volume
        mountPath: /mnt
    volumes:
    - name: azure-file-volume
      storageType: AzureFile
      storageName: azurefiles
"@ | Set-Content -Path $patchPath -Encoding UTF8
# Apply the patch to the app spec
az containerapp update -g $resourceGroup -n $containerApp --yaml $patchPath | Out-Null

# Optionally set app environment variables that refer to the mounted path
az containerapp update -g $resourceGroup -n $containerApp `
  --set-env-vars "DIM_MatchingSvc_AppSettings__ConfigFolder=/mnt" "DIM_MatchingSvc_AppSettings__KeyStoreFolder=/mnt/KeyStore" "DIM_MatchingSvc_AppSettings__Logs=/mnt/Logs" "DIM_MatchingSvc_AppSettings__RapSettingsFileName=RapSettings.json" | Out-Null

# =============================
# SECURITY HARDENING
# Disable public network access on the storage account if not already disabled.
# =============================
if ((az storage account show -g $resourceGroup -n $storageAccount -o tsv --query publicNetworkAccess) -ne "Disabled") {
  az storage account update -g $resourceGroup -n $storageAccount --public-network-access Disabled | Out-Null
}

# =============================
# VERIFICATION
# Print a human friendly summary and show the volumes and mounts as read from the app.
# =============================
$appUrl = az containerapp show -g $resourceGroup -n $containerApp -o tsv --query properties.configuration.ingress.fqdn
$specJson = az containerapp show -g $resourceGroup -n $containerApp -o json | ConvertFrom-Json
$vols = $specJson.properties.template.volumes
$mounts = $specJson.properties.template.containers[0].volumeMounts

Write-Host ""; Write-Host "=== DEPLOYMENT SUMMARY ===" -ForegroundColor Green
Write-Host "Resources created: $created" -ForegroundColor Green
Write-Host "Resources skipped: $skipped" -ForegroundColor Gray
Write-Host "App URL: https://$appUrl" -ForegroundColor Yellow
Write-Host "Volumes:" ($vols | ConvertTo-Json -Depth 5)
Write-Host "Mounts :" ($mounts | ConvertTo-Json -Depth 5)
Write-Host ""; Write-Host "Try:" -ForegroundColor Cyan
Write-Host "curl https://$appUrl" -ForegroundColor Gray
Write-Host "az containerapp logs show -g $resourceGroup -n $containerApp --follow" -ForegroundColor Gray
