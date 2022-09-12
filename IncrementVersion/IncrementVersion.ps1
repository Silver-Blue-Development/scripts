Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "The increment for the version number (i.e. +0.1", Mandatory = $true)]
    [String] $versionNumber = '+0.1'
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\Github-Helper.ps1" -Resolve)
 
    $project = '.'
    $directCommit = false;
    # $branch = "$(if (!$directCommit) { [System.IO.Path]::GetRandomFileName() })"
    # $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch    

    Write-Host "Versionnumber = $($versionNumber)"
    $versionNumber = $versionNumber.Substring(1)
    try {
        $newVersion = [System.Version]"$($versionnumber).0.0"
    }
    catch {
        throw "Version number ($versionnumber) is malformed. A version number must be structured as <Major>.<Minor> or +<Major>.<Minor>"
    }

    Write-Host "The version increment is $($newVersion.Major) and $($newVersion.Minor)"

    if (!$project) { $project = '.' }
    $projects = @( '.' )

    $projects | ForEach-Object {
        $project = $_
        try {
            Write-Host "Reading settings from $project\$ALGoSettingsFile"
            $settingsJson = Get-Content "$project\$ALGoSettingsFile" -Encoding UTF8 | ConvertFrom-Json
            if ($settingsJson.PSObject.Properties.Name -eq "RepoVersion") {
                $oldVersion = [System.Version]"$($settingsJson.RepoVersion).0.0"         
                $repoVersion = [System.Version]"$($oldVersion.Major+$newVersion.Major).$($oldVersion.Minor+$newVersion.Minor).0.0"
                $settingsJson.RepoVersion = "$($repoVersion.Major).$($repoVersion.Minor)"
            }
            $settingsJson
            $settingsJson | ConvertTo-Json -Depth 99 | Set-Content "$project\$ALGoSettingsFile" -Encoding UTF8
        }
        catch {
            throw "Settings file $project\$ALGoSettingsFile is malformed.$([environment]::Newline) $($_.Exception.Message)."
        }

        $folders = @('appFolders', 'testFolders' | ForEach-Object { if ($SettingsJson.PSObject.Properties.Name -eq $_) { $settingsJson."$_" } })
        if (-not ($folders)) {
            $folders = Get-ChildItem -Path $project -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'app.json') } | ForEach-Object { $_.Name }
        }
        $folders | ForEach-Object {
            Write-Host "Modifying app.json in folder $project\$_"
            $appJsonFile = Join-Path "$project\$_" "app.json"
            if (Test-Path $appJsonFile) {
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    $oldVersion = [System.Version]$appJson.Version
                    $newBuild = [Int32]([DateTime]::UtcNow.ToString('yyyyMMdd'))

                    $appVersion = [System.Version]"$($newVersion.Major+$oldVersion.Major).$($newVersion.Minor+$oldVersion.Minor).$($newBuild).0"
                    $appJson.Version = "$appVersion"
                    $appJson | ConvertTo-Json -Depth 99 | Set-Content $appJsonFile -Encoding UTF8
                }
                catch {
                    throw "Application manifest file($appJsonFile) is malformed."
                }
            }
        }

        Add-Content -Path $env:GITHUB_ENV -Value "outputTag=$appVersion"
        #Add-Content -Path $env:GITHUB_ENV -Value "outputBranch=$branch"

        CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Increment Version number by $($newVersion.Major).$($newVersion.Minor)" -branch "develop" #$branch
    }
}
catch {
    OutputError -message "IncrementVersionNumber action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
}