#Requires -Version 7
<#
.SYNOPSIS
Fetches the published site and verifies every file of it before anything is built on it.
#>

Import-Module (Join-Path $PSScriptRoot 'AptIndex.psm1')
Import-Module (Join-Path $PSScriptRoot 'Keyring.psm1')
Import-Module (Join-Path $PSScriptRoot 'AptRelease.psm1')

$architectures = 'amd64', 'arm64'

function Save-SiteFile([string] $Destination, [string] $Path, [byte[]] $Bytes) {
    $file = Join-Path $Destination 'apt' $Path
    New-Item -ItemType Directory -Force -Path (Split-Path $file) | Out-Null
    [System.IO.File]::WriteAllBytes($file, $Bytes)
    $file
}

function Get-SiteFile([scriptblock] $Fetch, [string] $Path) {
    $bytes = & $Fetch $Path
    if ($null -eq $bytes) { throw "The site does not serve $Path." }
    [byte[]] $bytes
}

function Assert-Digest([byte[]] $Bytes, [string] $Size, [string] $Sha256, [string] $Path) {
    $actual = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    if ([string] $Bytes.Length -ne $Size -or $actual -ne $Sha256) {
        throw "$Path does not match its signed entry: $($Bytes.Length) bytes, SHA-256 $actual; listed $Size bytes, $Sha256."
    }
}

