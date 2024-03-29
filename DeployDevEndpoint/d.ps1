Param(
    [Parameter(HelpMessage = "Tenants to install the app in", Mandatory = $true)]
    [string[]] $tenants,
    [Parameter(HelpMessage = "Environment to publish the app in", Mandatory = $true)]
    [ValidateSet('T','A')]
    [string[]] $environments,
    [Parameter(HelpMessage = "The Artifcats folder", Mandatory = $true)]
    [string] $repoName,
    [Parameter(HelpMessage = "The Azure Container SAS", Mandatory = $true)]
    [string] $azureContainerSAS
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$environmentsArray = $environments.Split(",");

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\Github-Helper.ps1" -Resolve)

foreach ($deployEnvironment in $environmentsArray) {
    Write-Host "Deploying to $deployEnvironment Environment"
        
    switch ($deployEnvironment)
    {
        "T" #TODO
        {
            $devEndpointUri = "http:\\EIN-PEDR02-L10" 
            $devPort = 7049 
            $instanceName = "BC190"
        }
        "A" #TODO
        {
            $devEndpointUri = "http:\\EIN-PEDR02-L10" 
            $devPort = 7049 
            $instanceName = "BC190"
        }
    }      

    Write-Host "Deploying to Instance: $serverInstance"    
    write-Host "Deploying artifacts from folder: $artifacts"    

    $apps = @()
    $testApps = @()

    $apps
    if (Test-Path $artifacts) {
        $apps = @((Get-ChildItem -Path $artifacts) | ForEach-Object { $_.FullName })
        if (!($apps)) {
            throw "There are no artifacts present in $artifacts."
        }
    }
    else {
        throw "Artifact $artifacts was not found. Make sure that the artifact files exist and files are not corrupted."
    }

    $testApps
    if (Test-Path "$artifacts\Tests") {
        $testApps = @((Get-ChildItem -Path $artifacts) | ForEach-Object { $_.FullName })
        if (!($testApps)) {
            throw "There are no test artifacts present in $artifacts."
        }
    }
    
    Write-Host "ServiceInstance is set to $serverInstance"

    Import-Module "$($serviceFolder)\Microsoft.Dynamics.Nav.Apps.Management.dll" -Scope Global -Verbose:$false
    Import-Module "$($serviceFolder)\Microsoft.Dynamics.Nav.Management.dll" -Scope Global -Verbose:$false
    Import-module "$($serviceFolder)\Microsoft.Dynamics.Nav.Model.Tools.dll" -Scope Global -Verbose:$false
    Import-Module "$($serviceFolder)\Microsoft.Dynamics.Nav.Apps.Tools.dll" -Scope Global -Verbose:$false
    Import-Module "$($serviceFolder)\NavAdminTool.ps1" -WarningAction SilentlyContinue | Out-Null

    $apps | ForEach-Object {
        try {
            Write-Host "File found: $_"
            PublishAndInstallApp($_, $tenants)
        }
        catch {            
            Write-Host $_.Exception.Message
        }     
    }

    $testApps | ForEach-Object {
        try {
            Write-Host "File found: $_"
            PublishAndInstallApp($_, $tenants)            
        }
        catch {            
            Write-Host $_.Exception.Message
        }     
    }
}