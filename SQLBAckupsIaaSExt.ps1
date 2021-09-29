#Requires -Module Az.Compute
#Requires -Module Az.Accounts
#Requires -Module Az.SqlVirtualMachine
#Requires -Module Az.Resources

function get-SQLVMList
(
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to retreieve list of VMs based on current subscription context.

.DESCRIPTION
    Function to retreieve list of VMs based on current subscription context.
    If the ResourceGroup is sent in without the VM name, will pull all VMs for that ResourceGroup.
    If ResourceGroup and VM name is sent in, will pull information regarding that single VM.
    If ResourceGroup and VM are omitted, pull all VMs for the current subscription.

.EXAMPLE
    $SQLVMs = get-SQLVMList -ResourceGroupName "YourResourceGroupName"

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group to pull VM information from.  
    Optional.  If omitted, will pull from all VMs in the current subscription context.

.PARAMETER VirtualMachineName
    The name of the Azure Virtual Machine to pull information from.  
    Optional. If passed in, the Resource Group is also required.

Produces an array of VM objects.
#>
    [Parameter(Position=0,mandatory=$false)]
        [string] $ResourceGroupName,
    [Parameter(Position=1,mandatory=$false)]
        [string] $VirtualMachineName
) {
    $SQLVMList = @()
    
    if($ResourceGroupName -or $VirtualMachineName)
    {
        $GetVMParams = @{}
        #Check to make sure the Resource Group exists if param sent in
        if($ResourceGroupName)
        {
            if(-not(Get-AzResourceGroup -Name $ResourceGroupName))
            {
                Write-Error "Resource Group does not exist."
                return
            }
            $GetVMParams.ResourceGroupName = $ResourceGroupName
        }
    
        #Check to make sure the VM exists if param sent in
        if($VirtualMachineName)
        {
            $GetVMParams.Name = $VirtualMachineName
            if(-not(Get-AzVm -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName))
            {
                Write-Error "Virtual Machine does not exist."
                return
            }
        }
    
        #Get VM info for a specific RG or specific VM based on params sent in
        $SQLVMList = Get-AzVm @GetVMParams
    }
    else  # no params sent in for RG or VM, so get everything for the subscription
    {
        $SQLVMList = Get-AzVm
    }
    return $SQLVMList
}

function enable-SQLVMAutoBackupSettings
{
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to enable a SQL VMs backups for the IaaS extension.

.DESCRIPTION
    Function to enable a SQL VMs backups for the IaaS extension.
    Assumes that the VM being passed in already has the IaaS extension enabled AND the VM has SQL Server installed on it.

.EXAMPLE
    $VMArray = send-SQLVMIaaSExtensionData -ResourceGroupName "timiaasext" -ServiceScriptPath $ScriptPath

.PARAMETER VirtualMachineName
    The name of the Azure Resource Group to pull VM information from.  
    Required.  If omitted, will pull from all VMs in the current subscription context.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group to pull VM information from.  
    Required.  If omitted, will pull from all VMs in the current subscription context.

.PARAMETER $AutomatedBackupConfigParams
    Configuration settings related to the SQL backups that are to be configured on the VM.
    This configuration hash table must contain a storage context to be used.
#>
    param
    (
        [Parameter(Position=0,mandatory=$true)]
            [string] $VirtualMachineName, 
        [Parameter(Position=1,mandatory=$true)]
            [string] $ResourceGroupName, 
        [Parameter(Position=2,mandatory=$true)]
            [object]$AutomatedBackupConfigParams
    )

        if($SQLVM = Get-AzSQLVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName -ErrorAction Ignore)
        {
            if($SQLVM.SqlManagementType -ne "Full")
            {
                Write-Error "Cannot update because VM is using the lightweight version of the IaaS Extension."
                return
            }
            $LocalVMList += $SQLVM
        }else
        {
            Write-Error "Cannot update because VM is not a SQLVM."
            return
        }            

        $BackupConfig = New-AzVMSqlServerAutoBackupConfig @AutomatedBackupConfigParams

        Set-AzVMSqlServerExtension -AutoBackupSettings $BackupConfig -VMName $SQLVM.Name -ResourceGroupName $SQLVM.ResourceGroupName           
}




function get-BackupStorageAccountContext
{
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to retreieve the storage account context for an Azure Storage Account.

.DESCRIPTION
    Function to retreieve the storage account context for an Azure Storage Account.
    If Storage Account does not exist, this function will create the Storage Account with the Standard_GRS SKU.
    This storage account will be used to storage backups from SQL Server on IaaS.

.EXAMPLE
    $StorageContext = get-BackupStorageAccountContext -ResourceGroupName "YourRGName" -StorageAccountRegion "eastus" -BackupStorageAccountName "someuniquestorageaccountname"

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group where the Storage Account exists or where the Storage Account will be located. 
    Required parameter.

.PARAMETER StorageAccountRegion
    The Azure region where the Storage Account exists or where the Storage Account will be located. 
    Optional, but required if the Storage Account is to be created.

.PARAMETER BackupStorageAccountName
    The name of the Storage Account where the SQL backups will be stored.
    Required.
#>
    param
    (
        [Parameter(Position=0,mandatory=$true)]
            [string]$ResourceGroupName,
        [Parameter(Position=1,mandatory=$false)]
            [string]$StorageAccountRegion,
        [Parameter(Position=2,mandatory=$true)]
            [string]$BackupStorageAccountName
    )

    #storage acocunts only allow for lowercase letters.
    $BackupStorageAccountName = $BackupStorageAccountName.tolower()

    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $BackupStorageAccountName -ErrorAction SilentlyContinue

    If(-Not $StorageAccount)
    { 
        if($StorageAccountRegion)
        {
            write-host "Creating New Storage Account $BackupStorageAccountName in Resource Group $ResourceGroupName." -BackgroundColor Green
            $StorageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $BackupStorageAccountName -SkuName Standard_GRS -Location $StorageAccountRegion 
        }
        else 
        {
            Write-Error "Must provide the region for the storage account to be created"
            return  
        }
    }

    return $StorageAccount.Context
}









    $SQLVMs = get-SQLVMList
    foreach($SQLVM in $SQLVMs)
    {
        enable-SQLVMAutoBackupSettings -ResourceGroupName "timiaasext" -VirtualMachineName "vm3" -AutomatedBackupConfigParams $BackupParams
    }



    $SQLVMs = get-SQLVMList -ResourceGroupName "TimIaasExt"
    $StorageContext = get-BackupStorageAccountContext -ResourceGroupName "TimIaasExt" -StorageAccountRegion "eastus" -BackupStorageAccountName "timchapSQLBackups"
    $BackupParams = @{}
    $BackupParams.Enable = $true
    $BackupParams.RetentionPeriodInDays = 10 
    $BackupParams.StorageContext = $StorageContext
    $BackupParams.ResourceGroupName = "timiaasext" 
    $BackupParams.BackupSystemDbs = $true
    $BackupParams.BackupScheduleType = "Manual"
    $BackupParams.FullBackupFrequency = "Daily"
    $BackupParams.FullBackupStartHour = 16 
    $BackupParams.FullBackupWindowInHours = 2
    $BackupParams.LogBackupFrequencyInMinutes = 10 

    enable-SQLVMAutoBackupSettings -ResourceGroupName "timiaasext" -VirtualMachineName "vm3" -AutomatedBackupConfigParams $BackupParams