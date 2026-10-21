#Requires -Version 7
<#
.SYNOPSIS
Prints '<repository> <tag>' for every release the hourly poll should start a publishing run for.

.DESCRIPTION
Reads the projects from projects.json, the published index from the live site's Packages
files, and the names of the publishing runs already started from `gh run list`. The live
index is read without verifying its signature: it only decides which runs to start, and every
run verifies the site before it signs anything. Prints nothing while the site has no index,
since only a rebuild creates it.
#>
param(
    [string] $BaseUrl = 'https://pkg.shortarrow.jp/apt'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AptIndex.psm1')
Import-Module (Join-Path $PSScriptRoot 'GitHubRelease.psm1')

$api = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
if ($env:GITHUB_TOKEN) { $api.Authorization = "Bearer $env:GITHUB_TOKEN" }

$indexes = foreach ($architecture in 'amd64', 'arm64') {
    $response = Invoke-WebRequest -SkipHttpErrorCheck "$($BaseUrl.TrimEnd('/'))/dists/stable/main/binary-$architecture/Packages"
    if ($response.StatusCode -eq 404) {
        Write-Warning 'The site has no index yet; a rebuild creates it.'
        return
    }
    if ($response.StatusCode -ne 200) { throw "Fetching Packages for $architecture answered $($response.StatusCode)." }
    , @(ConvertFrom-Deb822 ([System.Text.Encoding]::UTF8.GetString($response.Content)))
}
$index = @(Join-PackageIndex $indexes)

$started = @(& gh run list --workflow publish.yml --limit 1000 --json displayTitle --jq '.[].displayTitle')
if ($LASTEXITCODE -ne 0) { throw 'Listing the publishing runs failed.' }

$projects = Get-Content -Raw (Join-Path $PSScriptRoot '..' 'projects.json') | ConvertFrom-Json
foreach ($repository in $projects.repository) {
    $releases = Invoke-RestMethod -Headers $api "https://api.github.com/repos/ShortArrow/$repository/releases?per_page=100"
    Find-UnpublishedRelease -Repository $repository -Releases $releases -Index $index -StartedRuns $started |
        ForEach-Object { "$repository $_" }
}
