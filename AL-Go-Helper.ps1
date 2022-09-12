Param(
    [switch] $local
)

$gitHubHelperPath = Join-Path $PSScriptRoot 'Github-Helper.psm1'
if (Test-Path $gitHubHelperPath) {
    Import-Module $gitHubHelperPath
}

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0

$ALGoFolder = ".AL-Go\"
$ALGoSettingsFile = ".AL-Go\settings.json"
$RepoSettingsFile = ".github\AL-Go-Settings.json"
$runningLocal = $local.IsPresent

$runAlPipelineOverrides = @(
    "DockerPull"
    "NewBcContainer"
    "ImportTestToolkitToBcContainer"
    "CompileAppInBcContainer"
    "GetBcContainerAppInfo"
    "PublishBcContainerApp"
    "UnPublishBcContainerApp"
    "InstallBcAppFromAppSource"
    "SignBcContainerApp"
    "ImportTestDataInBcContainer"
    "RunTestsInBcContainer"
    "GetBcContainerAppRuntimePackage"
    "RemoveBcContainer"
)

# Well known AppIds
$systemAppId = "63ca2fa4-4f03-4f2b-a480-172fef340d3f"
$baseAppId = "437dbf0e-84ff-417a-965d-ed2bb9650972"
$applicationAppId = "c1335042-3002-4257-bf8a-75c898ccb1b8"
$permissionsMockAppId = "40860557-a18d-42ad-aecb-22b7dd80dc80"
$testRunnerAppId = "23de40a6-dfe8-4f80-80db-d70f83ce8caf"
$anyAppId = "e7320ebb-08b3-4406-b1ec-b4927d3e280b"
$libraryAssertAppId = "dd0be2ea-f733-4d65-bb34-a28f4624fb14"
$libraryVariableStorageAppId = "5095f467-0a01-4b99-99d1-9ff1237d286f"
$systemApplicationTestLibraryAppId = "9856ae4f-d1a7-46ef-89bb-6ef056398228"
$TestsTestLibrariesAppId = "5d86850b-0d76-4eca-bd7b-951ad998e997"
$performanceToolkitAppId = "75f1590f-55c5-4501-ae63-bada5534e852"

$performanceToolkitApps = @($performanceToolkitAppId)
$testLibrariesApps = @($systemApplicationTestLibraryAppId, $TestsTestLibrariesAppId)
$testFrameworkApps = @($anyAppId, $libraryAssertAppId, $libraryVariableStorageAppId) + $testLibrariesApps
$testRunnerApps = @($permissionsMockAppId, $testRunnerAppId) + $performanceToolkitApps + $testLibrariesApps + $testFrameworkApps

$MicrosoftTelemetryConnectionString = "InstrumentationKey=84bd9223-67d4-4378-8590-9e4a46023be2;IngestionEndpoint=https://westeurope-1.in.applicationinsights.azure.com/"

