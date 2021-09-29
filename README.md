# How to find IaaS VMs with SQL Server Installed
Script to query an Azure subscription to find all Virtual Machines, determine if SQL Server is installed on the Virtual Machine and if the IaaS extension is enabled.

## 1.  Execute PowerShell script to create helper functions
The script [GetAzureSQLVMStatus.ps1](./GetAzureSQLVMStatus.ps1 'GetAzureSQLVMStatus.ps1')  contains several functions to enable querying Virtual Machines in an Azure subscription.  This script will need to be executed in its entirety to create the necessary functions before performing the work.  You can open the script and hit F5 to run the whole script or you can open a new PowerShell script and include the functions.  

To execute the script file in a new PowerShell window, run the following:

````PowerShell
. .\GetAzureSQLVMStatus.ps1
````
## 2.  Call PowerShell functions to query Azure subscription to find Virtual Machines
### A.  Login to the Azure subscription that contains the Virtual Machines.
You'll need to ensure that your PowerShell session is connect to the Azure subscription that contains the Azure IaaS machines that you want to query.  To do this, execute the *[Connect-AzAccount](https://docs.microsoft.com/en-us/powershell/module/az.accounts/connect-azaccount?view=azps-6.4.0)* cmdlet.  You can supply the ID of the subscription that you wish to use if you have access to multiple subscriptions.  

````PowerShell
Connect-AzAccount -Subscription "3fdc92Xf-565a-49a6-bafd-f8a1X2bb9650"
````

### B.  Generate script to shell out to Virtual Machines
To run an external script against the Virtual Machines in Azure, we must first save a script locally to disk. This function call will save a .txt file locally to your C:\temp directory, or whatever you wish the file to be saved.  

````PowerShell
$ScriptPath = "c:\temp\GetServiceInfo.txt" 
create-SQLVMIaaSServiceScript -ServiceScriptPath $ScriptPath
````
### C.  Query Virtual Machines
This next function call will execute the script created in step B against a target set of Virtual Machines.  If you supply a Resource Group name as a parameter, the script will asynchronously shell out to every VM in that Resource Group and query it for SQL Services.  It will also identify if the IaaS extension is enabled on that VM.  You can also supply a single VM name in a Resource Group if there is a particular machine you want to query.  If you do not supply a Resource Group or Virtual Machine name as parameters, all VMs in the subscription will be queried for SQL instances. This may take a few moments to execute depending on the number of Virtual Machines you wish to execute this against.

````PowerShell
$VMArray = send-SQLVMIaaSExtensionData -ResourceGroupName "YourResourceGroupName" -ServiceScriptPath $ScriptPath
````
**Note:  These scripts will query the services on the Virtual Machine by executing *[Invoke-AzVMRunCommand](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/run-command)*, which requires the user connect to Azure and running the script to have the Virtual Machine Contributor role permissions.** 


### D.  Retreive Virtual Machine Status
Once the queries have been sent to the virtual machines, the next step is to retrieve the results.  Expect each call to the VM (from Step C above) to take roughly 10-20 seconds (this is how the cmdlet Invoke-AzVMRunCommand works), which is why it is important to run all of the queries in a multi-threaded fashion.  This function call will wait for the results to be returned from the Virtual Machines so the report can be generated.  A status bar will keep you updated with how much work has been done and how much is left.

````PowerShell
$VMArray = get-SQLVMIaaSExtensionData $VMArray
````

![Retrieve VM Data](https://github.com/timchapman/sql-iaas-extension-helpers/blob/main/media/1-RetreiveVMData.jpg)

### E.  Report on Virtual Machine Status
The last step of the process is to run a report off of the status of the Virtual Machines.  This call will return:
- Total Virtual Machine Count: how many VMs were queried
- VMs with SQL Server installed: how many VMs have the SQL Server service installed
- VMs with the SQL Iaas Extension enabled: how many VMs have the SQL IaaS Extension installed
- VMs with Named Instances of SQL: how many VMs have a named SQL Server service installed

````PowerShell
report-SQLVMIaaSExtensionData $VMArray
````

![VM Data Results.](media/2-VMDataResults.JPG 'VM Data Results')