function Get-VerifiedText([string] $InRelease, [string] $KeyringDirectory) {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $keyring = Join-Path $work 'trusted.gpg'
        Write-BinaryKeyring -KeyringDirectory $KeyringDirectory -Path $keyring
        $signed = Join-Path $work 'Release'
        # gpgv 2.5 on Windows verifies but does not write --output, so gpg extracts the signed text.
        $status = & gpg --homedir $work --batch --yes --no-default-keyring --keyring $keyring `
            --status-fd 1 --output $signed --decrypt $InRelease 2>$null
        $valid = $status | Where-Object { $_ -like '`[GNUPG:`] VALIDSIG *' }
        $bad = $status | Where-Object { $_ -like '`[GNUPG:`] BADSIG *' }
        if (-not $valid -or $bad -or -not (Test-Path $signed)) {
            throw "InRelease is not signed by a key under $KeyringDirectory."
        }
        [System.IO.File]::ReadAllText($signed)
    }
    finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

function Import-PublishedSite {
    <#
    .SYNOPSIS
    Fetches InRelease, the index files and every file the site serves itself, verifies each, and returns the index.

    .DESCRIPTION
    InRelease must carry a valid signature by a key under KeyringDirectory. Every file Release
    lists must match its size and SHA-256 there, and every package whose Filename is not under
    pool/ must match its Packages entry. Packages under pool/ are redirected to GitHub and
    never fetched. The first failure throws, so nothing unverified is signed again.

    .PARAMETER Fetch
    Returns the bytes of a path relative to the repository's base URL, or $null when the site
    does not serve it.

    .PARAMETER Destination
    Where the fetched files are saved, under apt/ at the paths the site serves them.

    .OUTPUTS
    The entries of every architecture's Packages, merged by Join-PackageIndex.
    #>
    param(
        [scriptblock] $Fetch,
        [string] $KeyringDirectory,
        [string] $Destination
    )

    $inReleaseBytes = & $Fetch 'dists/stable/InRelease'
    if ($null -eq $inReleaseBytes) {
        throw 'The site serves no dists/stable/InRelease; a rebuild creates the repository.'
    }
    $inRelease = Save-SiteFile $Destination 'dists/stable/InRelease' $inReleaseBytes
    $release = @(ConvertFrom-Deb822 (Get-VerifiedText $inRelease $KeyringDirectory))[0]

    $indexes = @()
    foreach ($line in $release.SHA256 -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) {
        $sha256, $size, $relative = $line -split '\s+'
        $path = "dists/stable/$relative"
        $bytes = Get-SiteFile $Fetch $path
        Assert-Digest $bytes $size $sha256 $path
        $file = Save-SiteFile $Destination $path $bytes
        if ($relative -match '^main/binary-[^/]+/Packages$') {
            $indexes += , @(ConvertFrom-Deb822 ([System.IO.File]::ReadAllText($file)))
        }
    }

    $index = @(Join-PackageIndex $indexes)
    foreach ($entry in $index | Where-Object { $_.Filename -notlike 'pool/*' }) {
        $bytes = Get-SiteFile $Fetch $entry.Filename
        Assert-Digest $bytes $entry.Size $entry.SHA256 $entry.Filename
        Save-SiteFile $Destination $entry.Filename $bytes | Out-Null
    }
    $index
}

function Write-Gzip([string] $Path, [byte[]] $Bytes) {
    $stream = [System.IO.Compression.GZipStream]::new([System.IO.File]::Create($Path), [System.IO.Compression.CompressionLevel]::SmallestSize)
    try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
}

function New-FrontPage([string] $KeyringDirectory) {
    $keys = foreach ($key in Get-KeyringKey -KeyringDirectory $KeyringDirectory) {
        $fingerprint = $key.Fingerprint -replace '(.{4})(?!$)', '$1 '
        "<li><code>$fingerprint</code><br>$([System.Net.WebUtility]::HtmlEncode($key.UserId))</li>"
    }
    @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>pkg.shortarrow.jp</title>
<style>
body { font-family: system-ui, sans-serif; line-height: 1.5; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; }
code { font-family: ui-monospace, monospace; }
@media (prefers-color-scheme: dark) { body { background: #111; color: #ddd; } a { color: #8ab4f8; } }
</style>
</head>
<body>
<h1>pkg.shortarrow.jp</h1>
<p>The APT repository of ShortArrow's command-line tools, at <code>https://pkg.shortarrow.jp/apt</code>.
It is maintained by <a href="https://github.com/ShortArrow">ShortArrow</a> and built from
<a href="https://github.com/ShortArrow/pkg">ShortArrow/pkg</a>, which gives the install steps.</p>
<h2>Keys</h2>
<p><a href="/apt/shortarrow-archive-keyring.gpg">shortarrow-archive-keyring.gpg</a> holds these public keys.
The signing key signs the repository; the standby key takes over when the signing key has to be replaced.</p>
<p>To check a downloaded keyring, compare the fingerprints this prints with the ones below:</p>
<pre><code>curl -fsSL https://pkg.shortarrow.jp/apt/shortarrow-archive-keyring.gpg | gpg --show-keys</code></pre>
<ul>
$($keys -join "`n")
</ul>
</body>
</html>

"@
}

function Write-Site {
    <#
    .SYNOPSIS
    Writes the whole site to deploy into an empty Destination, and signs its index.

    .DESCRIPTION
    The site holds the redirects at its root, and under apt/ the keyring built from
    KeyringDirectory, every file the index names off pool/, and for amd64 and arm64 a Packages
    and Packages.gz with that architecture's entries and the architecture-independent ones.
    A file the index does not name is not carried over, because a deployed version serves
    only the files it lists.

    .PARAMETER SourceDirectory
    Holds every file the index names off pool/ at apt/<Filename>, as Import-PublishedSite
    saves them and new keyring packages are added.

    .PARAMETER Redirects
    The _redirects file, copied to the root of the site.
    #>
    param(
        [string] $Destination,
        [string] $SourceDirectory,
        [string] $Redirects,
        [System.Collections.IDictionary[]] $Index,
        [string] $KeyringDirectory,
        [DateTimeOffset] $Date,
        [string] $GpgHome,
        [string[]] $KeyId
    )

    if ((Test-Path $Destination) -and (Get-ChildItem -Force $Destination)) {
        throw "$Destination is not empty."
    }
    $apt = Join-Path $Destination 'apt'
    $suite = Join-Path $apt 'dists' 'stable'
    New-Item -ItemType Directory -Force -Path $suite | Out-Null
    Copy-Item $Redirects (Join-Path $Destination '_redirects')
    [System.IO.File]::WriteAllText((Join-Path $Destination 'index.html'), ((New-FrontPage $KeyringDirectory) -replace "`r`n", "`n"))
    Write-BinaryKeyring -KeyringDirectory $KeyringDirectory -Path (Join-Path $apt 'shortarrow-archive-keyring.gpg')

    foreach ($entry in $Index | Where-Object { $_.Filename -notlike 'pool/*' }) {
        $source = Join-Path $SourceDirectory 'apt' $entry.Filename
        if (-not (Test-Path $source)) { throw "The source does not hold $($entry.Filename)." }
        $target = Join-Path $apt $entry.Filename
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item $source $target
    }

    foreach ($architecture in $architectures) {
        $binary = Join-Path $suite 'main' "binary-$architecture"
        New-Item -ItemType Directory -Force -Path $binary | Out-Null
        $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Deb822 @(Select-ArchitectureIndex -Index $Index -Architecture $architecture)))
        [System.IO.File]::WriteAllBytes((Join-Path $binary 'Packages'), $bytes)
        Write-Gzip (Join-Path $binary 'Packages.gz') $bytes
    }

    Write-SignedRelease -SuiteDirectory $suite -Date $Date -GpgHome $GpgHome -KeyId $KeyId
}

Export-ModuleMember -Function Import-PublishedSite, Write-Site
