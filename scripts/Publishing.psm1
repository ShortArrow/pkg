#Requires -Version 7
<#
.SYNOPSIS
Runs one update of the registry: publishing a release, re-signing, rebuilding or withdrawing a version.
#>

Import-Module (Join-Path $PSScriptRoot 'AptIndex.psm1')
Import-Module (Join-Path $PSScriptRoot 'GitHubRelease.psm1')
Import-Module (Join-Path $PSScriptRoot 'Keyring.psm1')
Import-Module (Join-Path $PSScriptRoot 'PublishedSite.psm1')

function Get-StableReleaseEntry([object] $Release, [string] $Repository, [scriptblock] $Download, [string] $WorkDirectory) {
    $directory = Join-Path $WorkDirectory 'releases' $Repository $Release.tag_name
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    Get-ReleasePackageEntry -Repository $Repository -Tag $Release.tag_name -Assets $Release.assets `
        -Download $Download -WorkDirectory $directory
}

function Add-KeyringEntry([System.Collections.IDictionary[]] $Index, [string] $KeyringDirectory, [string] $SourceDirectory, [DateTimeOffset] $Date) {
    $newest = Select-NewestKeyringEntry -Index $Index
    if ($newest -and (Test-KeyringPackageCurrent -Package (Join-Path $SourceDirectory 'apt' $newest.Filename) -KeyringDirectory $KeyringDirectory)) {
        return $Index
    }
    $published = @($Index | Where-Object { $_.Package -eq $newest.Package } | ForEach-Object { $_.Version })
    $version = Get-NextKeyringVersion -Published $published -Date $Date.UtcDateTime
    $output = Join-Path $SourceDirectory 'apt' 'keyring'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $built = New-KeyringPackage -KeyringDirectory $KeyringDirectory -Version $version -OutputDirectory $output
    $control = & dpkg-deb -f $built.Package
    $entry = New-PackageEntry -Control @(ConvertFrom-Deb822 ($control -join "`n"))[0] -Path $built.Package `
        -Filename "keyring/$(Split-Path -Leaf $built.Package)"
    Set-PackageVersion -Index $Index -Entries @($entry)
}

function Invoke-RegistryUpdate {
    <#
    .SYNOPSIS
    Builds the next version of the site in Destination, signed, for one operation.

    .DESCRIPTION
    Publish, Resign and Withdraw start from the live site, fetched and verified by
    Import-PublishedSite; Rebuild starts from nothing and reads every stable release of every
    repository instead. Every operation then adds a keyring package when the newest one
    published does not hold exactly the keys under KeyringDirectory, and writes the site with
    Write-Site.

    - Publish replaces the entries of the release's package versions. A release GitHub marks
      as a pre-release, or whose tag carries '-', is refused. A release with no .deb asset is
      skipped: nothing is written and Skipped is set.
    - Withdraw removes every architecture of one package version.
    - Resign changes nothing but the keyring, the dates and the signature.

    .PARAMETER FetchSite
    Returns the bytes the live site serves at a path under apt/, or $null.

    .PARAMETER GetRelease
    Returns the release of a repository with a tag: tag_name, prerelease and assets, each
    asset with a name and a url.

    .PARAMETER GetReleases
    Returns every release of a repository, in the same form.

    .PARAMETER Download
    Saves the asset at a url to a path.

    .OUTPUTS
    An object with the Index written, and Skipped when nothing was written.
    #>
    param(
        [ValidateSet('Publish', 'Resign', 'Rebuild', 'Withdraw')] [string] $Operation,
        [string] $Repository,
        [string] $Tag,
        [string] $Package,
        [string] $Version,
        [string[]] $Repositories,
        [scriptblock] $FetchSite,
        [scriptblock] $GetRelease,
        [scriptblock] $GetReleases,
        [scriptblock] $Download,
        [string] $KeyringDirectory,
        [string] $Redirects,
        [string] $Destination,
        [string] $GpgHome,
        [string[]] $KeyId,
        [DateTimeOffset] $Date,
        [string] $WorkDirectory
    )

    $source = Join-Path $WorkDirectory 'site'
    if ($Operation -eq 'Rebuild') {
        $index = @()
        foreach ($repository in $Repositories) {
            foreach ($release in & $GetReleases $repository | Where-Object { Test-StableRelease -Tag $_.tag_name -Prerelease $_.prerelease }) {
                $entries = @(Get-StableReleaseEntry $release $repository $Download $WorkDirectory)
                if ($entries) { $index = @(Set-PackageVersion -Index $index -Entries $entries) }
            }
        }
    }
    else {
        $index = @(Import-PublishedSite -Fetch $FetchSite -KeyringDirectory $KeyringDirectory -Destination $source)
    }

    if ($Operation -eq 'Publish') {
        $release = & $GetRelease $Repository $Tag
        if (-not (Test-StableRelease -Tag $release.tag_name -Prerelease $release.prerelease)) {
            throw "$Repository $Tag is not a stable release."
        }
        $entries = @(Get-StableReleaseEntry $release $Repository $Download $WorkDirectory)
        if (-not $entries) {
            return [pscustomobject]@{ Index = $index; Skipped = $true }
        }
        $index = @(Set-PackageVersion -Index $index -Entries $entries)
    }
    elseif ($Operation -eq 'Withdraw') {
        $index = @(Remove-PackageVersion -Index $index -Package $Package -Version $Version)
    }

    $index = @(Add-KeyringEntry $index $KeyringDirectory $source $Date)
    Write-Site -Destination $Destination -SourceDirectory $source -Redirects $Redirects -Index $index `
        -KeyringDirectory $KeyringDirectory -Date $Date -GpgHome $GpgHome -KeyId $KeyId
    [pscustomobject]@{ Index = $index; Skipped = $false }
}

Export-ModuleMember -Function Invoke-RegistryUpdate
