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
        if (-not ($dependency.PsObject.Properties.name -eq "AuthTokenSecret")) {
            $dependency | Add-Member -name "AuthTokenSecret" -MemberType NoteProperty -Value $token
        }
        if (-not ($dependency.PsObject.Properties.name -eq "Version")) {
            $dependency | Add-Member -name "Version" -MemberType NoteProperty -Value "latest"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "Projects")) {
            $dependency | Add-Member -name "Projects" -MemberType NoteProperty -Value "*"
        }
        if (-not ($dependency.PsObject.Properties.name -eq "release_status")) {
            $dependency | Add-Member -name "release_status" -MemberType NoteProperty -Value "latestBuild"
        }

        Write-Host "Getting releases from $($dependency.repo)"
        #$repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")
        $repository = $dependency.repo
        Write-Host "Repo = $repository"

        Write-Host "Release Status = Latest Build"
        $artifacts = GetArtifacts -token $dependency.authTokenSecret -api_url $api_url -repository $repository -mask $mask
        if ($dependency.version -ne "latest") {
            Write-Host "Hello there!"
            $artifacts = $artifacts | Where-Object { ($_.tag_name -eq $dependency.version) }
        }    
            
        $artifact = $artifacts | Select-Object -First 1
        if (!($artifact)) {
            throw "Could not find any artifacts that matches the criteria."
        }

        $download = DownloadArtifact -path $saveToPath -token $dependency.authTokenSecret -artifact $artifact

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
        $headers["Authorization"] = "token $token"
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
        [string] $mask = "-Apps-"
    )

    Write-Host "Analyzing artifacts"
    $artifacts = Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/actions/artifacts" | ConvertFrom-Json
    $artifacts.artifacts | Where-Object { $_.name -like "*$($mask)*" }
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