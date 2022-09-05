function Get-dependencies {
    Param(
        $probingPathsJson,
        $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE "dependencies"),
        [string] $mask = "Apps"
    )

    if (!(Test-Path $saveToPath)) {
        New-Item $saveToPath -ItemType Directory | Out-Null
    }

    Write-Host "Getting all the artifacts from probing paths"
    $downloadedList = @()
    $probingPathsJson | ForEach-Object {
        $dependency = $_
        Write-Host "Dependency = $dependency"
        if (-not ($dependency.PsObject.Properties.name -eq "repo")) {
            throw "AppDependencyProbingPaths needs to contain a repo property, pointing to the repository on which you have a dependency"
        }

        $repository = $dependency.repo

        Write-Host "Repo = $repository"
        Write-Host "Release Status = Latest Build"

        $artifacts = GetArtifacts -token $token -api_url $api_url -repository $repository -mask $mask
            
        $artifact = $artifacts | Select-Object -First 1
        if (!($artifact)) {
            throw "Could not find any artifacts that matches the criteria."
        }

        $download = DownloadArtifact -path $saveToPath -token $token -artifact $artifact

        if ($download) {
            $downloadedList += $download
        }
    }
    
    return $downloadedList;
}

function GetReleases {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing releases $api_url/repos/$repository/releases"
    Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases" | ConvertFrom-Json
}

function GetHeader {
    param (
        [string] $token,
        [string] $accept = "application/json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "bearer $token"
    }

    return $headers
}

function GetReleaseNotes {
    Param(
        [string] $token,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $tag_name,
        [string] $previous_tag_name
    )
    
    Write-Host "Generating release note $api_url/repos/$repository/releases/generate-notes"

    $postParams = @{
        tag_name = $tag_name;
    } 
    
    if (-not [string]::IsNullOrEmpty($previous_tag_name)) {
        $postParams["previous_tag_name"] = $previous_tag_name
    }

    Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Method POST -Body ($postParams | ConvertTo-Json) -Uri "$api_url/repos/$repository/releases/generate-notes" 
}

function GetLatestRelease {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )
    
    Write-Host "Getting the latest release from $api_url/repos/$repository/releases/latest"
    try {
        Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases/latest" | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function DownloadRelease {
    Param(
        [string] $token,
        [string] $projects = "*",
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $path,
        [string] $mask = "-Apps-",
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "Downloading release $($release.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/octet-stream"
    }
    $projects.Split(',') | ForEach-Object {
        $project = $_
        Write-Host "project '$project'"
        
        $release.assets | Where-Object { $_.name -like "$project$mask*.zip" } | ForEach-Object {
            Write-Host "$api_url/repos/$repository/releases/assets/$($_.id)"
            $filename = Join-Path $path $_.name
            Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "$api_url/repos/$repository/releases/assets/$($_.id)" -OutFile $filename 
            return $filename
        }
    }
}       

function GetArtifacts {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $mask = "Apps"
    )

    $uri = "$api_url/repos/$repository/actions/artifacts"
    Write-Host $uri

    $artifacts = Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri $uri | ConvertFrom-Json
    $artifacts.artifacts | Where-Object { $_.name -like "*$($mask)*" }

    Write-Host "Found this: $($artifacts.artifacts)"
}

function DownloadArtifact {
    Param(
        [string] $token,
        [string] $path,
        $artifact
    )

    Write-Host "Downloading artifact $($artifact.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.v3+json"
    }
    $outFile = Join-Path $path "$($artifact.Name).zip"
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $artifact.archive_download_url -OutFile $outFile
    $outFile
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