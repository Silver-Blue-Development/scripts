$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\Github-Helper.ps1" -Resolve)

    $project = ""
    
    $baseFolder = Join-Path $ENV:GITHUB_WORKSPACE $project
    $settings = ReadSettings -baseFolder $baseFolder -workflowName $env:GITHUB_WORKFLOW

    Write-Host "Settings: $($settings)"
    $settingsJson = Get-Content $settings -Encoding UTF8 | ConvertFrom-Json

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

                Write-Host "app.json version set to $($appVersion)"
                
                Write-Host "::set-output name=outputTag::$appVersion"
                Write-Host "set-output name=outputTag::$appVersion"
            }
            catch {
                throw "Application manifest file($appJsonFile) is malformed."
            }
        }
    }
}
catch {
    OutputError -message "IncrementVersionNumber action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
}