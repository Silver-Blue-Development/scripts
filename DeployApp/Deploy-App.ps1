Param(
    [Parameter(HelpMessage = "Tenants to install the app in", Mandatory = $true)]
    [string[]] $tenants,
    [Parameter(HelpMessage = "Environment to publish the app in", Mandatory = $true)]
    [ValidateSet('O','T','A')]
    [string[]] $environments,
    [Parameter(HelpMessage = "The Artifcats folder", Mandatory = $true)]
    [string] $repoName,
    [Parameter(HelpMessage = "The Azure Container SAS", Mandatory = $true)]
    [string] $azureContainerSAS
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$environmentsArray = $environments.Split(",");
$tenantsarray= $tenants.Split(",")

foreach ($deployEnvironment in $environmentsArray) {
    Write-Host "Deploying to $deployEnvironment Environment"
        
    switch ($deployEnvironment)
    {
        "O" 
        {    
            $serviceFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\190\Service"
            $serverInstance = "ONTW" #TODO Set correct instance  
            $artifacts = "C:\Artifacts\Development\$repoName"
        }
        "T" 
        {
            $serviceFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\190\Service"
            $serverInstance = "BC190" #TODO Set correct instance
            $artifacts = "C:\Artifacts\Development\$repoName"
        }
        "A" 
        {
            $serviceFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\190\Service"
            $serverInstance = "BC190" #TODO Set correct instance 
            $artifacts = "C:\Artifacts\Acceptance\$repoName"
        }
    }      

    Write-Host "Deploying to Instance: $serverInstance"    
    write-Host "Deploying artifacts from folder: $artifacts"    

    $apps = @()

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
            PublishAndInstallApp($_)
        }
        catch {            
            Write-Host $_.Exception.Message
        }     
    }

    $testApps | ForEach-Object {
        try {
            Write-Host "File found: $_"
            PublishAndInstallApp($_)            
        }
        catch {            
            Write-Host $_.Exception.Message
        }     
    }

    function PublishAndInstallApp {
        param (
            $theApp
        )    
        foreach ($file in Get-ChildItem $_)
        {
            Write-Host "Deploying $file"

            $AppInfo = Get-NAVAppInfo -Path $file -Verbose:$false
            Write-Host "-App.ID = $($AppInfo.AppId)" 
            Write-Host "-App.Name = $($AppInfo.Name)"
            Write-Host "-App.Publisher = $($AppInfo.Publisher)"
            Write-Host "-App.Version = $($AppInfo.Version)"

            foreach ($installTenant in $tenantsarray) {   

                Get-NAVAppInfo -ServerInstance $serverInstance -Tenant $installTenant -Name $AppInfo.Name -Publisher $AppInfo.Publisher -TenantSpecificProperties | 
                    ForEach-Object -Process { 
                        if ($_.Version -ne $AppInfo.Version)
                        {
                            Write-Host "Attempting to uninstall app $($_.Name) with version: $($_.Version)"
                            Uninstall-NAVApp -ServerInstance $serverInstance -Tenant $installTenant -Name $_.Name -Version $_.Version -Force
                            Write-Host "App $($_.Name) with version $($_.Version) was uninstalled from tenant $installTenant"
                        }
                    }

                Publish-NAVApp -ServerInstance $serverInstance -Path $file -SkipVerification
                Write-Host "App $($AppInfo.Name) was published to $serverInstance"
                Sync-NAVApp -ServerInstance $serverInstance -Tenant $installTenant -Name $AppInfo.Name -Version $AppInfo.Version 
                Write-Host "App $($AppInfo.Name) was Synced to $serverInstance Tenant $installTenant"

                Write-Host "Installing app on tenant $installTenant"   
                try {
                    Start-NAVAppDataUpgrade -ServerInstance $serverInstance -Name $AppInfo.Name -Version $AppInfo.Version -Tenant $installTenant         
                    Write-Host "Data upgrade for app $($AppInfo.Name) with version $($AppInfo.Version) was started on $serverInstance Tenant $installTenant"                      
                }
                catch {
                    Write-Host "Data Upgrade failed for app $($AppInfo.Name) with version $($AppInfo.Version): $($_.Exception.Message)"
                }      
                Write-Host "App $($AppInfo.Name) with version $($AppInfo.Version) was installed on $serverInstance Tenant $installTenant"
            }
            
            try {
                Unpublish-NAVApp -ServerInstance $serverInstance -Name $_.Name -Version $_.Version
                Write-Host "App $($_.Name) with version $($_.Version) was unpublished from $serverInstance"
            }
            catch {
                Write-Host "Unpublish of app $($_.Name) with version $($_.Version) failed: $($_.Exception.Message)"
            } 
        }
    }
}