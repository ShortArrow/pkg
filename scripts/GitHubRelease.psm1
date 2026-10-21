#Requires -Version 7
<#
.SYNOPSIS
Decides which GitHub Releases of a project enter the index, and checks their assets.
#>

Import-Module (Join-Path $PSScriptRoot 'AptIndex.psm1')

function Test-StableRelease {
    <#
    .SYNOPSIS
    Tells whether a release is stable: not marked as a pre-release, and no '-' after the version in its tag.

    .DESCRIPTION
    The check is on the tag, not on a package's Version, which carries the Debian revision
    ('0.5.0-1'). A version with '-' would sort after its final release in Debian's ordering.
    #>
    param(
        [string] $Tag,
        [bool] $Prerelease
    )

    -not $Prerelease -and $Tag -notmatch '-'
}

function ConvertFrom-Sha256Sums {
    <#
    .SYNOPSIS
    Parses the text of a SHA256SUMS asset into a map from file name to lower-case hash.
    #>
    param([string] $Text)

    $sums = @{}
    foreach ($line in $Text -split "`r?`n" | Where-Object { $_ }) {
        if ($line -notmatch '^([0-9A-Fa-f]{64}) [ *](.+)$') {
            throw "SHA256SUMS line is not a hash and a file name: '$line'"
        }
        $sums[$Matches[2]] = $Matches[1].ToLowerInvariant()
    }
    $sums
}

function Assert-Sha256Sum {
    <#
    .SYNOPSIS
    Throws unless the file's SHA-256 is the one SHA256SUMS lists for its name.
    #>
    param(
        [string] $Path,
        [hashtable] $Sums
    )

    $name = Split-Path -Leaf $Path
    if (-not $Sums.ContainsKey($name)) {
        throw "SHA256SUMS does not list $name."
    }
    $actual = (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant()
    if ($actual -ne $Sums[$name]) {
        throw "$name does not match SHA256SUMS: $actual, listed $($Sums[$name])."
    }
}

function Get-ReleasePackageEntry {
    <#
    .SYNOPSIS
    Downloads a release's packages and SHA256SUMS, checks each package, and returns its index entries.

    .DESCRIPTION
    A release with no .deb asset, such as one made before its project built packages, yields
    nothing and downloads nothing. One with .deb assets but no SHA256SUMS is refused, and so
    is a package that does not match it. Each entry carries the package's own control fields,
    read with dpkg-deb, and the Filename pool/<Repository>/<Tag>/<asset>, which the site
    redirects to the release asset.

    .PARAMETER Assets
    The release's assets, each with a name and a url.

    .PARAMETER Download
    Saves the asset at the given url to the given path.
    #>
    param(
        [string] $Repository,
        [string] $Tag,
        [object[]] $Assets,
        [scriptblock] $Download,
        [string] $WorkDirectory
    )

    $packages = @($Assets | Where-Object { $_.name -like '*.deb' })
    if (-not $packages) { return }
    $sumsAsset = $Assets | Where-Object { $_.name -eq 'SHA256SUMS' }
    if (-not $sumsAsset) {
        throw "$Repository $Tag has packages but no SHA256SUMS."
    }

    $sumsPath = Join-Path $WorkDirectory 'SHA256SUMS'
    & $Download $sumsAsset.url $sumsPath
    $sums = ConvertFrom-Sha256Sums ([System.IO.File]::ReadAllText($sumsPath))
    foreach ($asset in $packages | Sort-Object name) {
        $path = Join-Path $WorkDirectory $asset.name
        & $Download $asset.url $path
        Assert-Sha256Sum -Path $path -Sums $sums
        $control = & dpkg-deb -f $path
        if ($LASTEXITCODE -ne 0) { throw "Reading the control fields of $($asset.name) failed." }
        New-PackageEntry -Control @(ConvertFrom-Deb822 ($control -join "`n"))[0] -Path $path `
            -Filename "pool/$Repository/$Tag/$($asset.name)"
    }
}

function Find-UnpublishedRelease {
    <#
    .SYNOPSIS
    Returns the tags of a repository's releases that the hourly poll should start a publishing run for.

    .DESCRIPTION
    A release qualifies when it is stable, has a .deb asset, has no entry under
    pool/<Repository>/<tag>/ in the index, and no run named 'publish <Repository> <tag>' was
    ever started. A run that waits for approval, was rejected or failed is therefore not
    started again; it is repeated by hand.

    .PARAMETER StartedRuns
    The names of every publishing run started so far.
    #>
    param(
        [string] $Repository,
        [object[]] $Releases,
        [AllowEmptyCollection()] [System.Collections.IDictionary[]] $Index,
        [AllowEmptyCollection()] [string[]] $StartedRuns
    )

    foreach ($release in $Releases) {
        $tag = $release.tag_name
        if (-not (Test-StableRelease -Tag $tag -Prerelease $release.prerelease)) { continue }
        if (-not ($release.assets | Where-Object { $_.name -like '*.deb' })) { continue }
        if ($Index | Where-Object { $_.Filename -like "pool/$Repository/$tag/*" }) { continue }
        if ("publish $Repository $tag" -in $StartedRuns) { continue }
        $tag
    }
}

Export-ModuleMember -Function Test-StableRelease, ConvertFrom-Sha256Sums, Assert-Sha256Sum, Get-ReleasePackageEntry, Find-UnpublishedRelease
