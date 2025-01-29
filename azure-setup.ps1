#############################################
$subscriptionID = "a8f472b9-6b5a-48fe-806d-a3ca4e2d1f6f"
$resourceGroup = "asdf"
$storageAccount = "asdfasdfas"
$location = "australiacentral"

class EnrichmentScope {
    [string]$SubscriptionID
    [string[]]$ResourceGroupNames
}

$enrichmentScopes = @()
#############################################

# set the subscription context
Set-AzContext -Subscription $subscriptionID
Write-Output ""

$ErrorActionPreference = "Stop"

# Verify subscription ID
Write-Output "Verifying subscription ID '$subscriptionID"
$ret = Get-AzSubscription -SubscriptionId $subscriptionID -ErrorAction SilentlyContinue
if ( $ret.ID.Length -eq 0 ) {
    Write-Error "Fail: Could not find subscriptionID '$subscriptionID'"
}
else {
    Write-Output "Success: verified subscription ID"
}
Write-Output ""

# Verify the location
Write-Output "Verifying location '$location'"
$foundLocation = $false
Get-AzLocation | ForEach-Object {
    if ( $_.Location.length -gt 0 -AND $location.toLower().equals($_.Location.toLower()) ) {
        $foundLocation = $true
    }
}
if ( -NOT $foundLocation ) {
    Write-Error "Fail: Could not find location '$location"
}
else {
    Write-Output "Success: Location verified"
}
Write-Output ""

# Verify the resource group
Write-Output "Verifying resource group '$resourceGroup'"
$ret = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
if ( $ret.ResourceGroupName.length -eq 0 ) {
    Write-Error "Fail: Could not find resource group '$resourceGroup'"
}
else {
    Write-Output "Success: Resource group verified"
}
Write-Output ""

# Verify the subscription has a service principal for the Kentik app
Write-Output "Ensuring Kentik service principal a20ce222-63c0-46db-86d5-58551eeee89f exists"
$ret = Get-AzADServicePrincipal -ApplicationID a20ce222-63c0-46db-86d5-58551eeee89f
if ( $ret.DisplayName.length -eq 0 ) {
    Write-Error "Fail: Could not find the service principal"
}
else {
    $appPrincipalID = $ret.Id
    $kentikPrincipalName = $ret.DisplayName
    Write-Output "Success: service principal found with ID '$appPrincipalID', display name '$kentikPrincipalName'"
}
Write-Output ""

# Verify the service principal has Reader access to the resource group
Write-Output "Ensuring service principal '$kentikPrincipalName' has Reader access to resource group '$resourceGroup'"
$ret = Get-AzRoleAssignment -ObjectId $appPrincipalID -ResourceGroupName $resourceGroup -RoleDefinitionName Reader -ErrorAction SilentlyContinue
if ( $ret.RoleDefinitionName.length -eq 0 ) {
    $ret = New-AzRoleAssignment -ObjectId $appPrincipalID -ResourceGroupName $resourceGroup -RoleDefinitionName Reader
    if ( $ret.RoleDefinitionName.length -gt 0 -AND $ret.RoleDefinitionName.toLower().equals("reader") ) {
        Write-Output "Success: Access granted"
    }
    else {
        Write-Error "Fail: Could not grant access"
    }
}
else {
    Write-Output "Success: Access was already granted"
}
Write-Output ""

