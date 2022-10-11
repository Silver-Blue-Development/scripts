
$credential = $host.ui.PromptForCredential("Need credentials", "Please enter your user name and password.", "", "NetBiosUserName")
$appFile = "C:\Users\Petra Driessen\Documents\Default publisher_ALProject1_1.0.0.0.app" 
$devEndpointUri = "http:\\EIN-PEDR02-L10" 
$devPort = 7049 
$instanceName = "BC190"

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
