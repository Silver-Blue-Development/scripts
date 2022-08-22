Param(
    [Parameter(HelpMessage = "Tenants to install the app in", Mandatory = $true)]
    [string[]] $tenants,
    [Parameter(HelpMessage = "Environment to publish the app in", Mandatory = $true)]
    [ValidateSet('O','T','A')]
    [string[]] $environments,
    [Parameter(HelpMessage = "SAS Token for Azure", Mandatory = $true)]
    [string] $azureSas,
    [Parameter(HelpMessage = "Repository Name", Mandatory = $true)]
    [string] $repoName,
    [Parameter(HelpMessage = "O or A", Mandatory = $false)]
    [ValidateSet('O','A')]
    [string] $source = 'O'
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
            $serverInstance = "ONTW"; #TODO Set correct instance
        }
        "T" 
        {
            $serviceFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\190\Service"
            $serverInstance = "BC190"; #TODO Set correct instance
        }
        "A" 
        {
            $serviceFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\190\Service"
            $serverInstance = "ACCEPT"; #TODO Set correct instance
        }
    }      

    switch ($source)
    {
        "O" 
        {    
            $containerName = "Development";
        }
        "A" 
        {
            $containerName = "Acceptance";
        }
    }      
    
    $SourcePath = "https://businesscentralartifcats.blob.core.windows.net/$containerName/Apps/*?$azureSas"
    $SourcePath2 = "https://businesscentralartifcats.blob.core.windows.net/$containerName/TestApps/*?$azureSas" 

    $FolderName = "C:\Artifacts\$containerName\$repoName"
    if (Test-Path $FolderName) {            
        Write-Host "Removing previous app versions from folder on server"
        Remove-Item C:\Artifacts\$containerName\$repoName\*.* 
    } 

    $FolderName = "C:\Artifacts\$containerName\$repoName\Tests"
    if (Test-Path $FolderName) {
        Write-Host "Removing previous test versions from folder on server"
        Remove-Item C:\Artifacts\$containerName\$repoName\Tests\*.* 
    }

    $FolderName = "C:\Azure\azcopy.exe"
    if (Test-Path $FolderName -PathType Leaf) {     
        Set-Location "C:\Azure"
        ./azcopy.exe copy $SourcePath --include-pattern "*$repoName*" 'C:\Artifacts\$repoName\$repoName'          
        ./azcopy.exe copy $SourcePath2 --include-pattern "*$repoName*" 'C:\Artifacts\$repoName\$repoName\Tests'
    }
    else
    {            
        New-Item $FolderName -ItemType Directory
        Write-Host "Folder Created successfully"            
        Write-Host "File azcopy.exe is missing in Azure folder"
    } 
    
    $artifacts = "C:\Artifacts\$containerName\$repoName"
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
    
    Write-Host "ServiceInstance is set to $serverInstance"

    Import-Module "$($serviceFolder)\Microsoft.Dynamics.Nav.Apps.Management.dll" -Scope Global -Verbose:$false
    Import-Module "$($serviceFolder)\Microsoft.Dynamics.Nav.Management.dll" -Scope Global -Verbose:$false
    Import-module "$($serviceFolder)\Microsoft.Dynamics.Nav.Model.Tools.dll" -Scope Global -Verbose:$false
    Import-Module "$($serviceFolder)\Microsoft.Dynamics.Nav.Apps.Tools.dll" -Scope Global -Verbose:$false
    Import-Module "$($serviceFolder)\NavAdminTool.ps1" -WarningAction SilentlyContinue | Out-Null

    $apps | ForEach-Object {
        try {
            Write-Host "File found: $_"
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
                                Write-Host "Attempting to uninstall app $($_.Name) with version: $($_.Version)"
                                Uninstall-NAVApp -ServerInstance $serverInstance -Tenant $installTenant -Name $_.Name -Version $_.Version -Force
                                Write-Host "App $($_.Name) with version $($_.Version) was uninstalled from tenant $installTenant"
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
                    Install-NAVApp -ServerInstance $serverInstance -Name $AppInfo.Name -Version $AppInfo.Version -Tenant $installTenant        
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
        catch {            
            Write-Host $_.Exception.Message
        }     
    }
}