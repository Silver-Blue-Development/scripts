Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '{}',
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = "",
    [Parameter(HelpMessage = "Settings from repository in compressed Json format", Mandatory = $false)]
    [string] $settingsJson = '{"AppBuild":"", "AppRevision":""}',
    [Parameter(HelpMessage = "Secrets from repository in compressed Json format", Mandatory = $false)]
    [string] $secretsJson = '{"licenseFileUrl":"PersonalAccesToken"}',
    [Parameter(HelpMessage = "The Person Access Token for used GitHub repositories", Mandatory = $true)]
    [string] $gitHubPAT
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    Write-Host "********** Start Run-Pipeline **************"

    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\Github-Helper.ps1" -Resolve)
    #$BcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE   //Only when github runner

    Write-Host "Check Container Helper Permissions"
    Check-BcContainerHelperPermissions -Fix

    # Pull docker image in the background
    $genericImageName = Get-BestGenericImageName
    Start-Job -ScriptBlock {
        docker pull --quiet $genericImageName
    } -ArgumentList $genericImageName | Out-Null

    $runAlPipelineParams = @{}
    $environment = 'GitHubActions'
    if ($project  -eq ".") { 
        $project = "" 
    }
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $sharedFolder = ""
    if ($project) {
        $sharedFolder = $ENV:GITHUB_WORKSPACE
    }
    $workflowName = $env:GITHUB_WORKFLOW
    $containerName = GetContainerName($project)

    Write-Host "Use settings and secrets"
    $settings = $settingsJson | ConvertFrom-Json | ConvertTo-HashTable
    $secrets = $secretsJson | ConvertFrom-Json | ConvertTo-HashTable
    $appBuild = $settings.appBuild
    $appRevision = $settings.appRevision

    Write-Host = "App Build = $($appBuild)"
    Write-Host = "App Revision = $($appRevision)"

    $appRevision = $settings.appRevision
    'licenseFileUrl'| ForEach-Object {
        if ($secrets.ContainsKey($_)) {
            $value = $secrets."$_"
        }
        else {
            $value = ""
        }
        Set-Variable -Name $_ -Value $value
    }

    $repo = AnalyzeRepo -settings $settings -baseFolder $baseFolder 
    if ((-not $repo.appFolders) -and (-not $repo.testFolders)) {
        Write-Host "Repository is empty, exiting"
        exit
    }

    $artifact = $repo.artifact
    Write-Host = "Artifact = $artifact"
    $installApps = $repo.installApps
    Write-Host "Install Apps = $installApps"
    $installTestApps = $repo.installTestApps
    Write-Host "Install Apps = $installTestApps"
    $doNotBuildTests = $repo.doNotBuildTests
    Write-Host "Do not build tests = $doNotBuildTests"
    $doNotRunTests = $repo.doNotRunTests
    Write-Host "Do not run tests = $doNotRunTests"
 
    if ($repo.appDependencyProbingPaths) {
    Write-Host "Downloading dependencies ..."
    $installApps += Get-dependencies -probingPathsJson $repo.appDependencyProbingPaths -token $gitHubPAT      
    }

    $previousApps = @()
    if ($repo.skipUpgrade) {
        OutputWarning -message "Skipping upgrade tests"
    }
    else {
        try {
            $releasesJson = GetReleases -token $token -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY
            $latestRelease = $releasesJson | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
            if ($latestRelease) {
                Write-Host "Using $($latestRelease.name) as previous release"
                $artifactsFolder = Join-Path $baseFolder "artifacts"
                New-Item $artifactsFolder -ItemType Directory | Out-Null
                DownloadRelease -token $token -projects $project -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -release $latestRelease -path $artifactsFolder
                $previousApps += @(Get-ChildItem -Path $artifactsFolder | ForEach-Object { $_.FullName })
            }
            else {
                OutputWarning -message "No previous release found"
            }
        }
        catch {
            OutputError -message "Error trying to locate previous release. Error was $($_.Exception.Message)"
            exit
        }
    }

    $additionalCountries = $repo.additionalCountries
    Write-Host "Additional Counties = $additionalCountries"

    $imageName = ""
    if ($repo.gitHubRunner -ne "windows-latest") {
        $imageName = $repo.cacheImageName
        Flush-ContainerHelperCache -keepdays $repo.cacheKeepDays
    }
    $authContext = $null
    $environmentName = ""
    $CreateRuntimePackages = $false

    if ($repo.versioningStrategy -eq -1) {
        Write-Host "Versioning Strategy = -1"
        $artifactVersion = [Version]$repo.artifact.Split('/')[4]
        $runAlPipelineParams += @{
            "appVersion" = "$($artifactVersion.Major).$($artifactVersion.Minor)"
        }
        $appBuild = $artifactVersion.Build
        $appRevision = $artifactVersion.Revision
    }
    elseif (($repo.versioningStrategy -band 16) -eq 16) {
        Write-Host "Versioning Strategy = 16"
        $runAlPipelineParams += @{
            "appVersion" = $repo.repoVersion
        }
    }
    
    $buildArtifactFolder = Join-Path $baseFolder "output"
    New-Item $buildArtifactFolder -ItemType Directory | Out-Null

    $allTestResults = "testresults*.xml"
    $testResultsFile = Join-Path $baseFolder "TestResults.xml"
    $testResultsFiles = Join-Path $baseFolder $allTestResults
    if (Test-Path $testResultsFiles) {
        Remove-Item $testResultsFiles -Force
    }
    
    "containerName=$containerName" | Add-Content $ENV:GITHUB_ENV

    Set-Location $baseFolder
    $runAlPipelineOverrides | ForEach-Object {
        $scriptName = $_
        $scriptPath = Join-Path $ALGoFolder "$ScriptName.ps1"
        if (Test-Path -Path $scriptPath -Type Leaf) {
            Write-Host "Add override for $scriptName"
            $runAlPipelineParams += @{
                "$scriptName" = (Get-Command $scriptPath | Select-Object -ExpandProperty ScriptBlock)
            }
        }
    }
    
    Write-Host "Invoke Run-AlPipeline"
    Run-AlPipeline @runAlPipelineParams `
        -pipelinename $workflowName `
        -containerName $containerName `
        -imageName $imageName `
        -bcAuthContext $authContext `
        -environment $environmentName `
        -artifact $artifact `
        -companyName $repo.companyName `
        -memoryLimit $repo.memoryLimit `
        -baseFolder $baseFolder `
        -sharedFolder $sharedFolder `
        -licenseFile $LicenseFileUrl `
        -installApps $installApps `
        -installTestApps $installTestApps `
        -installOnlyReferencedApps:$repo.installOnlyReferencedApps `
        -previousApps $previousApps `
        -appFolders $repo.appFolders `
        -testFolders $repo.testFolders `
        -doNotBuildTests:$doNotBuildTests `
        -doNotRunTests:$doNotRunTests `
        -testResultsFile $testResultsFile `
        -testResultsFormat 'JUnit' `
        -installTestRunner:$repo.installTestRunner `
        -installTestFramework:$repo.installTestFramework `
        -installTestLibraries:$repo.installTestLibraries `
        -installPerformanceToolkit:$repo.installPerformanceToolkit `
        -enableCodeCop:$repo.enableCodeCop `
        -enableAppSourceCop:$repo.enableAppSourceCop `
        -enablePerTenantExtensionCop:$repo.enablePerTenantExtensionCop `
        -enableUICop:$repo.enableUICop `
        -customCodeCops:$repo.customCodeCops `
        -azureDevOps:($environment -eq 'AzureDevOps') `
        -gitLab:($environment -eq 'GitLab') `
        -gitHubActions:($environment -eq 'GitHubActions') `
        -failOn $repo.failOn `
        -rulesetFile $repo.rulesetFile `
        -AppSourceCopMandatoryAffixes $repo.appSourceCopMandatoryAffixes `
        -additionalCountries $additionalCountries `
        -buildArtifactFolder $buildArtifactFolder `
        -CreateRuntimePackages:$CreateRuntimePackages `
        -appBuild $appBuild -appRevision $appRevision `
        -uninstallRemovedApps `
        -isolation 'hyperv'
}
catch {
    OutputError -message $_.Exception.Message
}
finally {    
    #CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath  //Only when github runner
}