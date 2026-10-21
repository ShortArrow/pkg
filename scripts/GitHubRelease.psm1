#Requires -Version 7
<#
.SYNOPSIS
Decides which GitHub Releases of a project enter the index, and checks their assets.
#>

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

Export-ModuleMember -Function Test-StableRelease, ConvertFrom-Sha256Sums, Assert-Sha256Sum
