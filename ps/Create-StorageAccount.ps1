<#
.SYNOPSIS
Create an Azure Storage Account instance for tenant
.Description
Create an Azure Storage Account instance for tenant. And returns a storage account key.
.PARAMETER SubscriptionId
Azure subscription ID
.PARAMETER ResourceGroupName
Azure Resource Group
.PARAMETER Location
Location
.PARAMETER StorageAccountName
Name of storage account
Storage account name must be between 3 and 24 characters in length and use numbers and lower-case letters only.
.PARAMETER StorageAccountKind
the kind fo storage account
.PARAMETER StorageAccountSku
Performance and redundancy of storage account 
.PARAMETER StorageAccountAccessTier
Hot or cool
.PARAMETER FileShareQuota
Quota in GB
.PARAMETER KeyVaultName
Name of key vault where key for storage account encryption is
.PARAMETER KeyName
Name of key used for storage account encryption
.PARAMETER PrivateEndpointSubnetName
Name of subnet to use with private endpoint
.PARAMETER PrivateDnsSubscriptionId
ID of the Private DNS Subscription
.PARAMETER PrivateDnsResourceGroupName
Name of Private DNS Resource Group
.PARAMETER AllowedNetworks
JSON string of allowed networks where the a key is a vnet and an array of subnets is the value
.PARAMETER RecSvcVaultName
Name of Azure Recovery Services Vault containing Azure File Services backup policy
.PARAMETER AzFsBackupPolicy
Name of Azure File Services backup policy to apply to storage account
.EXAMPLE
---------- Example 1 ----------
$subId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
$rgName = 'ResourceGroupName';
$saName = 'StorageAccountName';
$networks = "{'vnet1':['subnet1','subnet2'], 'vnet2':['subnet1']};
.\Create-TenantStorageAccount.ps1 -SubscriptionId $subId -ResourceGroupName $rgName -StorageAccountName $saName -PrivateEndpointSubnetName $subNetName -PrivateDnsSubscriptionId $subId -PrivateDnsResourceGroupName $rgName -AllowedNetworks $networks
---------- Example 2 ----------
$subId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
$rgName = 'ResourceGroupName';
$saName = 'StorageAccountName';
$saKind = 'StorageV2';
$saSku = 'Standard_RAGRS';
$saAT = 'Hot';
$recoveryVault = 'AzRecVault';
$backupPolicy = 'dailyAzFsBackup';
$networks = "{'vnet1':['subnet1','subnet2'], 'vnet2':['subnet1']};
.\Create-TenantStorageAccount.ps1 -SubscriptionId $subId -ResourceGroupName $rgName -StorageAccountName $saName -StorageAccountKind $saKind -StorageAccountSku $saSku -StorageAccountAccessTier $saAT -PrivateEndpointSubnetName $subNetName -PrivateDnsSubscriptionId $subId -PrivateDnsResourceGroupName $rgName -AllowedNetworks $networks -RecSvcVaultName $recoveryVault -AzFsBackupPolicy $backupPolicy
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID")]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Resource Group")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,
    [Parameter(HelpMessage = "Location")]
    [ValidateNotNullOrEmpty()]
    [string]$Location,
    [Parameter(Mandatory = $true, HelpMessage = "Name of storage account")]
    [ValidateNotNullOrEmpty()]
    [string]$StorageAccountName,
    [Parameter(HelpMessage = "Storage account kind")]
    [ValidateSet('Storage', 'StorageV2', 'BlobStorage', 'BlockBlobStorage', 'FileStorage')]
    [string]$StorageAccountKind = 'StorageV2',
    [Parameter(HelpMessage = "Storage account SKU")]
    [ValidateSet('Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS', 'Premium_ZRS', 'Standard_GZRS', 'Standard_RAGZRS')]
    [string]$StorageAccountSku = 'Standard_RAGRS',
    [Parameter(HelpMessage = "Storage account access tier")]
    [ValidateSet('Hot', 'Cool')]
    [string]$StorageAccountAccessTier = 'Hot',
    [Parameter(HelpMessage = "File share quota in GB")]
    [ValidateRange(1, 1000)]
    [int]$FileShareQuota = 5,
    [Parameter(Mandatory = $true, HelpMessage = "Name of key vault where key for storage account encryption is")]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultName,
    [Parameter(HelpMessage = "Name of key used for storage account encryption")]
    [string]$KeyName,
    [Parameter(Mandatory = $true, HelpMessage = "Name of subnet for storage account private endpoints")]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateEndpointSubnetName,
    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID for private dns")]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateDnsSubscriptionId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Resource Group for private dns")]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateDnsResourceGroupName,
    [Parameter(Mandatory = $true, HelpMessage = "Network sources that should be allowed to access the storage account")]
    [string]$AllowedNetworks,
    [Parameter(HelpMessage = "Name of Azure Recovery Services Vault containing Azure File Services backup policy")]
    [string]$RecSvcVaultName,
    [Parameter(HelpMessage = "Name of Azure File Services backup policy to apply to storage account")]
    [string]$AzFsBackupPolicy
)

