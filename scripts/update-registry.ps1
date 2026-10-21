#Requires -Version 7
<#
.SYNOPSIS
Builds the next version of the site for one operation, against the live site and GitHub, signed with SIGNING_KEY.

.DESCRIPTION
Reads the signing keys from the SIGNING_KEY environment variable and the projects from
projects.json. Writes the site to Destination unless the operation is skipped, and, when run
in GitHub Actions, sets the step outputs `deployed` (true or false) and `packages`: one line
'<package> <version> <upstream version> <check command>' per package version a publish
added.

.PARAMETER Operation
Publish, Resign, Rebuild or Withdraw, as Invoke-RegistryUpdate describes them.

.PARAMETER KeyringDirectory
The public keys the live site is verified against and the keyring is built from; this
repository's keyring/ by default.
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('Publish', 'Resign', 'Rebuild', 'Withdraw')]
    [string] $Operation,

    [string] $Repository,
    [string] $Tag,
    [string] $Package,
    [string] $Version,

    [Parameter(Mandatory)]
    [string] $Destination,

    [string] $BaseUrl = 'https://pkg.shortarrow.jp/apt',

    [string] $KeyringDirectory = (Join-Path $PSScriptRoot '..' 'keyring')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Join-Path $PSScriptRoot '..'
Import-Module (Join-Path $PSScriptRoot 'AptRelease.psm1')
Import-Module (Join-Path $PSScriptRoot 'Publishing.psm1')

$projects = Get-Content -Raw (Join-Path $root 'projects.json') | ConvertFrom-Json
if ($Operation -eq 'Publish' -and $Repository -notin $projects.repository) {
    throw "$Repository is not a project of this registry; projects.json lists $($projects.repository -join ', ')."
}

$api = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
if ($env:GITHUB_TOKEN) { $api.Authorization = "Bearer $env:GITHUB_TOKEN" }

function ConvertTo-Release($Response) {
    [pscustomobject]@{
        tag_name   = $Response.tag_name
        prerelease = $Response.prerelease
        assets     = @($Response.assets | ForEach-Object { [pscustomobject]@{ name = $_.name; url = $_.browser_download_url } })
    }
}

$client = [System.Net.Http.HttpClient]::new()
$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$gpgHome = Join-Path $work 'gnupg'
New-Item -ItemType Directory -Path $gpgHome | Out-Null
try {
    $keyId = @(Import-SigningKey -ArmoredKey $env:SIGNING_KEY -GpgHome $gpgHome)

    $result = Invoke-RegistryUpdate -Operation $Operation -Repository $Repository -Tag $Tag `
        -Package $Package -Version $Version -Repositories $projects.repository `
        -FetchSite {
            param([string] $Path)
            $response = $client.GetAsync("$($BaseUrl.TrimEnd('/'))/$Path").GetAwaiter().GetResult()
            if ($response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) { return $null }
            $response.EnsureSuccessStatusCode() | Out-Null
            , $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        } `
        -GetRelease {
            param([string] $Repository, [string] $Tag)
            ConvertTo-Release (Invoke-RestMethod -Headers $api "https://api.github.com/repos/ShortArrow/$Repository/releases/tags/$Tag")
        } `
        -GetReleases {
            param([string] $Repository)
            for ($page = 1; ; $page++) {
                $releases = Invoke-RestMethod -Headers $api "https://api.github.com/repos/ShortArrow/$Repository/releases?per_page=100&page=$page"
                if (-not $releases) { break }
                $releases | ForEach-Object { ConvertTo-Release $_ }
            }
        } `
        -Download { param([string] $Url, [string] $Path) Invoke-WebRequest -Uri $Url -OutFile $Path } `
        -KeyringDirectory $KeyringDirectory -Redirects (Join-Path $root 'public' '_redirects') `
        -Destination $Destination -GpgHome $gpgHome -KeyId $keyId -Date ([DateTimeOffset]::UtcNow) `
        -WorkDirectory $work

    $published = if ($Operation -eq 'Publish' -and -not $result.Skipped) {
        $check = ($projects | Where-Object repository -EQ $Repository).check
        $result.Index | Where-Object { $_.Filename -like "pool/$Repository/$Tag/*" } |
            ForEach-Object { "$($_.Package) $($_.Version) $($Tag -replace '^v') $check" } | Sort-Object -Unique
    }
    if ($result.Skipped) { Write-Output "$Repository $Tag has no packages; nothing to deploy." }
    if ($env:GITHUB_OUTPUT) {
        "deployed=$(([string] -not $result.Skipped).ToLowerInvariant())" | Add-Content $env:GITHUB_OUTPUT
        $delimiter = [guid]::NewGuid()
        @("packages<<$delimiter") + @($published) + @("$delimiter") | Add-Content $env:GITHUB_OUTPUT
    }
}
finally {
    $client.Dispose()
    & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
