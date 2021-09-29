


set-location D:\GitHub\sql-iaas-extension-helpers

. .\GetAzureSQLVMStatus.ps1




$ScriptPath = "c:\temp\GetServiceInfo.txt" 
create-SQLVMIaaSServiceScript -ServiceScriptPath $ScriptPath



$VMArray = send-SQLVMIaaSExtensionData -ResourceGroupName "timiaasext" -ServiceScriptPath $ScriptPath
$VMArray = get-SQLVMIaaSExtensionData $VMArray
report-SQLVMIaaSExtensionData $VMArray


