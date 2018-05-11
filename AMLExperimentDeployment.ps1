	<#
	.NOTES
		==============================================================================================
		Copyright(c) Microsoft Corporation. All rights reserved.
				
		File:		AMLExperimentDeployment.ps1
		
		Purpose:	Azure Machine Learning - Azure Deployment Automation Script
		
		Version: 	1.0.0.4 - 12th October 2017 - Release Deployment Team
		==============================================================================================

	.SYNOPSIS
		Azure Machine Learning - Azure Deployment Automation Script
	
	.DESCRIPTION
		Azure Machine Learning - Azure Deployment Automation Script
				
		Deployment steps of the script are outlined below.
		1) Import Module AzureMLPS.dll (Machine Learning DLL)
		2) Load Parameters "templateParametersfile"
		3) Configure Azure Machine Learning
				    
	.PARAMETER executionPath 
        Specify the execution Path 
        	
	.PARAMETER mlwName
		Specify the MLW Name

	.PARAMETER mlwTargetName
		Specify the MLW Target Name
	
	.PARAMETER env 
        Specify the environment name like dev, prod, uat'   

	.PARAMETER templateFilePath
		Specify the location of template file

	.EXAMPLE
		Default:
        C:\PS> AMLExperimentDeployment.ps1 -executionPath <"executionPath"> `
				-mlwName <"mlwName"> `
				-mlwTargetName <"mlwTargetName"> `
				-expName <"expName "> `
				-env <"env"> `
				-templateFilePath <"templateFilePath">            
#>

#region - Global Variables
param
(
	[Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$executionPath = "C:\AML",
	[Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$mlwName = "{Source AML workspace name}",
	[Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$mlwTargetName = "{Target AML workspace name}",
	[Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$env = "{environment identifier for template file path}",
	[Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$templateFilePath = "C:\AML\Templates\",
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$mlwSubscriptionId = "{source subscription id}",
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$targetmlwSubscriptionId = "{target subscription id}",
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$ClientId = "{client id of azure spn}",
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$resourceAppIdURI = "{app id uri of azure spn}",
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$TenantId = "{tenant id of azure ad}",
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
	[string]$ClientKey = "{client secret of azure spn}"
)

$secpasswd = ConvertTo-SecureString $ClientKey -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($ClientId, $secpasswd)
Login-AzureRmAccount -ServicePrincipal -Tenant $TenantId -Credential $mycreds  -SubscriptionId $targetmlwSubscriptionId

Set-Location -Path $executionPath
Unblock-File .\AzureMLPS.dll
Import-Module .\AzureMLPS.dll
#endregion

#region - Functions
<#
 ==============================================================================================	 
	Script Functions
		GetWebServiceDetails					- Gets Web Serice configuration			
 ==============================================================================================	
#>
function GetWebServiceDetails
{
	[CmdletBinding()]
	param
	(
		[string]$webServiceName
	)
	
	$webSvc = Get-AmlWebService | Where-Object Name -eq $webServiceName
	if ($webSvc -ne $null)
	{
		$templateParametersFile = "$templateFilePath" + "ADF.Parameters_$env.json"
		$templateParameters = Get-Content -Path $templateParametersFile -Raw | ConvertFrom-JSON
		
		$endpoints = Get-AmlWebServiceEndpoint -WebServiceId $webSvc.Id
		Write-Output $webServiceName
		$primaryKey = $endpoints.PrimaryKey
		Write-Output $primaryKey
		($templateParameters.parameters.amlConfiguration | Where-Object { $PSItem.amlName -eq $webServiceName }).amlApiKey.value = $primaryKey
		
		$apiEndpoint = $endpoints.ApiLocation + "/jobs?api-version=2.0"
		Write-Output $apiEndpoint
		($templateParameters.parameters.amlConfiguration | Where-Object { $PSItem.amlName -eq $webServiceName }).amlEndPoint.value = $apiEndpoint

		$templateParameters | ConvertTo-Json -Depth 4 | set-content $templateParametersFile
	}
	else
	{
		throw "Web Service does not exist or cannot be reached!"
	}
}
#endregion

#region - Control Routine

#region - Load Parameters
$templateParametersFile = "$templateFilePath" + "ADF.Parameters_$env.json"
$templateParameters = Get-Content -Path $templateParametersFile -Raw | ConvertFrom-JSON

$serverName = $templateParameters.parameters.datahubSqlServerName.value + ".database.windows.net"
$dbName = $templateParameters.parameters.datahubDatabaseName.value
$userName = $templateParameters.parameters.datahubSqlServerAdminLogin.value

$amlNamesFilePath = "$templateFilePath" + "AMLExperiments.json"
$amlNames = Get-Content -Path $amlNamesFilePath -Raw | ConvertFrom-JSON
[bool]$flag = $false

if (-not $templateParameters)
{
	throw "ERROR: Unable to retrieve ADP Template parameters file. Terminating the script unsuccessfully."
}

if (-not $amlNames)
{
	throw "ERROR: Unable to retrieve AML Names file. Terminating the script unsuccessfully."
}
#endregion

#region - Azure Machine Learning Configuration - Experiments
$expNames = @()
foreach ($exp in $amlNames.AMLExperiments)
{
	$expNames += $exp.EXP_name
}

foreach ($expName in $expNames)
{
	$script:flag = $false
	$wspTarget = Get-AzureRmResource | Where-Object { $PSItem.Name -Like $mlwTargetName }
	$widTarget = (Get-AzureRmResource -Name $wspTarget.Name -ResourceGroupName $wspTarget.ResourceGroupName -ResourceType $wspTarget.ResourceType -ApiVersion 2016-04-01).Properties.workspaceId
	$wptTarget = (Invoke-AzureRmResourceAction -ResourceId $wspTarget.ResourceId -Action listworkspacekeys -Force).primaryToken
	$wilTarget = (Get-AzureRmResource -Name $wspTarget.Name -ResourceGroupName $wspTarget.ResourceGroupName -ResourceType $wspTarget.ResourceType -ApiVersion 2016-04-01).Location
	 
	(New-Object psobject | Add-Member -PassThru NoteProperty Location $wilTarget | Add-Member -PassThru NoteProperty WorkspaceId $widTarget | Add-Member -PassThru NoteProperty AuthorizationToken $wptTarget) | ConvertTo-Json > config.json
	Get-Content ".\config.json"
	
	$exp = Get-AmlExperiment | Where-Object Description -eq $expName
	if ($exp -ne $null)
	{
		if ($exp.Status.StatusCode.ToString() -eq "Finished")
		{
			Write-Output "Experiment already exist and is in finished state. Getting service details now"
			GetWebServiceDetails $expName
			continue
		}
	}
	
    $secpasswd = ConvertTo-SecureString $ClientKey -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($ClientId, $secpasswd)
    Login-AzureRmAccount -ServicePrincipal -Tenant $TenantId -Credential $mycreds -SubscriptionId $mlwSubscriptionId

	$wsp = Get-AzureRmResource | Where-Object { $PSItem.Name -Like $mlwName }
	$wid = (Get-AzureRmResource -Name $wsp.Name -ResourceGroupName $wsp.ResourceGroupName -ResourceType $wsp.ResourceType -ApiVersion 2016-04-01).Properties.workspaceId
	$wpt = (Invoke-AzureRmResourceAction -ResourceId $wsp.ResourceId -Action listworkspacekeys -Force).primaryToken
	$wil = (Get-AzureRmResource -Name $wsp.Name -ResourceGroupName $wsp.ResourceGroupName -ResourceType $wsp.ResourceType -ApiVersion 2016-04-01).Location
	(New-Object psobject | Add-Member -PassThru NoteProperty Location $wil | Add-Member -PassThru NoteProperty WorkspaceId $wid | Add-Member -PassThru NoteProperty AuthorizationToken $wpt) | ConvertTo-Json > config.json
	Get-Content ".\config.json"
	
	$experiment = Get-AmlExperiment | Where-Object Description -eq $expName
	Write-Output $experiment
	
	Copy-AmlExperiment -ExperimentId $experiment.ExperimentId -DestinationWorkspaceId $widTarget -DestinationWorkspaceAuthorizationToken $wptTarget

    $secpasswd = ConvertTo-SecureString $ClientKey -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($ClientId, $secpasswd)
    Login-AzureRmAccount -ServicePrincipal -Tenant $TenantId -Credential $mycreds  -SubscriptionId $targetmlwSubscriptionId

	(New-Object psobject | Add-Member -PassThru NoteProperty Location $wilTarget | Add-Member -PassThru NoteProperty WorkspaceId $widTarget | Add-Member -PassThru NoteProperty AuthorizationToken $wptTarget) | ConvertTo-Json > config.json
	Get-Content ".\config.json"
		
	$expTarget = Get-AmlExperiment | Where-Object Description -eq $expName
	Write-Output $expTarget
	
	$outputFilePath = $executionPath + "\ExportedExperimentGraphs\" + $expTarget.Description.ToString() + ".json"
	Export-AmlExperimentGraph -ExperimentId $expTarget.ExperimentId -OutputFile $outputFilePath
	$json = Get-Content -LiteralPath $outputFilePath -Raw | ConvertFrom-Json
	$nodes = $json.Graph.ModuleNodes | Where-Object { $PSItem.Comment -eq "azuresql" }
	
	foreach ($node in $nodes)
	{
		($node.ModuleParameters | Where-Object { $PSItem.Name -eq "Database Server Name" }).Value = $serverName
		($node.ModuleParameters | Where-Object { $PSItem.Name -eq "Database Name" }).Value = $dbName
		($node.ModuleParameters | Where-Object { $PSItem.Name -eq "Server User Account Name" }).Value = $userName
	}
	
	$json | ConvertTo-Json -Depth 5 | set-content -LiteralPath $outputFilePath
	
	Remove-AmlExperiment -ExperimentId $expTarget.ExperimentId
	
	Import-AmlExperimentGraph -InputFile $outputFilePath -NewName $expName
	
	# LOGIC to loop through for 5 minutes checking every 10 seconds by downloading experiment graph to see if all nodes of azure sql have the password updated or is it still null
	
	$timeout = new-timespan -Minutes 5
	$sw = [diagnostics.stopwatch]::StartNew()
	
	:outer
	while ($sw.elapsed -lt $timeout)
	{
		Write-Output "Please update SQL DB Connection password for all Input / Output nodes in AML workspace against the experiment $expName"
		$expTarget = Get-AmlExperiment | Where-Object Description -eq $expName
		Write-Output $expTarget
		
		$outputFilePath = $executionPath + "\ExportedExperimentGraphs\" + $expTarget.Description.ToString() + ".json"
		Export-AmlExperimentGraph -ExperimentId $expTarget.ExperimentId -OutputFile $outputFilePath
		
		$json = Get-Content -LiteralPath $outputFilePath -Raw | ConvertFrom-Json
		$nodes = $json.Graph.ModuleNodes | Where-Object { $PSItem.Comment -eq "azuresql" }
		
		:inner
		foreach ($node in $nodes)
		{
			$pass = $node.ModuleParameters | Where-Object { $PSItem.Name -eq "Server User Account Password" }
			if ($pass.Value -eq $null)
			{
				$script:flag = $false
				Write-Output "Please update SQL DB Connection password for all Input / Output nodes in AML workspace against the experiment $expName"
				break inner
			}
			else
			{
				$script:flag = $true
			}
		}
		
		if ($script:flag -eq $true)
		{
			break outer
		}
		else
		{
			start-sleep -seconds 10
		}
	}
	
	Write-Output "Passwords updated"
	if ($flag -eq $false)
	{
		Write-Output "Time's up!"
		throw "Password was not updated in Azure portal, exiting!"
	}
	
	Write-Output "Starting experiment run!"
	$expTarget = Get-AmlExperiment | Where-Object Description -eq $expName
	Start-AmlExperiment -ExperimentId $expTarget.ExperimentId
	
	$exp = Get-AmlExperiment | Where-Object Description -eq $expName
	if ($exp -ne $null)
	{
		if ($exp.Status.StatusCode.ToString() -eq "Failed")
		{
			throw "Experiment test run failed, exiting now!"
		}
	}
	
	$webService = New-AmlWebService -PredictiveExperimentId $expTarget.ExperimentId
	$webService
	GetWebServiceDetails $expName
}
#endregion

#endregion