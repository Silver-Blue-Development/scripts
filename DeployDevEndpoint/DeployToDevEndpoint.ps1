Param(
    [Parameter(HelpMessage = "Tenants to install the app in", Mandatory = $true)]
    [string[]] $tenants,
    [Parameter(HelpMessage = "Environment to publish the app in", Mandatory = $true)]
    [ValidateSet('T','A')]
    [string[]] $environments,
    [Parameter(HelpMessage = "The Artifcats folder", Mandatory = $true)]
    [string] $repoName
)

$credential = New-Object System.Management.Automation.PSCredential ("user", ("password" | ConvertTo-SecureString -AsPlainText -Force))

Get-ChildItem "Z:\" -Filter *.app | 
Foreach-Object 
{
    $filePath = "Z:\$($_)"
    Publish-AppToDevEndPoint -appFile $filePath -credential $credential -devEndpointUri "http:\\localhost" -devPort 7049 -instanceName BC

    function Publish-AppToDevEndpoint {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateScript( { Test-Path "$_" })]
            [String]
            $appFile,
            [Parameter(Mandatory = $true)]
            [PSCredential]
            $credential,
            [Parameter(Mandatory=$true)]
            [ValidatePattern('http[s]?://.*')]
            [String]
            $devEndpointUri,
            [Parameter(Mandatory=$true)]
            [int]
            $devPort,
            [Parameter(Mandatory=$true)]
            [string]
            $instanceName
        )
        Add-Type -AssemblyName System.Net.Http
        $handler = New-Object System.Net.Http.HttpClientHandler
        $HttpClient = [System.Net.Http.HttpClient]::new($handler)
        $pair = ("$($Credential.UserName):" + [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)))
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [System.Convert]::ToBase64String($bytes)
        $HttpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Basic", $base64);
        $HttpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
        $HttpClient.DefaultRequestHeaders.ExpectContinue = $false
        
        $url = "$($devEndpointUri):$port/$instanceName/dev/apps?SchemaUpdateMode=forcesync"
        
        $appName = [System.IO.Path]::GetFileName("$appFile")
        
        $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
        $FileStream = [System.IO.FileStream]::new("$appFile", [System.IO.FileMode]::Open)
        try {
            $fileHeader = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
            $fileHeader.Name = "$AppName"
            $fileHeader.FileName = "$appName"
            $fileHeader.FileNameStar = "$appName"
            $fileContent = [System.Net.Http.StreamContent]::new($FileStream)
            $fileContent.Headers.ContentDisposition = $fileHeader
            $multipartContent.Add($fileContent)
            Write-Host "Publishing $appName to $url"
            $result = $HttpClient.PostAsync($url, $multipartContent).GetAwaiter().GetResult()
            if (!$result.IsSuccessStatusCode) {
                $message = "Status Code $($result.StatusCode) : $($result.ReasonPhrase)"
                try {
                    $resultMsg = $result.Content.ReadAsStringAsync().Result
                    try {
                        $json = $resultMsg | ConvertFrom-Json
                        $message += "`n$($json.Message)"
                    }
                    catch {
                        $message += "`n$resultMsg"
                    }
                }
                catch {}
                throw $message
            }
            else {
                Write-Host "Success: $appName was published and installed"
            }
        }
        finally {
            $FileStream.Close()
        }
    }
}