Import-Module Az;

<#
Get the virtual network for 'this' subscription
#>
function Get-VirtualNetwork {

    try {
        Write-Host "Get virtual network from subscription"
        # Might need to investigate a better way to look for the vnet as this method seems pretty
        # rigid and unreliable
        $vnet = Get-AzVirtualnetwork -ErrorAction Stop | Where-Object { $_.Name.Contains("spoke") } ;
        # sandbox value
        # $vnet = Get-AzVirtualnetwork -ErrorAction Stop | Where-Object { $_.Name -eq 'herbielower-cl_vnet' } ;
    }
    catch {
        if ($_.Exception.Response.StatusCode -ne "NotFound") {
            Write-Error $_.Exception.Message;
        }
    }

    if ($null -eq $vnet) {
        Write-Error "Cannot find virtual network in subscription";
        throw $_;
    }

    return $vnet;
}

<#
Get a SubNet from a virtual network by name
#>
function Get-SubNet {
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$Vnet,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubnetName
    )

    $vnetName = $Vnet.Name;

    try {
        Write-Host "Verifying subnet [$subnetName] exists in virtual network [$vnetName].";
        $subnet = $vnet.Subnets | where-object { $_.name -eq $subnetName }
    }
    catch {
        Write-Error $_.Exception.Message;
    }

    if ($null -eq $subnet) {
        Write-Error "Cant find subnet [$subnetName] in virtual network [$vnetName].";
        throw $_;
    }

    return $subnet;
}

<#
Create a new private endpoint for a storage account
#>
function New-StorageAccount-PrivateEndpoint {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount,
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]
        $Vnet,
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]
        $Subnet,
        [Parameter(Mandatory = $true)]
        [ValidateSet('file', 'blob', 'dfs', 'queue', 'table', 'web')]
        [string]$GroupId
    )
    
    # set up some values that are needed
    $rgName = $StorageAccount.ResourceGroupName;
    $pecName = "pec-$($StorageAccount.StorageAccountName)-$GroupId"; # added groupid becuase there will be multiple endpoints per type of storage being used in the SA
    $peName = "pe-$($StorageAccount.StorageAccountName)-$GroupId";

    try {
        $pe = (Get-AzPrivateEndpoint -Name $peName -ErrorAction SilentlyContinue);
        if ($pe -eq $NULL) {
            Write-Host "Creating private endpoint for storage account $($StorageAccount.StorageAccountName)";
            # Make Private endpoint connection
            $pec = New-AzPrivateLinkServiceConnection -Name $pecName -PrivateLinkServiceId $StorageAccount.Id -GroupId $GroupId;
            # Make Private endpoint
            $pe = New-AzPrivateEndpoint -Name $peName -ResourceGroupName $rgName -Location $Vnet.Location -Subnet $Subnet -PrivateLinkServiceConnection $pec;
        }
        else {
            Write-Host "Found existing Private Endpoint with the name [$peName].";
        }        
    }
    catch {
        Write-Error "An error has occured: $_";
    }

    if ($pe -eq $NULL) {
        Write-Error "Failed to create private endpoint [$peName] for storage account [$($StorageAccount.StorageAccountName)].";
        throw $_
    }
    
    return $pe;
}

