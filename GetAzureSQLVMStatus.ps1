#Requires -Module Az.Compute
#Requires -Module Az.Accounts
#Requires -Module Az.SqlVirtualMachine
#Requires -Module Az.Resources

function create-SQLVMIaaSServiceScript
{
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to create PS script file to shell out to IaaS VMs to interrogage SQL Services on machine.

.DESCRIPTION
    Function to create PS script file to shell out to IaaS VMs to interrogage SQL Services on machine.
    Has a default path to the C:\temp folder

.EXAMPLE
    $ScriptPath = "c:\temp\GetServiceInfo.txt" 
    create-SQLVMIaaSServiceScript -ServiceScriptPath $ScriptPath

.PARAMETER $ServiceScriptPath
The path to the script file.  Base folder must exist.  Will create or overwrite existing file with new contents if it exists.

#>
    Param
    (
        [Parameter(Position=0,Mandatory=$false)]
            [string]$ServiceScriptPath = "c:\temp\GetSQLService.txt"
    )
    
    #script contents to pull SQL service data from VM
    $ServiceScript = @'
$ComputeName = $env:computername
$Domain = $env:userdnsdomain
$SQLService = get-service mssqlserver, mssql$* -ErrorAction Ignore
$out = @{}
$out.ComputerName = $ComputeName
$out.SQLStatus = $SQLService.Status.ToString()
$out.ServiceName = $SQLService.Name.ToString()
$out.Domain = $Domain
$out|ConvertTo-Json
'@

    if(-not(Test-Path $ServiceScriptPath))
    {
        if($ServiceScriptPath -cmatch '\.[^.]+$')
        {
            #path contains a file, so need to create folder path if it isn't there, then create file.
            $FileName = Split-Path $ServiceScriptPath -Leaf
        }
        else
        {
            #parent path does not exist
            #dont mess with creating the path
            Write-Error "Folder Path does not exist."
            return
        }

    }

    #file exists, lets update it
    Set-Content -Path $ServiceScriptPath -Value $ServiceScript
}

