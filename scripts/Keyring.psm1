#Requires -Version 7
<#
.SYNOPSIS
Builds the shortarrow-archive-keyring package from the public keys under keyring/.
#>

$packageName = 'shortarrow-archive-keyring'
$installedPath = 'usr/share/keyrings/shortarrow-archive-keyring.gpg'

function Get-NextKeyringVersion {
    <#
    .SYNOPSIS
    Returns the version for a keyring built on Date: the date and a counter that starts at 1 each day.
    #>
    param(
        [AllowEmptyCollection()] [string[]] $Published,
        [DateTime] $Date
    )

    $day = $Date.ToString('yyyy.MM.dd', [cultureinfo]::InvariantCulture)
    $counters = @($Published | Where-Object { $_ -like "$day.*" } | ForEach-Object { [int] $_.Substring($day.Length + 1) })
    $highest = ($counters | Measure-Object -Maximum).Maximum ?? 0
    "$day.$($highest + 1)"
}

function Write-BinaryKeyring {
    <#
    .SYNOPSIS
    Writes every *.asc key in KeyringDirectory, in file name order and dearmored, to one binary keyring at Path.

    .DESCRIPTION
    This is the form APT's signed-by and gpgv's --keyring read. Needs gpg; the caller's
    GnuPG home is not touched.
    #>
    param(
        [string] $KeyringDirectory,
        [string] $Path
    )

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $keys = foreach ($asc in Get-ChildItem $KeyringDirectory -Filter '*.asc' | Sort-Object Name) {
            $binary = Join-Path $work "$($asc.BaseName).gpg"
            $output = & gpg --homedir $work --batch --yes --output $binary --dearmor $asc.FullName 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Dearmoring $($asc.Name) failed: $($output | Out-String)" }
            [System.IO.File]::ReadAllBytes($binary)
        }
        if (-not $keys) { throw "$KeyringDirectory holds no *.asc key." }
        [System.IO.File]::WriteAllBytes($Path, [byte[]] $keys)
    }
    finally {
        & gpgconf --homedir $work --kill gpg-agent 2>$null
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

function Get-KeyringControl([string] $Version) {
    @(
        "Package: $packageName"
        "Version: $Version"
        'Architecture: all'
        'Maintainer: ShortArrow <bamboogeneral@shortarrow.jp>'
        'Section: misc'
        'Priority: optional'
        'Multi-Arch: foreign'
        'Description: GnuPG keys of the pkg.shortarrow.jp APT repository'
        ' The public keys that sign https://pkg.shortarrow.jp/apt, the signing key'
        ' and the standby key that replaces it.'
    ) -join "`n"
}

function New-KeyringPackage {
    <#
    .SYNOPSIS
    Writes the binary keyring and the keyring package for the public keys in KeyringDirectory.

    .DESCRIPTION
    The keyring holds every *.asc key in KeyringDirectory, in file name order, dearmored. The
    package installs it at /usr/share/keyrings/shortarrow-archive-keyring.gpg, the path the
    source line names. Needs gpg and dpkg-deb.

    .OUTPUTS
    An object whose Keyring is the path of the keyring file and Package that of the .deb,
    both in OutputDirectory.
    #>
    param(
        [string] $KeyringDirectory,
        [string] $Version,
        [string] $OutputDirectory
    )

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $keyring = Join-Path $OutputDirectory "$packageName.gpg"
        Write-BinaryKeyring -KeyringDirectory $KeyringDirectory -Path $keyring

        $root = Join-Path $work 'root'
        $installed = Join-Path $root $installedPath
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'DEBIAN'), (Split-Path $installed) | Out-Null
        Copy-Item $keyring $installed
        [System.IO.File]::WriteAllText((Join-Path $root 'DEBIAN' 'control'), (Get-KeyringControl $Version) + "`n")
        & chmod -R u=rwX,go=rX $root

        $package = Join-Path $OutputDirectory "${packageName}_${Version}_all.deb"
        $output = & dpkg-deb --root-owner-group --build $root $package 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Building $package failed: $($output | Out-String)" }

        [pscustomobject]@{ Keyring = $keyring; Package = $package }
    }
    finally {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-NextKeyringVersion, Write-BinaryKeyring, New-KeyringPackage