function invoke-gh {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    $arguments = "$command "
    $remaining | ForEach-Object {
        if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
            $arguments += """$($_.Replace('"','\"'))"" "
        }
        else {
            $arguments += "$_ "
        }
    }
    cmdDo -command gh -arguments $arguments -silent:$silent -returnValue:$returnValue
}

function ConvertTo-HashTable {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | Foreach { $ht[$_.Name] = $_.Value }
    }
    $ht
}

function OutputError {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        throw $message
    }
    else {
        Write-Host "::Error::$message"
        $host.SetShouldExit(1)
    }
}

function OutputWarning {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host -ForegroundColor Yellow "WARNING: $message"
    }
    else {
        Write-Host "::Warning::$message"
    }
}

function OutputDebug {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host $message
    }
    else {
        Write-Host "::Debug::$message"
    }
}


function Expand-7zipArchive {
    Param (
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [string] $DestinationPath
    )

    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

    $use7zip = $false
    if (Test-Path -Path $7zipPath -PathType Leaf) {
        try {
            $use7zip = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($7zipPath).FileMajorPart -ge 19
        }
        catch {
            $use7zip = $false
        }
    }

    if ($use7zip) {
        OutputDebug -message "Using 7zip"
        Set-Alias -Name 7z -Value $7zipPath
        $command = '7z x "{0}" -o"{1}" -aoa -r' -f $Path, $DestinationPath
        Invoke-Expression -Command $command | Out-Null
    }
    else {
        OutputDebug -message "Using Expand-Archive"
        Expand-Archive -Path $Path -DestinationPath "$DestinationPath" -Force
    }
}

function DownloadAndImportBcContainerHelper {
    Param(
        [string] $BcContainerHelperVersion = "",
        [string] $baseFolder = ""
    )

    $params = @{ "ExportTelemetryFunctions" = $true }
    if ($baseFolder) {
        Write-Host "BaseFolder = true"
        $repoSettingsPath = Join-Path $baseFolder $repoSettingsFile

        if (Test-Path $repoSettingsPath) {
            Write-Host "Hello 002"
            if (-not $BcContainerHelperVersion) {
                Write-Host "Hello 003"
                $repoSettings = Get-Content $repoSettingsPath -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
                if ($repoSettings.ContainsKey("BcContainerHelperVersion")) {
                    Write-Host "Hello 004"
                    $BcContainerHelperVersion = $repoSettings.BcContainerHelperVersion
                    Write-Host "BCContainerHelper Version = $BcContainerHelperVersion"
                }
            }
            Write-Host "Repo Settings Path = $repoSettingsPath"
            $params += @{ "bcContainerHelperConfigFile" = $repoSettingsPath }
        }
    }
    $tempName = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    $webclient = New-Object System.Net.WebClient

    Write-Host "Downloading BcContainerHelper $BcContainerHelperVersion version"
    try {
        $webclient.DownloadFile("https://bccontainerhelper.azureedge.net/public/$($BcContainerHelperVersion).zip", "$tempName.zip")
    }
    catch {
        $webclient.DownloadFile("https://bccontainerhelper.blob.core.windows.net/public/$($BcContainerHelperVersion).zip", "$tempName.zip")        
    }
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"

    $BcContainerHelperPath = (Get-Item -Path (Join-Path $tempName "*\BcContainerHelper.ps1")).FullName
    . $BcContainerHelperPath @params
    $tempName
}

function CleanupAfterBcContainerHelper {
    Param(
        [string] $bcContainerHelperPath
    )

    if ($bcContainerHelperPath) {
        try {
            Write-Host "Removing BcContainerHelper"
            Remove-Module BcContainerHelper
            Remove-Item $bcContainerHelperPath -Recurse -Force
        }
        catch {}
    }
}

function MergeCustomObjectIntoOrderedDictionary {
    Param(
        [System.Collections.Specialized.OrderedDictionary] $dst,
        [PSCustomObject] $src
    )

    # Add missing properties in OrderedDictionary

    $src.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $prop = $_.Name
        $srcProp = $src."$prop"
        $srcPropType = $srcProp.GetType().Name
        if (-not $dst.Contains($prop)) {
            if ($srcPropType -eq "PSCustomObject") {
                $dst.Add("$prop", [ordered]@{})
            }
            elseif ($srcPropType -eq "Object[]") {
                $dst.Add("$prop", @())
            }
            else {
                $dst.Add("$prop", $srcProp)
            }
        }
    }

    @($dst.Keys) | ForEach-Object {
        $prop = $_
        if ($src.PSObject.Properties.Name -eq $prop) {
            $dstProp = $dst."$prop"
            $srcProp = $src."$prop"
            $dstPropType = $dstProp.GetType().Name
            $srcPropType = $srcProp.GetType().Name
            if ($srcPropType -eq "PSCustomObject" -and $dstPropType -eq "OrderedDictionary") {
                MergeCustomObjectIntoOrderedDictionary -dst $dst."$prop" -src $srcProp
            }
            elseif ($dstPropType -ne $srcPropType) {
                throw "property $prop should be of type $dstPropType, is $srcPropType."
            }
            else {
                if ($srcProp -is [Object[]]) {
                    $srcProp | ForEach-Object {
                        $srcElm = $_
                        $srcElmType = $srcElm.GetType().Name
                        if ($srcElmType -eq "PSCustomObject") {
                            $ht = [ordered]@{}
                            $srcElm.PSObject.Properties | Sort-Object -Property Name -Culture "iv-iv" | Foreach { $ht[$_.Name] = $_.Value }
                            $dst."$prop" += @($ht)
                        }
                        else {
                            $dst."$prop" += $srcElm
                        }
                    }
                }
                else {
                    $dst."$prop" = $srcProp
                }
            }
        }
    }
}

function ReadSettings {
    Param(
        [string] $baseFolder,
        [string] $repoName = "$env:GITHUB_REPOSITORY",
        [string] $workflowName = "",
        [string] $userName = ""
    )

    $repoName = $repoName.SubString("$repoName".LastIndexOf('/') + 1)
    
    # Read Settings file
    $settings = [ordered]@{
        "type"                                   = "PTE"
        "country"                                = "us"
        "artifact"                               = ""
        "companyName"                            = ""
        "repoVersion"                            = "1.0"
        "repoName"                               = $repoName
        "versioningStrategy"                     = 0
        "runNumberOffset"                        = 0
        "appBuild"                               = 0
        "appRevision"                            = 0
        "keyVaultName"                           = ""
        "licenseFileUrlSecretName"               = "LicenseFileUrl"
        "insiderSasTokenSecretName"              = "InsiderSasToken"
        "ghTokenWorkflowSecretName"              = "GhTokenWorkflow"
        "adminCenterApiCredentialsSecretName"    = "AdminCenterApiCredentials"
        "keyVaultCertificateUrlSecretName"       = ""
        "keyVaultCertificatePasswordSecretName"  = ""
        "keyVaultClientIdSecretName"             = ""
        "codeSignCertificateUrlSecretName"       = "CodeSignCertificateUrl"
        "codeSignCertificatePasswordSecretName"  = "CodeSignCertificatePassword"
        "storageContextSecretName"               = "StorageContext"
        "additionalCountries"                    = @()
        "appDependencies"                        = @()
        "appFolders"                             = @()
        "testDependencies"                       = @()
        "testFolders"                            = @()
        "installApps"                            = @()
        "installTestApps"                        = @()
        "installOnlyReferencedApps"              = $true
        "skipUpgrade"                            = $false
        "applicationDependency"                  = "18.0.0.0"
        "installTestRunner"                      = $false
        "installTestFramework"                   = $false
        "installTestLibraries"                   = $false
        "installPerformanceToolkit"              = $false
        "enableCodeCop"                          = $false
        "enableUICop"                            = $false
        "customCodeCops"                         = @()
        "failOn"                                 = "error"
        "rulesetFile"                            = ""
        "doNotBuildTests"                        = $false
        "doNotRunTests"                          = $false
        "appSourceCopMandatoryAffixes"           = @()
        "memoryLimit"                            = ""
        "templateUrl"                            = ""
        "templateBranch"                         = ""
        "appDependencyProbingPaths"              = @()
        "githubRunner"                           = "windows-latest"
        "cacheImageName"                         = "my"
        "cacheKeepDays"                          = 3
        "alwaysBuildAllProjects"                 = $false
        "MicrosoftTelemetryConnectionString"     = $MicrosoftTelemetryConnectionString
        "PartnerTelemetryConnectionString"       = ""
        "SendExtendedTelemetryToMicrosoft"       = $false
        "Environments"                           = @()
    }

    $gitHubFolder = ".github"
    if (!(Test-Path (Join-Path $baseFolder $gitHubFolder) -PathType Container)) {
        $RepoSettingsFile = "..\$RepoSettingsFile"
        $gitHubFolder = "..\$gitHubFolder"
    }
    $workflowName = $workflowName.Split([System.IO.Path]::getInvalidFileNameChars()) -join ""
    $RepoSettingsFile, $ALGoSettingsFile, (Join-Path $gitHubFolder "$workflowName.settings.json"), (Join-Path $ALGoFolder "$workflowName.settings.json"), (Join-Path $ALGoFolder "$userName.settings.json") | ForEach-Object {
        $settingsFile = $_
        $settingsPath = Join-Path $baseFolder $settingsFile
        Write-Host "Checking $settingsFile"
        if (Test-Path $settingsPath) {
            try {
                Write-Host "Reading $settingsFile"
                $settingsJson = Get-Content $settingsPath -Encoding UTF8 | ConvertFrom-Json
       
                # check settingsJson.version and do modifications if needed
         
                MergeCustomObjectIntoOrderedDictionary -dst $settings -src $settingsJson
            }
            catch {
                throw "Settings file $settingsFile, is wrongly formatted. Error is $($_.Exception.Message)."
            }
        }
    }

    $settings
}

function AnalyzeRepo {
    Param(
        [hashTable] $settings,
        [string] $baseFolder,
        [switch] $doNotCheckArtifactSetting
    )

    if (!$runningLocal) {
        Write-Host "::group::Analyzing repository"
    }

    # Check applicationDependency
    [Version]$settings.applicationDependency | Out-null


    # Write-Host "Checking type"
    # if ($settings.type -eq "PTE") {
    if (!$settings.Contains('enablePerTenantExtensionCop')) {
        Write-Host "Enabled PerTenantExtensionCop"
        $settings.Add('enablePerTenantExtensionCop', $true)
    }
    if (!$settings.Contains('enableAppSourceCop')) {
        Write-Host "Disabled AppSource Cop"
        $settings.Add('enableAppSourceCop', $false)
    }
    # }
    # elseif ($settings.type -eq "AppSource App" ) {
    #     if (!$settings.Contains('enablePerTenantExtensionCop')) {
    #         $settings.Add('enablePerTenantExtensionCop', $false)
    #     }
    #     if (!$settings.Contains('enableAppSourceCop')) {
    #         $settings.Add('enableAppSourceCop', $true)
    #     }
    #     if ($settings.enableAppSourceCop -and (-not ($settings.appSourceCopMandatoryAffixes))) {
    #         throw "For AppSource Apps with AppSourceCop enabled, you need to specify AppSourceCopMandatoryAffixes in $ALGoSettingsFile"
    #     }
    # }
    # else {
    #     throw "The type, specified in $ALGoSettingsFile, must be either 'Per Tenant Extension' or 'AppSource App'. It is '$($settings.type)'."
    # }
 
    $artifact = $settings.artifact
    Write-Host "Artifact = $artifact"   
    # if ($artifact.Contains('{INSIDERSASTOKEN}')) {
    #     if ($insiderSasToken) {
    #         $artifact = $artifact.replace('{INSIDERSASTOKEN}', $insiderSasToken)
    #     }
    #     else {
    #         throw "Artifact definition $artifact requires you to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
    #     }
    # }

    if (!$doNotCheckArtifactSetting) {
        Write-Host "Checking artifact setting"
        # if ($artifact -like "https://*") {
        #     Write-Host "Hello 001"
        #     $artifactUrl = $artifact
        #     $storageAccount = ("$artifactUrl////".Split('/')[2]).Split('.')[0]
        #     $artifactType = ("$artifactUrl////".Split('/')[3])
        #     $version = ("$artifactUrl////".Split('/')[4])
        #     $country = ("$artifactUrl////".Split('/')[5])
        #     $sasToken = "$($artifactUrl)?".Split('?')[1]
        # }
        # else {
        #     Write-Host "Hello 002"
        $segments = "$artifact/////".Split('/')
        $storageAccount = $segments[0];
        $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
        $version = $segments[2]
        $country = $segments[3]; if ($country -eq "") { $country = $settings.country }
        $select = $segments[4]; if ($select -eq "") { $select = "latest" }
        $sasToken = $segments[5]
        $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -sasToken $sasToken | Select-Object -First 1
        if (-not $artifactUrl) {
            throw "No artifacts found for the artifact setting ($artifact) in $ALGoSettingsFile"
        }
        Write-Host "Artifact URL = $artifactUrl"
        $version = $artifactUrl.Split('/')[4]
        $storageAccount = $artifactUrl.Split('/')[2]
        #}
    
        # if ($settings.additionalCountries -or $country -ne $settings.country) {
        #     if ($country -ne $settings.country) {
        #         OutputWarning -message "artifact definition in $ALGoSettingsFile uses a different country ($country) than the country definition ($($settings.country))"
        #     }
        #     Write-Host "Checking Country and additionalCountries"
        #     # AT is the latest published language - use this to determine available country codes (combined with mapping)
        #     $ver = [Version]$version
        #     Write-Host "https://$storageAccount/$artifactType/$version/$country"
        #     $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -sasToken $sasToken
        #     Write-Host "Latest AT artifacts $atArtifactUrl"
        #     $latestATversion = $atArtifactUrl.Split('/')[4]
        #     $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -sasToken $sasToken -select All | ForEach-Object { 
        #         $countryArtifactUrl = $_.Split('?')[0] # remove sas token
        #         $countryArtifactUrl.Split('/')[5] # get country
        #     }
        #     Write-Host "Countries with artifacts $($countries -join ',')"
        #     $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
        #     Write-Host "Allowed Country codes $($allowedCountries -join ',')"
        #     if ($allowedCountries -notcontains $settings.country) {
        #         throw "Country ($($settings.country)), specified in $ALGoSettingsFile is not a valid country code."
        #     }
        #     $illegalCountries = $settings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
        #     if ($illegalCountries) {
        #         throw "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $ALGoSettingsFile."
        #     }
        # }
        # else {
            Write-Host "Downloading artifacts from $($artifactUrl.Split('?')[0])"
            $folders = Download-Artifacts -artifactUrl $artifactUrl -includePlatform -ErrorAction SilentlyContinue
            if (-not ($folders)) {
                throw "Unable to download artifacts from $($artifactUrl.Split('?')[0]), please check $ALGoSettingsFile."
            }
            $settings.artifact = $artifactUrl
        # }
    }
    
    if (-not (@($settings.appFolders)+@($settings.testFolders))) {
        Write-Host "Hello 003"
        Get-ChildItem -Path $baseFolder -Directory | Where-Object { Test-Path -Path (Join-Path $_.FullName "app.json") } | ForEach-Object {
            $folder = $_
            Write-Host "Folder = $folder"
            $appJson = Get-Content (Join-Path $folder.FullName "app.json") -Encoding UTF8 | ConvertFrom-Json
            $isTestApp = $false
            if ($appJson.PSObject.Properties.Name -eq "dependencies") {
                $appJson.dependencies | ForEach-Object {
                    if ($_.PSObject.Properties.Name -eq "AppId") {
                        $id = $_.AppId
                    }
                    else {
                        $id = $_.Id
                    }
                    if ($testRunnerApps.Contains($id)) { 
                        $isTestApp = $true
                    }
                }
            }
            if ($isTestApp) {
                $settings.testFolders += @($_.Name)
            }
            else {
                $settings.appFolders += @($_.Name)
            }
        }
        Write-Host "AppFolders = $($settings.appFolders)"
    }
    Write-Host "Checking appFolders and testFolders"
    $dependencies = [ordered]@{}
    $true, $false | ForEach-Object {
        $appFolder = $_
        if ($appFolder) {
            $folders = @($settings.appFolders)
            $descr = "App folder"
        }
        else {
            $folders = @($settings.testFolders)
            $descr = "Test folder"
        }
        $folders | ForEach-Object {
            $folderName = $_
            Write-Host "Folder Name = $folderName"
            if ($dependencies.Contains($folderName)) {
                throw "$descr $folderName, specified in $ALGoSettingsFile, is specified more than once."
            }
            $folder = Join-Path $baseFolder $folderName
            $appJsonFile = Join-Path $folder "app.json"
            $removeFolder = $false
            if (-not (Test-Path $folder -PathType Container)) {
                OutputWarning -message "$descr $folderName, specified in $ALGoSettingsFile, does not exist."
                $removeFolder = $true
            }
            elseif (-not (Test-Path $appJsonFile -PathType Leaf)) {
                OutputWarning -message "$descr $folderName, specified in $ALGoSettingsFile, does not contain the source code for an app (no app.json file)."
                $removeFolder = $true
            }
            if ($removeFolder) {
                if ($appFolder) {
                    $settings.appFolders = @($settings.appFolders | Where-Object { $_ -ne $folderName })
                }
                else {
                    $settings.testFolders = @($settings.testFolders | Where-Object { $_ -ne $folderName })
                }
            }
            else {
                Write-Host "Add Dependency $folderName"
                $dependencies.Add("$folderName", @())
                try {
                    $appJson = Get-Content $appJsonFile -Encoding UTF8 | ConvertFrom-Json
                    if ($appJson.PSObject.Properties.Name -eq 'Dependencies') {
                        $appJson.dependencies | ForEach-Object {
                            if ($_.PSObject.Properties.Name -eq "AppId") {
                                $id = $_.AppId
                            }
                            else {
                                $id = $_.Id
                            }
                            if ($id -eq $applicationAppId) {
                                if ([Version]$_.Version -gt [Version]$settings.applicationDependency) {
                                    $settings.applicationDependency = $appDep
                                }
                            }
                            else {
                                $dependencies."$folderName" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
                            }
                        }
                    }
                    if ($appJson.PSObject.Properties.Name -eq 'Application') {
                        $appDep = $appJson.application
                        if ([Version]$appDep -gt [Version]$settings.applicationDependency) {
                            $settings.applicationDependency = $appDep
                        }
                    }
                }
                catch {
                    throw "$descr $folderName, specified in $ALGoSettingsFile, contains a corrupt app.json file. Error is $($_.Exception.Message)."
                }
            }
        }
    }

    if (!$doNotCheckArtifactSetting) {
        Write-Host "Hello 004"
        if ([Version]$settings.applicationDependency -gt [Version]$version) {
            throw "Application dependency is set to $($settings.applicationDependency), which isn't compatible with the artifact version $version"
        }
    }

    # unpack all dependencies and update app- and test dependencies from dependency apps
    Write-Host "App Dependencies = $($settings.appDependencies)"
    $settings.appDependencies + $settings.testDependencies | ForEach-Object {
        $dep = $_
        if ($dep -is [string]) {
            Write-Host "Hello 005"
            # TODO: handle pre-settings - documentation pending
        }
    }

    Write-Host "Updating app- and test Dependencies"
    $dependencies.Keys | ForEach-Object {
        $folderName = $_
        Write-Host "Folder name 2 = $folderName"
        $appFolder = $settings.appFolders.Contains($folderName)
        if ($appFolder) { $prop = "appDependencies" } else { $prop = "testDependencies" }
        $dependencies."$_" | ForEach-Object {
            Write-Host "Hello 006"
            $id = $_.Id
            $version = $_.version
            $exists = $settings."$prop" | Where-Object { $_ -is [System.Collections.Specialized.OrderedDictionary] -and $_.id -eq $id }
            if ($exists) {
                Write-Host "Hello 007"
                if ([Version]$version -gt [Version]$exists.Version) {
                    $exists.Version = $version
                }
            }
            else {
                Write-Host "Hello 008"
                $settings."$prop" += @( [ordered]@{ "id" = $id; "version" = $_.version } )
            }
        }
    }

    Write-Host "Analyzing Test App Dependencies"
    if ($settings.testFolders) { 
        $settings.installTestRunner = $true 
    }

    $settings.appDependencies + $settings.testDependencies | ForEach-Object {
        $dep = $_
        Write-Host "Dependency = $dep"
        if ($dep.GetType().Name -eq "OrderedDictionary") {
            if ($testRunnerApps.Contains($dep.id)) { $settings.installTestRunner = $true }
            if ($testFrameworkApps.Contains($dep.id)) { $settings.installTestFramework = $true }
            if ($testLibrariesApps.Contains($dep.id)) { $settings.installTestLibraries = $true }
            if ($performanceToolkitApps.Contains($dep.id)) { $settings.installPerformanceToolkit = $true }
        }
    }

    if (-not $settings.testFolders) {
        Write-Host "Hello 009"
        OutputWarning -message "No test apps found in testFolders in $ALGoSettingsFile"
        $doNotRunTests = $true
    }
    if (-not $settings.appFolders) {
        Write-Host "Hello 010"
        OutputWarning -message "No apps found in appFolders in $ALGoSettingsFile"
    }

    $settings
    if (!$runningLocal) {
        Write-Host "::endgroup::"
    }
}

function CommitFromNewFolder {
    Param(
        [string] $serverUrl,
        [string] $commitMessage,
        [string] $branch
    )

    invoke-git add *
    if ($commitMessage.Length -gt 250) {
        $commitMessage = "$($commitMessage.Substring(0,250))...)"
    }
    invoke-git commit --allow-empty -m "'$commitMessage'"
    if ($branch) {
        invoke-git push -u $serverUrl $branch
        invoke-gh pr create --fill --base develop --head $branch --repo $env:GITHUB_REPOSITORY
        #invoke-gh pr create --fill --head $branch --repo $env:GITHUB_REPOSITORY
    }
    else {
        invoke-git push $serverUrl
    }
}


function CloneIntoNewFolder {
    Param(
        [string] $actor,
        [string] $token,
        [string] $branch
    )

    $baseFolder = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
    New-Item $baseFolder -ItemType Directory | Out-Null
    Set-Location $baseFolder
    $serverUri = [Uri]::new($env:GITHUB_SERVER_URL)
    $serverUrl = "$($serverUri.Scheme)://$($actor):$($token)@$($serverUri.Host)/$($env:GITHUB_REPOSITORY)"

    # Environment variables for hub commands
    $env:GITHUB_USER = $actor
    $env:GITHUB_TOKEN = $token

    # Configure git username and email
    invoke-git config --global user.email "$actor@users.noreply.github.com"
    invoke-git config --global user.name "$actor"

    # Configure hub to use https
    invoke-git config --global hub.protocol https

    invoke-git clone $serverUrl

    Set-Location *

    if ($branch) {
        invoke-git checkout -b $branch
    }

    Write-Host "The server URL is $($serverUrl)"

    $serverUrl
}

function invoke-git {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    $arguments = "$command "
    $remaining | ForEach-Object {
        if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
            $arguments += """$($_.Replace('"','\"'))"" "
        }
        else {
            $arguments += "$_ "
        }
    }
    cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue
}

