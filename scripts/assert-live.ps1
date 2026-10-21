#Requires -Version 7
<#
.SYNOPSIS
Waits until the live site serves the InRelease just signed, and fails if it never does.

.DESCRIPTION
A deployment that reports success while the old index is still served fails here. A client
would otherwise accept the old index until it expires.

.PARAMETER Expected
The InRelease file that was signed and deployed.
#>
param(
    [Parameter(Mandatory)]
    [string] $Expected,

    [string] $BaseUrl = 'https://pkg.shortarrow.jp/apt',

    [int] $Attempts = 12,

    [int] $DelaySeconds = 10
)

$ErrorActionPreference = 'Stop'
$want = [System.IO.File]::ReadAllBytes($Expected)
$url = "$($BaseUrl.TrimEnd('/'))/dists/stable/InRelease"
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $response = Invoke-WebRequest -SkipHttpErrorCheck -Headers @{ 'Cache-Control' = 'no-cache' } $url
    if ($response.StatusCode -eq 200 -and [System.Linq.Enumerable]::SequenceEqual([byte[]] $response.Content, $want)) {
        Write-Output "OK: $url serves the InRelease just signed."
        return
    }
    Write-Output "Attempt $attempt of $($Attempts): $url answered $($response.StatusCode) with another InRelease."
    Start-Sleep -Seconds $DelaySeconds
}
throw "$url does not serve the InRelease just signed."
