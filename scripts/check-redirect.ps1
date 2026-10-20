#Requires -Version 7
<#
.SYNOPSIS
Asserts that a pool path on the registry answers 302 to the matching GitHub release asset.

.PARAMETER BaseUrl
The registry to check, such as https://pkg.shortarrow.jp or http://127.0.0.1:8787 for `wrangler dev`.
#>
param(
    [Parameter(Mandatory)]
    [string] $BaseUrl
)

$ErrorActionPreference = 'Stop'

$path = 'apt/pool/ivi-cli/v0.4.0/SHA256SUMS'
$want = 'https://github.com/ShortArrow/ivi-cli/releases/download/v0.4.0/SHA256SUMS'
$url = "$($BaseUrl.TrimEnd('/'))/$path"

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [System.Net.Http.HttpClient]::new($handler)
try {
    $response = $client.SendAsync([System.Net.Http.HttpRequestMessage]::new('HEAD', $url)).GetAwaiter().GetResult()
    $status = [int] $response.StatusCode
    $location = [string] $response.Headers.Location
}
finally {
    $client.Dispose()
}

if ($status -ne 302 -or $location -ne $want) {
    Write-Error "FAIL: $url -> $status $location (want 302 $want)"
}
Write-Output "OK: $url -> 302 $location"