function CmdDo {
    Param(
        [string] $command = "",
        [string] $arguments = "",
        [switch] $silent,
        [switch] $returnValue
    )

    $oldNoColor = "$env:NO_COLOR"
    $env:NO_COLOR = "Y"
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $result = $true
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.WorkingDirectory = Get-Location
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
    
        $outtask = $p.StandardOutput.ReadToEndAsync()
        $errtask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit();

        $message = $outtask.Result
        $err = $errtask.Result

        if ("$err" -ne "") {
            $message += "$err"
        }
        
        $message = $message.Trim()

        if ($p.ExitCode -eq 0) {
            if (!$silent) {
                Write-Host $message
            }
            if ($returnValue) {
                $message.Replace("`r","").Split("`n")
            }
        }
        else {
            $message += "`n`nExitCode: "+$p.ExitCode + "`nCommandline: $command $arguments"
            throw $message
        }
    }
    finally {
    #    [Console]::OutputEncoding = $oldEncoding
        $env:NO_COLOR = $oldNoColor
    }
}

function GetContainerName([string] $project) {
    "bc$($project -replace "\W")$env:GITHUB_RUN_ID"
}

function ConvertTo-HashTable() {
    [CmdletBinding()]
    Param(
        [parameter(ValueFromPipeline)]
        [PSCustomObject] $object
    )
    $ht = @{}
    if ($object) {
        $object.PSObject.Properties | Foreach { $ht[$_.Name] = $_.Value }
    }
    $ht
}