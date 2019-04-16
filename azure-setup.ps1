#############################################
$subscriptionID = "a8f472b9-6b5a-48fe-806d-a3ca4e2d1f6f"
$resourceGroup = "asdf"
$storageAccount = "asdfasdfas"
$location = "australiacentral"
#############################################

$ErrorActionPreference = "Stop"

# Verify subscription ID
Write-Output "Verifying subscription ID '$subscriptionID"
$ret = Get-AzSubscription -SubscriptionId $subscriptionID -ErrorAction SilentlyContinue
if ( $ret.ID.Length -eq 0 ) {
    Write-Error "Fail: Could not find subscriptionID '$subscriptionID'"
} else {
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
} else {
    Write-Output "Success: Location verified"
}
Write-Output ""

# Verify the resource group
Write-Output "Verifying resource group '$resourceGroup'"
$ret = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
if ( $ret.ResourceGroupName.length -eq 0 ) {
    Write-Error "Fail: Could not find resource group '$resourceGroup'"
} else {
    Write-Output "Success: Resource group verified"
}
Write-Output ""

# Verify the subscription has a service principal for the Kentik app
Write-Output "Ensuring Kentik service principal 'a20ce222-63c0-46db-86d5-58551eeee89f' exists"
$ret = Get-AzADServicePrincipal -ApplicationID "a20ce222-63c0-46db-86d5-58551eeee89f"
if ( $ret.DisplayName.length -eq 0 ) {
    Write-Error "Fail: Could not find the service principal"
} else {
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
    } else {
        Write-Error "Fail: Could not grant access"
    }
} else {
    Write-Output "Success: Access was already granted"
}
Write-Output ""

# Verify storage account
$storageAccount = $storageAccount.toLower()
Write-Output "Ensuring storage account '$storageAccount' in resource group '$resourceGroup', location '$location'"
$ret = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount -ErrorAction SilentlyContinue
$storageAccountID = $ret.ID
if ( $ret.ProvisioningState -ne [Microsoft.Azure.Management.Network.Models.ProvisioningState]::Succeeded ) {
    # Create storage account
    Write-Output "Storage account does not yet exist - creating it now"
    $ret = New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount -Location $location -SkuName Standard_LRS -Kind StorageV2
    if ( $ret.ResourceGroupName.toLower().equals($resourceGroup.toLower()) ){
        $storageAccountID = $ret.ID
        Write-Output "Success: Created storage account"
    } else {
        Write-Error "Fail: Could not create storage account"
    }
} else {
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
    } else {
        Write-Error "Fail: Could not grant access"
    }
} else {
    Write-Output "Success: Access was already granted"
}
Write-Output ""

# Enable network watcher feature is registered
Write-Output "Ensuring network watcher feature is registered. Please be patient, this may take several minutes"
$nwRet = Register-AzProviderFeature -FeatureName AllowNetworkWatcher -ProviderNamespace Microsoft.Network
While ( $nwRet.RegistrationState.toLower().equals("registering") ) {
    $nwRet = Get-AzProviderFeature -FeatureName AllowNetworkWatcher -ProviderNamespace Microsoft.Network
    $nwState = $nwRet.RegistrationState
    Write-Output "Network watcher registration state: '$nwState'"
    Start-Sleep -Milliseconds 5000
}
if ( $nwRet.RegistrationState.toLower().equals("registered") ) {
    Write-Output "Success! NetworkWatcher is registered"
} else {
    Write-Error "Fail: NetworkWatcher could not be registered"
}
Write-Output ""

# Ensure the network watcher feature is enabled for the resource group and location
Write-Output "Ensuring network watcher for resource group '$resourceGroup', location '$location'"
$ret = Get-AzNetworkWatcher -Location $location -ErrorAction SilentlyContinue
$networkWatcherObj = $ret
if ( $ret.ProvisioningState.length -eq 0 -OR -Not $ret.ProvisioningState.toLower().equals("succeeded") ) {
    $ret = New-AzNetworkWatcher -Name "nw_$($location)" -ResourceGroupName $resourceGroup -Location $location
    if ( -Not $ret.Name.equals("") ) {
        $networkWatcherObj = $ret
        Write-Output "Success: Network watcher created"
    } else {
        Write-Error "Fail: Could not create network watcher"
    }
} else {
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

# Turn on v2 flow logs for every network security group in the resource group and region
Write-Output "Looking for network security groups in resource group '$resourceGroup'"
Write-Output ""
Get-AzNetworkSecurityGroup -ResourceGroupName $resourceGroup | ForEach-Object {
    $NSG = $_
    if ( $NSG.Location.length -gt 0 -AND $NSG.Location.toLower().equals($location.toLower())) {
        Write-Output "Found network security group '$($NSG.Name)' in location '$location'"

        # Enable flow logs for this NSG
        Write-Output "Enabling v2 flow logs in network security group '$($NSG.Name)'"
        $ret = Set-AzNetworkWatcherConfigFlowLog -RetentionInDays 2 -NetworkWatcher $networkWatcherObj -TargetResourceId $NSG.Id -StorageAccountId $storageAccountID -EnableFlowLog $true -FormatType Json -FormatVersion 2
        if ( $ret.TargetResourceId.toLower().length -ne 0 -AND $ret.Enabled ) {
            Write-Output "Success: Network security group flow logs are enabled"
        } else {
            Write-Error "Fail: Could not enable network security group flow logs"
        }
        Write-Output ""
    }
}

Write-Output ""
Write-Output ""
Write-Output "Please provide Kentik with the following:"
Write-Output "`tSubscription ID:            $subscriptionID"
Write-Output "`tResource Group:             $resourceGroup"
Write-Output "`tLocation:                   $location"
Write-Output "`tStorage Account:            $storageAccount"
Write-Output ""
Write-Output ""