<#
Create a new private DNS registration for a storage account private endpoint
#>
function New-PrivateDnsRegistration {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PrivateDnsZoneSubscriptionId,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PrivateDnsZoneResourceGroupName,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName,
        [Parameter(Mandatory = $true)]
        [ValidateSet('file', 'blob', 'dfs', 'queue', 'table', 'web')]
        [string]$StorageType,
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [Microsoft.Azure.Commands.Network.Models.PSPrivateEndpoint]$PrivateEndpoint
    )

    $dnsRecordSet = $NULL;
    $zoneName = "privatelink.$StorageType.core.windows.net";
    
    try {
        Set-AzContext -SubscriptionId $PrivateDnsZoneSubscriptionId | Out-Host;
        Write-Host "Verifying private DNS record set [$StorageAccountName] in private zone [$zoneName] in resource group [$PrivateDNSZoneResourceGroupName]."
        $dnsRecordSet = Get-AzPrivateDnsRecordSet -ResourceGroupName $privateDNSZoneResourceGroupName -ZoneName $zoneName  -RecordType A -Name $StorageAccountName -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "NotFound") {
            Write-Host "Existing DNS record not found";
        }
        else {
            Write-Error "Error while checking if private DNS record is present: $($_.Exception.Message)";
        }
    }

    if ($dnsRecordSet -eq $NULL) {
        try {
            Write-Host "Creating private DNS record set [$StorageAccountName] in private zone [$zoneName] in resource group [$PrivateDNSZoneResourceGroupName]."

            $privateEndpointCustomDnsConfig = $PrivateEndpoint.CustomDnsConfigs | Where-Object { $_.Fqdn -eq "$StorageAccountName.$StorageType.core.windows.net" }
            $privateDnsRecordConfig = New-AzPrivateDnsRecordConfig -IPv4Address $privateEndpointCustomDnsConfig.IpAddresses[0]

            $dnsRecordSet = New-AzPrivateDnsRecordSet -Name $StorageAccountName -RecordType A -ZoneName $zoneName -ResourceGroupName $privateDNSZoneResourceGroupName -Ttl 3600 -PrivateDnsRecords $privateDnsRecordConfig -ErrorAction Stop

            Write-Host "Private DNS record set [$StorageAccountName] in private zone [$zoneName] in resource group [$privateDNSZoneResourceGroupName] created."
        }
        catch {
            Write-Error "Error while creating private DNS record: $($_.Exception.Message)";
            throw $_;
        }
    }
    else {
        Write-Host "Private DNS record set [$StorageAccountName] in private zone [$zoneName] in resource group [$privateDNSZoneResourceGroupName] found.";
    }

    return $dnsRecordSet;
}

