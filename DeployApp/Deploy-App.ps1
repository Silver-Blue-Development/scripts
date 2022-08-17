Param(
    [Parameter(HelpMessage = "Artifacts to deploy", Mandatory = $true)]
    [string] $artifacts,
    [Parameter(HelpMessage = "Tenants to install the app in", Mandatory = $true)]
    [string[]] $tenants
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    write-Host $artifacts

    $apps = @()

    $apps
    if (Test-Path $artifacts) {
        Write-Host "Hello 01"
        $apps = @((Get-ChildItem -Path $artifacts) | ForEach-Object { $_.FullName })
        if (!($apps)) {
            throw "There is no artifacts present in $artifacts."
        }
    }
    else {
        throw "Artifact $artifacts was not found. Make sure that the artifact files exist and files are not corrupted."
    }

    $ServiceFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\190\Service"
    Import-Module "$($ServiceFolder)\Microsoft.Dynamics.Nav.Apps.Management.dll" -Scope Global -Verbose:$false
    Import-Module "$($ServiceFolder)\Microsoft.Dynamics.Nav.Management.dll" -Scope Global -Verbose:$false
    Import-module "$($ServiceFolder)\Microsoft.Dynamics.Nav.Model.Tools.dll" -Scope Global -Verbose:$false
    Import-Module "$($ServiceFolder)\Microsoft.Dynamics.Nav.Apps.Tools.dll" -Scope Global -Verbose:$false
    Import-Module "$($ServiceFolder)\NavAdminTool.ps1" -WarningAction SilentlyContinue | Out-Null

    $apps | ForEach-Object {
        try {
            Write-Host "File Name found: $_"

            foreach ($file in Get-ChildItem $_)
            {
                Write-Host $file

                $AppInfo = Get-NAVAppInfo -Path $file -Verbose:$false
                Write-Host "-App.ID = $($AppInfo.AppId)" 
                Write-Host "-App.Name = $($AppInfo.Name)"
                Write-Host "-App.Publisher = $($AppInfo.Publisher)"
                Write-Host "-App.Version = $($AppInfo.Version)"

                Get-NAVAppInfo -ServerInstance BC190 -Tenant bosman -Name $AppInfo.Name -Publisher $AppInfo.Publisher -TenantSpecificProperties | 
                    ForEach-Object -Process { 
                            Write-Host "Attempting to uninstall app $($_.Name) with version: $($_.Version)"
                            Uninstall-NAVApp -ServerInstance BC190 -Tenant bosman -Name $_.Name -Version $_.Version -Force
                            Write-Host "App $($_.Name) with version $($_.Version) was uninstalled from tenant bosman"
                            Unpublish-NAVApp -ServerInstance BC190 -Name $_.Name -Version $_.Version
                            Write-Host "App $($_.Name) with version $($_.Version) was unpublished from tenant bosman"
                    }

                Publish-NAVApp -ServerInstance BC190 -Path $file -SkipVerification
                Write-Host "App $($AppInfo.Name) was published to BC190"
                Sync-NAVApp -ServerInstance BC190 -Tenant bosman -Name $AppInfo.Name -Version $AppInfo.Version 
                Write-Host "App $($AppInfo.Name) was Synced to BC190 Tenant bosman"

                $tenantsArray= $tenants.Split(",")

                foreach ($installTenant in $tenantsArray) {    
                    Write-Host "Installing app on tenant $installTenant"               
                    Start-NAVAppDataUpgrade -ServerInstance BC190 -Name $AppInfo.Name -Version $AppInfo.Version -Tenant $installTenant 
                    Write-Host "Data upgrade for app $($AppInfo.Name) with version $($AppInfo.Version) was started on BC190 Tenant $installTenant"
                    #Install-NAVApp -ServerInstance BC190 -Name $AppInfo.Name -Version $AppInfo.Version -Tenant bosman        
                    Write-Host "App $($AppInfo.Name) with version $($AppInfo.Version) was installed on BC190 Tenant $installTenant"
                }
            }
        }
        catch {
            Write-Host "Deploying to failed. $($_.Exception.Message)"
            exit
        }
    }
}
catch {
    Write-Host $_.Exception.Message
}