# Verify service principal has Reader access to enrichment subscriptions and resource groups
Foreach ($enrichmentScope in $enrichmentScopes) {
    if ($enrichmentScope.ResourceGroupNames.length -eq 0 ) {
        # Verify subscription Reader role
        $subscriptionScope = "/subscriptions/" + $enrichmentScope.SubscriptionID
        Write-Output "Ensuring service principal '$kentikPrincipalName' has Reader access to '$subscriptionScope'"
        $ret = Get-AzRoleAssignment -ObjectId $appPrincipalID -Scope $subscriptionScope -RoleDefinitionName Reader
        if ( $ret.Scope -eq $subscriptionScope ) {
            Write-Output "Success: Access was already granted to subscription scope: " + $subscriptionScope
        }
        else {
            Write-Output "Reader role not found. Creating new role"
            $ret = New-AzRoleAssignment -ObjectId $appPrincipalID -Scope $subscriptionScope -RoleDefinitionName Reader
            if ( $ret.Scope -eq $subscriptionScope ) {
                Write-Output "Success: Access granted"
            }
            else {
                Write-Error "Fail: Could not grant Reader role to $subscriptionScope"
            }
        }
    }
    else {
        # Verify individual resource group reader roles
        Foreach ($enrichmentResourceGroupName in $enrichmentscope.ResourceGroupNames) {
            $resourceGroupScope = "/subscriptions/" + $enrichmentScope.SubscriptionID + "/resourceGroups/" + $enrichmentResourceGroupName
            Write-Output "Ensuring service principal '$kentikPrincipalName' has Reader access to '$resourceGroupScope'"
            $ret = Get-AzRoleAssignment -ObjectId $appPrincipalID -Scope $resourceGroupScope -RoleDefinitionName Reader
            if ( $ret.length -gt 0 ) {
                Write-Output "Success: Access was already granted"
            }
            else {
                Write-Output "Reader role not found. Creating new role"
                $ret = New-AzRoleAssignment -ObjectId $appPrincipalID -Scope "$resourceGroupScope" -RoleDefinitionName Reader
                if ( $ret.Scope -eq $resourceGroupScope ) {
                    Write-Output "Success: Access granted"
                }
                else {
                    Write-Error "Fail: Could not grant Reader role to $resourceGroupScope"
                }
            }
        }
    }
}

# Verify storage account
$storageAccount = $storageAccount.toLower()
Write-Output "Ensuring storage account '$storageAccount' in resource group '$resourceGroup', location '$location'"
$ret = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount -ErrorAction SilentlyContinue
$storageAccountID = $ret.ID
if ( $ret.ProvisioningState -ne 'Succeeded' ) {
    # Create storage account
    Write-Output "Storage account does not yet exist - creating it now"
    $ret = New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount -Location $location -SkuName Standard_LRS -Kind StorageV2
    if ( $ret.ResourceGroupName.toLower().equals($resourceGroup.toLower()) ) {
        $storageAccountID = $ret.ID
        Write-Output "Success: Created storage account"
    }
    else {
        Write-Error "Fail: Could not create storage account"
    }
}
else {
    if ( -NOT $ret.Location.toLower().equals($location.toLower()) ) {
        Write-Error "Fail: storage account '$storageAccount' found, but in location '$($ret.Location)'. Must be in location '$location'"
    }

    $storageAccountID = $ret.ID
    Write-Output "Success: storage account already exists"
}
Write-Output ""

# Verify the service principal has Contributor access to the storage account, so it can fetch the access keys to then check for NSG flow logs
Write-Output "Ensuring service principal '$kentikPrincipalName' has Contributor access to storage account '$storageAccount'"
$ret = Get-AzRoleAssignment -ObjectId $appPrincipalID -ResourceGroupName $resourceGroup -ResourceType "Microsoft.Storage/storageAccounts" -ResourceName $storageAccount -RoleDefinitionName Contributor -ErrorAction SilentlyContinue
if ( $ret.RoleDefinitionName.length -eq 0 ) {
    $ret = New-AzRoleAssignment -ObjectId $appPrincipalID -ResourceGroupName $resourceGroup -ResourceType "Microsoft.Storage/storageAccounts" -ResourceName $storageAccount -RoleDefinitionName Contributor
    if ( $ret.RoleDefinitionName.length -gt 0 -AND $ret.RoleDefinitionName.toLower().equals("contributor") ) {
        Write-Output "Success: Access granted"
    }
    else {
        Write-Error "Fail: Could not grant access"
    }
}
else {
    Write-Output "Success: Access was already granted"
}
Write-Output ""

# Ensure network watcher feature is registered
# Network Watcher feature is registered by default
Write-Output "Ensuring network watcher feature is registered."
$nwRet = Get-AzProviderFeature -FeatureName AllowNetworkWatcher -ProviderNamespace Microsoft.Network

if ($nwRet.RegistrationState -ne 'Registered') {
    Register-AzProviderFeature -FeatureName AllowNetworkWatcher -ProviderNamespace Microsoft.Network
    Write-Output "Network Watcher feature is being registered. Please be patient, this may take several minutes."

    # Wait for the feature to be registered
    do {
        Start-Sleep -Milliseconds 5000
        $nwRet = Get-AzProviderFeature -FeatureName AllowNetworkWatcher -ProviderNamespace Microsoft.Network
        Write-Output "Checking registration status..."
    } while ($nwRet.RegistrationState -ne 'Registered')

    Write-Output "Success: Network Watcher feature is now registered."
}
else {
    Write-Output "Success: Network Watcher feature is already registered."
}
Write-Output ""

