Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ".",
    [Parameter(HelpMessage = "Indicates whether you want to retrieve the list of project list as well", Mandatory = $false)]
    [bool] $getprojects = $true,
    [Parameter(HelpMessage = "Specifies the pattern of the environments you want to retreive (or empty for no environments)", Mandatory = $false)]
    [string] $getenvironments = '*',
    [Parameter(HelpMessage = "Specifies whether you want to include production environments", Mandatory = $false)]
    [bool] $includeProduction,
    [Parameter(HelpMessage = "Indicates whether this is called from a release pipeline", Mandatory = $false)]
    [bool] $release,
    [Parameter(HelpMessage = "Specifies which properties to get from the settings file, default is all", Mandatory = $false)]
    [string] $get = ""
)


$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    if ($project  -eq ".") { $project = "" }

    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
   
    $settings = ReadSettings -baseFolder $baseFolder -workflowName $env:GITHUB_WORKFLOW
    if ($get) {
        $getSettings = $get.Split(',').Trim()
    }
    else {
        $getSettings = @($settings.Keys)
    }

    $settings.appBuild = [Int32]([DateTime]::UtcNow.ToString('YYMMddhhmm'))
    $settings.appRevision = 0

    $outSettings = @{}
    $getSettings | ForEach-Object {
        $setting = $_.Trim()
        $outSettings += @{ "$setting" = $settings."$setting" }
        Add-Content -Path $env:GITHUB_ENV -Value "$setting=$($settings."$setting")"
    }

    $outSettingsJson = $outSettings | ConvertTo-Json -Compress
    Write-Host "::set-output name=SettingsJson::$outSettingsJson"
    Write-Host "set-output name=SettingsJson::$outSettingsJson"
    Add-Content -Path $env:GITHUB_ENV -Value "Settings=$OutSettingsJson"

    $gitHubRunner = $settings.githubRunner.Split(',') | ConvertTo-Json -compress
    Write-Host "::set-output name=GitHubRunnerJson::$githubRunner"
    Write-Host "set-output name=GitHubRunnerJson::$githubRunner"

    if ($getprojects) {
        $projects = @(Get-ChildItem -Path $ENV:GITHUB_WORKSPACE -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".AL-Go") -PathType Container } | ForEach-Object { $_.Name })
        if ($projects) {
            if (($ENV:GITHUB_EVENT_NAME -eq "pull_request" -or $ENV:GITHUB_EVENT_NAME -eq "push") -and !$settings.alwaysBuildAllProjects) {
                $headers = @{             
                    "Authorization" = "token $token"
                    "Accept" = "application/vnd.github.baptiste-preview+json"
                }
                $ghEvent = Get-Content $ENV:GITHUB_EVENT_PATH -encoding UTF8 | ConvertFrom-Json
                if ($ENV:GITHUB_EVENT_NAME -eq "pull_request") {
                    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/compare/$($ghEvent.pull_request.base.sha)...$($ENV:GITHUB_SHA)"
                }
                else {
                    $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/compare/$($ghEvent.before)...$($ghEvent.after)"
                }
                $response = Invoke-WebRequest -Headers $headers -UseBasicParsing -Method GET -Uri $url | ConvertFrom-Json
                $filesChanged = @($response.files | ForEach-Object { $_.filename })
                if ($filesChanged.Count -lt 250) {
                    $foldersChanged = @($filesChanged | ForEach-Object { $_.Split('/')[0] } | Select-Object -Unique)
                    $projects = @($projects | Where-Object { $foldersChanged -contains $_ })
                    Write-Host "Modified projects: $($projects -join ', ')"
                }
            }
        }
        if (Test-Path ".AL-Go" -PathType Container) {
            $projects += @(".")
        }
        Write-Host "All Projects: $($projects -join ', ')"
        if ($projects.Count -eq 1) {
            $projectsJSon = "[$($projects | ConvertTo-Json -compress)]"
        }
        else {
            $projectsJSon = $projects | ConvertTo-Json -compress
        }
        Write-Host "::set-output name=ProjectsJson::$projectsJson"
        Write-Host "set-output name=ProjectsJson::$projectsJson"
        Write-Host "::set-output name=ProjectCount::$($projects.Count)"
        Write-Host "set-output name=ProjectCount::$($projects.Count)"
        Add-Content -Path $env:GITHUB_ENV -Value "Projects=$projectsJson"
    }

    if ($getenvironments) {
        $headers = @{ 
            "Authorization" = "token $token"
            "Accept"        = "application/vnd.github.v3+json"
        }
        $url = "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/environments"
        try {
            $environments = @($settings.Environments)+@((Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $url | ConvertFrom-Json).environments | Where-Object { 
                if ($includeProduction) {
                    $_.Name -like $getEnvironments -or $_.Name -like "$getEnvironments (Production)"
                }
                else {
                    $_.Name -like $getEnvironments -and $_.Name -notlike '* (Production)'
                }
            } | ForEach-Object { $_.Name })
        }
        catch {
            $environments = @()
        }
        if ($environments.Count -eq 1) {
            $environmentsJSon = "[$($environments | ConvertTo-Json -compress)]"
        }
        else {
            $environmentsJSon = $environments | ConvertTo-Json -compress
        }
        Write-Host "::set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "set-output name=EnvironmentsJson::$environmentsJson"
        Write-Host "::set-output name=EnvironmentCount::$($environments.Count)"
        Write-Host "set-output name=EnvironmentCount::$($environments.Count)"
        Add-Content -Path $env:GITHUB_ENV -Value "Environments=$environmentsJson"
    }
}
catch {
    Write-Host "Error:$($_.Exception.Message)"
    exit
}