<#
Setup customer managed keys for storage account encryption
#>
function Set-StorageAccountEncryption {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
        [Parameter(Mandatory = $true)]
        [string]$KeyName
    )

    # Get Key Vault
    $keyVault = (Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue)
    if ($keyVault -eq $NULL) {
        Write-Error "Error while looking up key vault [$KeyVaultName]";
        throw "Missing key vault";
    }

    # Create a managed identity for the storage account
    Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -AssignIdentity | Out-Host;
    $account = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName;

    # Get key or make key if one does not exist
    $key = (Get-AzKeyVaultKey -VaultName $KeyVaultName -Name $KeyName -ErrorAction SilentlyContinue);
    if ($key -eq $NULL) {
        Write-Host "Key [$KeyName] not found in key vault [$KeyVaultName]. Creating new key.";
        $expiryDate = (Get-Date).AddYears(2)
        Write-Host "Key [$KeyName] being created will expire on [$expiryDate]."
        ## TODO: REMOVE IF WHEN TESTING IS COMPLETE
        if ($keyVault.Sku -eq 'Premium') {
            # HSM requires a premium sku key vault
            $key = Add-AzKeyVaultKey -VaultName $KeyVaultName -Name  $KeyName -Destination HSM -Expires $expiryDate -ErrorAction Stop;
        }
        else {
            $key = Add-AzKeyVaultKey -VaultName $KeyVaultName -Name  $KeyName -Destination Software -Expires $expiryDate -ErrorAction Stop;
        }
    }
    else {
        Write-Host "Found key [$KeyName] in key vault [$KeyVaultName]";
    }
    # Give storage account access to key
    Write-Host "Granting storage account [$StorageAccountName] access to keys in [$KeyVaultName]";
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ObjectId $account.Identity.PrincipalId -BypassObjectIdValidation -PermissionsToKeys wrapkey, unwrapkey, get | Out-Host;
    # Update storage account to use key for encryption
    Write-Host "Updating storage account [$StorageAccountName] to use [$KeyName] for encryption"
    Set-AzStorageAccount -ResourceGroupName $ResourceGroupName `
        -AccountName $StorageAccountName `
        -KeyvaultEncryption `
        -KeyName $key.Name `
        -KeyVersion $key.Version `
        -KeyVaultUri $keyVault.VaultUri | Out-Host;
}

<#
Sets tags for a specified resource
#>
function Set-ResourceTags {
    param (
        [Parameter(Mandatory = $true)]   
        [string]$ResourceId,
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceGroup]$ResourceGroup
    )
 
    $tags = @{};
    $ResourceGroup.Tags.Keys | ForEach-Object {
        if ($_ -eq 'ApplicationName' -or $_ -eq 'Env' -or $_ -eq 'ServiceType' -or $_ -eq 'BusinessUnit') {
            $tags.Add($_, $ResourceGroup.Tags[$_]);
        }
    };
 
    Update-AzTag -Operation Merge -ResourceId $ResourceId -Tag $tags | Out-Null;
}

<#
Creates or updates shares on storage account
#>
function Set-StorageShare {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$SaContext,
        [Parameter(Mandatory = $true)]
        [string]$ShareName,
        [Parameter(Mandatory = $true)]
        [int]$ShareQuota
    )
    try {
        Write-Host "Creating file share [$ShareName] on storage account [$($SaContext.StorageAccountName)]";
        $saShare = (Get-AzStorageShare -Name $ShareName -Context $SaContext -ErrorAction SilentlyContinue);
        if ($saShare -eq $NULL) {
            $saShare = New-AzStorageShare -Name $ShareName -Context $SaContext;
            Write-Host "Created file share [$ShareName]";
        }
        else {
            Write-Host "File share [$ShareName] already exists on storage account [$($SaContext.StorageAccountName)]";
        }
        if ($ShareQuota -gt 0 -and ($saShare.Quota -eq $NULL -or $saShare.Quota -ne $ShareQuota)) {
            Write-Host "Setting quota on file share [$ShareName] to [$ShareQuota]GB"
            $saShare = Set-AzStorageShareQuota -ShareName $ShareName -Quota $ShareQuota -Context $SaContext;
        }
    }
    catch {
        throw $_;
    }
}

<#
Creates or updates network access to storage account by network source
#>
function Set-NetworkRules {
    param (
        [string]$ResourceGroupName,
        [string]$StorageAccountName,
        [string]$AllowedNetworks
    )
    [Microsoft.Azure.Commands.Management.Storage.Models.PSVirtualNetworkRule[]]$networkRules = @();
    Write-Host "Setting network access rules for storage account [$StorageAccountName]";
    try {
        $hTable = ConvertTo-Hashtable $AllowedNetworks;
        $hTable.keys | ForEach-Object {
            $vnetName = $_;
            $vnet = Get-AzVirtualnetwork -ErrorAction Stop | where-object { $_.Name -eq $vnetName };
            $hTable[$vnetName] | ForEach-Object {
                $subnetName = $_;
                Write-Host "Creating rule for subnet [$subnetName] of vnet [$vnetName]";
                $subnet = $vnet.Subnets | where-object { $_.Name -eq $subnetName };
                Write-Verbose "Subnet Resource ID: $($subnet.Id)";
                $rule = New-Object Microsoft.Azure.Commands.Management.Storage.Models.PSVirtualNetworkRule;
                $rule.Action = 'Allow';
                $rule.VirtualNetworkResourceId = $subnet.Id;
                $networkRules += $rule;
            }
        }
        Write-Host "Applying rules...";
        Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $ResourceGroupName `
            -Name $StorageAccountName -Bypass 'AzureServices' -DefaultAction 'Deny' `
            -VirtualNetworkRule $networkRules -ErrorAction Stop | Out-Host;
    }
    catch {
        Write-Error "Error setting network access rules: $($_.Exception.Message)";
        throw $_;
    }
}

function ConvertTo-Hashtable {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Json
    )
    [hashtable]$hTable = @{}; 
    ($Json | ConvertFrom-Json).psobject.properties | ForEach-Object { $hTable.add($_.Name, $_.Value) }
    return $hTable;
}

<#
    Configure Soft Delete Policy
#>
function Set-SoftDeletePolicy {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceGroup]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        [Parameter(Mandatory = $false)]
        [int]$RetentionInDays = 14
    )
    try {
        # Get environment
        $env = $NULL;
        if ($NULL -ne $ResourceGroup.Tags["Env"]) {
            $env = $ResourceGroup.Tags["Env"];
        }
        else {            
            $env = $ResourceGroup.ResourceGroupName.Split('-')[2];
        }

        Write-Host "Setting soft delete policy on storage account [$StorageAccountName] in environment [$env]";
        # Apply differnt policy based on which environment the script is executing against
        switch ($env) {
            { $_ -in "cert", "prod", "dr" } { 
                Write-Host "Soft delete poilicy [ENABLED:$true  RETENTION DAYS:$RetentionInDays]";
                Update-AzStorageFileServiceProperty -ResourceGroupName $ResourceGroup.ResourceGroupName -AccountName $StorageAccountName `
                    -EnableShareDeleteRetentionPolicy $true -ShareRetentionDays $RetentionInDays -ErrorAction Stop | Out-Host;
            }
            { $_ -in "alpha", "btat2" } { 
                Write-Host "Soft delete poilicy [ENABLED:$false]";
                Update-AzStorageFileServiceProperty -ResourceGroupName $ResourceGroup.ResourceGroupName -AccountName $StorageAccountName `
                    -EnableShareDeleteRetentionPolicy $false -ErrorAction Stop | Out-Host;
            }
            Default { 
                throw "Environment policy not found.";
            }
        }
    }
    catch {
        Write-Error "Error while configuring soft delete policy: $($_.Exception.Message)"
        throw $_;
    }
}

<#
    Enable backup policy on storage account
#>
function Enable-BackupPolicy {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RecSvcVaultName,
        [Parameter(Mandatory = $true)]
        [string]$PolicyName,
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName
    )
    try {
        # Get ARSV
        $rsv = (Get-AzRecoveryServicesVault -ResourceGroupName $ResouceGroupName -Name $RecSvcVaultName -ErrorAction SilentlyContinue);
        if ($rsv -eq $NULL) {
            throw "Unable to retrieve Azure Recovery Services Vault";
        }
        # Get backup policy
        $policy = (Get-AzRecoveryServicesBackupProtectionPolicy -Name $PolicyName -VaultId $rsv.ID -ErrorAction SilentlyContinue);
        if ($rsv -eq $NULL) {
            throw "Unable to retrieve Azure Recovery Services backup protection policy";
        }
        # Enable policy on storage account
        Write-Host "Enabling backup policy [$PolicyName] from recovery services vault [$RecSvcVaultName] on storage account [$StorageAccountName]";
        Enable-AzRecoveryServicesBackupProtection -StorageAccountName $StorageAccountName -Name $StorageAccountName `
            -Policy $policy -VaultId $rsv.ID -ErrorAction Stop | Out-Host;
    }
    catch {
        Write-Error "Error while configuring backup policy: $($_.Exception.Message)"
        throw $_;
    }
}

