#Requires -Version 7
<#
.SYNOPSIS
Fetches the published site and verifies every file of it before anything is built on it.
#>

Import-Module (Join-Path $PSScriptRoot 'AptIndex.psm1')
Import-Module (Join-Path $PSScriptRoot 'Keyring.psm1')

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

Export-ModuleMember -Function Import-PublishedSite