function send-SQLVMIaaSExtensionData
{
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to to shell out to IaaS VMs to interrogage SQL Services on machine.

.DESCRIPTION
    Function to to shell out to IaaS VMs to interrogage SQL Services on machine.
    Creates background sessions jobs asynchronously which will query the services on the Virtual Machines
    to find the SQL Server Service.
    Requires an active Azure context.  If one is not currently established, will require you to log into your 
    Azure subscription.

.EXAMPLE
    $VMArray = send-SQLVMIaaSExtensionData -ResourceGroupName "timiaasext" -ServiceScriptPath $ScriptPath

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group to pull VM information from.  
    Optional.  If omitted, will pull from all VMs in the current subscription context.

.PARAMETER VirtualMachineName
    The name of the Azure Virtual Machine to pull information from.  
    Optional. If passed in, the Resource Group is also required.

.PARAMETER ServiceScriptPath
    The file path the script to pull Services information from.
    Required. Script path validity is checked.  
    File is created in a call to create-SQLVMIaaSServiceScript

Produces an array of dictionary objects that represent the VMs that have been sent queries.
#>

    Param
    (
        [Parameter(Position=0,mandatory=$false)]
            [string]$ResourceGroupName,

        [Parameter(Position=1,mandatory=$false)]
            [string]$VirtualMachineName, 

        [Parameter(Position=2,Mandatory=$true)]
        [ValidateScript({
        if( -Not ($_ | Test-Path) ){
            throw "File path $_ does not exist."
        }
            return $true
        })]
            [string]$ServiceScriptPath
    )

    if(-not(Get-AzContext))
    {
        Connect-AzAccount
    }

    if($ResourceGroupName -or $VirtualMachineName)
    {
        $GetVMParams = @{}
        #Check to make sure the Resource Group exists if param sent in
        if($ResourceGroupName)
        {
            if(-not(Get-AzResourceGroup -Name $ResourceGroupName))
            {
                Write-Error "Resource Group does not exist in the current Azure subscription."
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
        $VMList = Get-AzVm @GetVMParams
    }
    else  # no params sent in for RG or VM, so get everything for the subscription
    {
        $VMList = Get-AzVm
    }

    $VMArray = New-Object -TypeName "System.Collections.ArrayList"
    
    #Clear out any existing session jobs - allows to restart command each time from a clean slate
    Get-Job|Remove-Job

    #Loop through the VM(s)
    #Only look for Windows machines
    foreach($VM in $VMList)
    {

        if($VM.OSProfile.WindowsConfiguration)
        {
            $OsType = "Windows"
        }
        else
        {
            $OsType = "Linux"
        }

        $VMDict = @{}
        $VMDict.ComputerName = $VM.Name
        $VMDict.ResourceGroup = $VM.ResourceGroupName
        $VMDict.OSType = $OsType
        $VMDict.VMSize = $VM.VMSize
        $VMDict.JobStatus = $null
        $VMDict.ServiceDetails = $null

        if($VM.Extensions.ID|Where-Object {$_ -like "*SQLIaasExtension*"})
        {
            $VMDict.SQLIaaSExtFoundOnVMProfile = $true
        }
        else
        {
            $VMDict.SQLIaaSExtFoundOnVMProfile = $false
        }

        #Shell out a call to the windows machine to get SQL Service info
        #Jobs run async, so will need to gather them later to get results
        #Use JobInfo and JobId properties to keep track of what has been collected
        if($OsType -eq "Windows")
        {
            $JobInfo = Invoke-AzVMRunCommand -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -CommandId 'RunPowerShellScript' -ScriptPath $ServiceScriptPath -AsJob
            $VMDict.JobInfo = $JobInfo
            $VMDict.JobId = $JobInfo.Id
        }
        $VMArray += $VMDict
    }
    return $VMArray
}
 
function get-SQLVMIaaSExtensionData
{
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to retrieve background jobs from the call to send-SQLVMIaaSExtensionData.

.DESCRIPTION
    Function to retrieve background jobs from the call to send-SQLVMIaaSExtensionData.  
    There will be several background session jobs that are to be collected and reported on.

.EXAMPLE
    $VMArray = get-SQLVMIaaSExtensionData $VMArray

.PARAMETER $VMArray
    Array of dictionary objects from send-SQLVMIaaSExtensionData

Produces an updated array of dictionary objects with job retreival status.
#>
    Param
    (
    [Parameter(Position=0,mandatory=$true)]
        [hashtable[]]$VMArray
    )

    $JobCount = (Get-Job).count
    $JobsReceived = 0
    while($Jobs = Get-Job)
    {
        Write-Progress -Activity "Retrieving Virtual Machine Information" -Status "Received $JobsReceived of $JobCount Virtual Machines." -PercentComplete (($JobsReceived/$JobCount)*100)
        foreach($Job in $Jobs)
        {
            $Jobid = $Job.id
            if($Job.State -eq "Completed")
            {
                $JobOut= Receive-Job -id $Jobid
                $JobsReceived += 1

                #retrieve job information - this is a call to get-service on the machine
                $JobOut = [pscustomobject]$JobOut.Value[0].Message|ConvertFrom-Json

                #set properties in dictionary from job call
                ($VMArray|Where-Object{$_.JobId -eq $Jobid}).ServiceDetails = $JobOut
                ($VMArray|Where-Object{$_.JobId -eq $Jobid}).JobStatus = "Success"

                #remove the job from the current session.  We have collected the info we need.
                Remove-Job -Id $Job.id
            }
            elseif($Job.State -eq "Failed")
            {
                Remove-Job -id $Job.id
                ($VMArray|Where-Object{$_.JobId -eq $Jobid}).JobStatus = "Failure"
            }
        }
        Start-Sleep -Seconds 1
    }
    return $VMArray
}


function report-SQLVMIaaSExtensionData
{
<#
Written by:  Tim Chapman, Microsoft  09/2021
.SYNOPSIS
    Function to report on VM information from previous function calls.

.DESCRIPTION
    Function to report on VM information from previous function calls.
    Will return the total number of virtual machines queried, VMs with SQL installed, 
    VMs using the IaaS extension and VMs containing named instances.

.EXAMPLE
    report-SQLVMIaaSExtensionData $VMArray

.PARAMETER $VMArray
    Array of dictionary objects from get-SQLVMIaaSExtensionData

#>
    Param
    (
        [hashtable[]]$VMArray
    )

        $TotalVMCount = $VMArray.Count
        $SQLInstalledCount = 0
        $IaaSExtInstalledCount = 0
        $NamedInstanceCount = 0

        foreach($Row in $VMArray)
        {

            if($Row.ServiceDetails.ServiceName -gt "")
            {
                $SQLInstalledCount += 1
            }

            if($Row.ServiceDetails.ServiceName -like "*$*")
            {
                $NamedInstanceCount += 1
            }

            if($Row.SQLIaaSExtFoundOnVMProfile)
            {
                $IaaSExtInstalledCount += 1
            }
        }

        "Total Virtual Machine Count: $TotalVMCount"
        "VMs with SQL Server installed: $SQLInstalledCount"
        "VMs with the SQL Iaas Extension: $IaaSExtInstalledCount"
        "VMs with Named Instances of SQL: $NamedInstanceCount"
} 

<#
Login-AzAccount
$ScriptPath = "c:\temp\GetServiceInfo.txt" 
create-SQLVMIaaSServiceScript -ServiceScriptPath $ScriptPath
$VMArray = send-SQLVMIaaSExtensionData -ResourceGroupName "timiaasext" -ServiceScriptPath $ScriptPath
$VMArray = get-SQLVMIaaSExtensionData $VMArray
report-SQLVMIaaSExtensionData $VMArray
#>