<#
    Create directory under file share
#>
function Set-StorageDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$SaContext,
        [Parameter(Mandatory = $true)]
        [string]$ShareName,
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )
    try {
        Write-Verbose "Creating [$Directory] folder on the [$ShareName] share."
        New-AzStorageDirectory -ShareName $ShareName -Path "$Directory" -Context $SaContext -ErrorAction Stop | Out-Null;
    }
    catch {
        if ($_.Exception.RequestInformation.ErrorCode -ne "ResourceAlreadyExists") {
            throw $_;
        }
    }
}

######
## Uncomment login lines if you want to be prompted to login
## during script runtime.
######
# Login
# Connect-AzAccount;

# Set subscription
Set-AzContext -SubscriptionId $SubscriptionId | Out-Host;

# Try to find resource group
$resourceGroup = (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue);

if ($resourceGroup -eq $NULL) {
    # We could create the missing resource group if needed here but I think
    # in the context that this script will run its better that we don't
    Write-Error "Could not find resource group $ResourceGroupName";
    exit 265;
}
else {
    Write-Host "Found matching resource group: $ResourceGroupName";
}

$sa = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue);

if ($sa -eq $NULL) {
    # If a location was not provided use the resource group's location
    if ($Location -eq "" -or $Location -eq $NULL) {
        $Location = $resourceGroup.Location;
    }

    # Create storage account
    Write-Host "Creating a new storage account: $StorageAccountName";
    $sa = New-AzStorageAccount -Name $StorageAccountName -Kind $StorageAccountKind -SkuName $StorageAccountSku `
        -AccessTier $StorageAccountAccessTier -ResourceGroupName $ResourceGroupName -Location $Location;
    Write-Host "Done.";
}
else {
    Write-Host "Storage account with the same name already exists: $StorageAccountName";
}

# Set tags on storage account
Write-Host "Updating tags on [$StorageAccountName]";
Set-ResourceTags -ResourceId $sa.Id -ResourceGroup $resourceGroup;
Write-Host "Done.";

Write-Host "Setting up storage account encryption...";
if ($KeyName -eq $NULL -or $KeyName -eq '') {
    $KeyName = "${StorageAccountName}key-HSM";
}
# Enable Customer Managed keys for storage account encryption
Set-StorageAccountEncryption -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -KeyVaultName $KeyVaultName -KeyName $KeyName
Write-Host "Done.";

Write-Host "Setting up private endpoint and dns records...";
# Fetch virtual Network
$vnet = Get-VirtualNetwork;
# Fetch subnet
$subnet = Get-SubNet -Vnet $vnet -SubnetName $PrivateEndpointSubnetName;
# Create private file endpoint for storage account
$sape = New-StorageAccount-PrivateEndpoint -StorageAccount $sa -Vnet $vnet -Subnet $subnet -GroupId 'file';
# Register new private endpoint in private DNS Zone
$pdr = New-PrivateDnsRegistration -PrivateDnsZoneSubscriptionId $PrivateDnsSubscriptionId `
    -PrivateDnsZoneResourceGroupName $PrivateDnsResourceGroupName -StorageAccountName $sa.StorageAccountName `
    -StorageType 'file' -PrivateEndpoint $sape;
Write-Host "Done file endpoint.";

# switch back to original subscription from DNS subscription
Set-AzContext -SubscriptionId $SubscriptionId | Out-Host;

# Create private table endpoint for storage account
$sapeTable = New-StorageAccount-PrivateEndpoint -StorageAccount $sa -Vnet $vnet -Subnet $subnet -GroupId 'table';
# Register new table private endpoint in private DNS Zone
$pdrTable = New-PrivateDnsRegistration -PrivateDnsZoneSubscriptionId $PrivateDnsSubscriptionId `
    -PrivateDnsZoneResourceGroupName $PrivateDnsResourceGroupName -StorageAccountName $sa.StorageAccountName `
    -StorageType 'table' -PrivateEndpoint $sapeTable;
Write-Host "Done table endpoint.";

# switch back to original subscription from DNS subscription
Set-AzContext -SubscriptionId $SubscriptionId | Out-Host;

Write-Host "Setting Network Access Rules...";
# Restrict SA access to sources in the allowed networks
Set-NetworkRules -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -AllowedNetworks $AllowedNetworks;
Write-Host "Done.";

# Setting up file share has to be done after making the private endpoint
# otherwise you will get a '403 Forbidden' error.
# For some reason New-AzRmStorageShare does not have this limitation.
Write-Host "Setting up file shares...";
Set-StorageShare -SaContext $sa.Context -ShareName 'client' -ShareQuota $FileShareQuota;
Set-StorageShare -SaContext $sa.Context -ShareName 'axiom' -ShareQuota 25;

Set-SoftDeletePolicy -ResourceGroup $resourceGroup -StorageAccountName $sa.StorageAccountName;

# Skip applying backup policy if information is not provided
if (($RecSvcVaultName -ne $NULL -and $RecSvcVaultName -ne '') -and 
    ($AzFsBackupPolicy -ne $NULL -and $AzFsBackupPolicy -ne '')) {
    Enable-BackupPolicy -RecSvcVaultName $RecSvcVaultName -PolicyName $AzFsBackupPolicy -StorageAccountName $sa.StorageAccountName;
}

# setup directories under axiom file share
Set-StorageDirectory -SaContext $sa.Context -ShareName 'axiom' -Directory 'platform';
Set-StorageDirectory -SaContext $sa.Context -ShareName 'axiom' -Directory 'platform/common';
Set-StorageDirectory -SaContext $sa.Context -ShareName 'axiom' -Directory 'productpackage';
Set-StorageDirectory -SaContext $sa.Context -ShareName 'axiom' -Directory 'license';
Set-StorageDirectory -SaContext $sa.Context -ShareName 'axiom' -Directory 'samlidpmetadata';
Set-StorageDirectory -SaContext $sa.Context -ShareName 'axiom' -Directory 'database';

Write-Host "Done.";

# Get all storage keys  
$keys = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName;
# Get Specific storage key
# Write-Host "Storage Account Key1: $(($keys | Where-Object { $_.KeyName -eq 'key1'; }).Value)";
# Write-Host "Storage Account Key2: $(($keys | Where-Object { $_.KeyName -eq 'key2'; }).Value)";

# Return a key for use in Axiom tenant configuration
return ($keys | Where-Object { $_.KeyName -eq 'key2'; }).Value;