# Ensure the network watcher feature is enabled for the resource group and location
# By default, Network Watcher is automatically enabled.
# When you create or update a virtual network in your subscription, Network Watcher will be automatically enabled in your Virtual Network's region.
# https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-create?tabs=powershell
Write-Output "Ensuring network watcher for resource group '$resourceGroup', location '$location'"
$ret = Get-AzNetworkWatcher -Location $location -ErrorAction SilentlyContinue
$networkWatcherObj = $ret
if ( $ret.ProvisioningState.length -eq 0 -OR -Not $ret.ProvisioningState.toLower().equals("succeeded") ) {
    $ret = New-AzNetworkWatcher -Name "NetworkWatcher_$($location)" -ResourceGroupName $resourceGroup -Location $location
    if ( -Not $ret.Name.equals("") ) {
        $networkWatcherObj = $ret
        Write-Output "Success: Network watcher created"
    }
    else {
        Write-Error "Fail: Could not create network watcher"
    }
}
else {
    $networkWatcherObj = $ret
    Write-Output "Success: Network watcher already exists"
}
Write-Output ""

# Ensure the Insights provider is registered
Write-Output "Ensuring the Microsoft Insights provider is registered. Please be patient, this may take several minutes"
Do {
    $ret = Register-AzResourceProvider -ProviderNamespace microsoft.insights
    $ret = $ret.RegistrationState
    Write-Output "Insights provider registration state: $ret"
    Start-Sleep -Milliseconds 5000
} While ( -Not $ret.toLower().equals("registered") )
Write-Output "Success: Microsoft Insights provider is registered"
Write-Output ""

# Add VNet support
Write-Output "Looking for Virtual Networks (VNets) in resource group '$resourceGroup'"
Get-AzVirtualNetwork -ResourceGroupName $resourceGroup | ForEach-Object {
    $VNet = $_
    if ($VNet.Location.length -gt 0 -AND $VNet.Location.toLower().equals($location.toLower())) {
        Write-Output "Found Virtual Network '$($VNet.Name)' in location '$location'"

        # Check if VNet flow logs are already enabled
        Write-Output "Checking if VNet flow logs are already enabled for Virtual Network '$($VNet.Name)'"
        $existingFlowLogs = Get-AzNetworkWatcherFlowLog -NetworkWatcherName "NetworkWatcher_$location" -ResourceGroupName "NetworkWatcherRG" -ErrorAction SilentlyContinue
        $existingFlowLog = $existingFlowLogs | Where-Object { $_.TargetResourceId -eq $VNet.Id }

        if ($existingFlowLog -and $existingFlowLog.Enabled) {
            Write-Output "Success: VNet flow logs already exist for Virtual Network '$($VNet.Name)' with Name: $($existingFlowLog.Name)"
        }
        else {
            # Enable VNet flow logs
            # https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-powershell
            Write-Output "Enabling VNet flow logs for Virtual Network '$($VNet.Name)'"
            $ret = New-AzNetworkWatcherFlowLog -Enabled $true -Name "flowLog_$($VNet.Name)" -NetworkWatcherName "NetworkWatcher_$location" -ResourceGroupName NetworkWatcherRG -StorageId $storageAccountID -TargetResourceId $VNet.Id -FormatVersion 2 -EnableRetention $true -RetentionPolicyDays 7
            if ( $ret.TargetResourceId.toLower().length -ne 0 -AND $ret.Enabled ) {
                Write-Output "Success: VNet flow logs are enabled with Name: $($ret.Name)"
            }
            else {
                Write-Error "Fail: Could not enable VNet flow logs"
            }
        }
        Write-Output ""
    }
}

Write-Output "Please provide Kentik with the following:"
Write-Output "`tSubscription ID:            $subscriptionID"
Write-Output "`tResource Group:             $resourceGroup"
Write-Output "`tLocation:                   $location"
Write-Output "`tStorage Account:            $storageAccount"
Write-Output ""
Write-Output ""
