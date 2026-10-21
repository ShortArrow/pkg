#Requires -Version 7
<#
.SYNOPSIS
Writes the Release file of the repository's one suite.
#>

$rfc2822 = 'ddd, dd MMM yyyy HH:mm:ss'

function Format-ReleaseDate([DateTimeOffset] $Date) {
    $Date.UtcDateTime.ToString($rfc2822, [cultureinfo]::InvariantCulture) + ' UTC'
}

function New-ReleaseText {
    <#
    .SYNOPSIS
    Returns the Release text for the suite directory, listing the SHA-256 and size of every index file in it.

    .DESCRIPTION
    The suite is `stable` with the one component `main`. Architectures are those that have a
    `main/binary-<arch>` directory. `Valid-Until` is 90 days after Date, so a client refuses
    metadata that has not been re-signed for that long. Release and InRelease themselves are
    not listed, and nothing is written.
    #>
    param(
        [string] $SuiteDirectory,
        [DateTimeOffset] $Date
    )

    $suite = (Resolve-Path $SuiteDirectory).Path
    $architectures = Get-ChildItem (Join-Path $suite 'main') -Directory -Filter 'binary-*' |
        ForEach-Object { $_.Name -replace '^binary-' } | Sort-Object
    $files = Get-ChildItem $suite -Recurse -File |
        Where-Object { $_.Name -notin 'Release', 'InRelease' } |
        ForEach-Object {
            $relative = [System.IO.Path]::GetRelativePath($suite, $_.FullName) -replace '\\', '/'
            $hash = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant()
            " $hash $($_.Length) $relative"
        } | Sort-Object { $_.Split(' ')[3] }

    $lines = @(
        'Origin: pkg.shortarrow.jp'
        'Label: ShortArrow'
        'Suite: stable'
        'Codename: stable'
        "Date: $(Format-ReleaseDate $Date)"
        "Valid-Until: $(Format-ReleaseDate $Date.AddDays(90))"
        "Architectures: $($architectures -join ' ')"
        'Components: main'
        'SHA256:'
        $files
    )
    ($lines -join "`n") + "`n"
}

function Write-SignedRelease {
    <#
    .SYNOPSIS
    Writes Release for the suite directory and InRelease, the same text clearsigned by every given key.

    .DESCRIPTION
    Release is written as UTF-8 without a byte order mark and with LF line ends, as APT
    reads it. While a new signing key is being introduced, both keys sign, so a client whose
    keyring holds either one verifies InRelease.

    .PARAMETER GpgHome
    A GnuPG home holding the secret half of every key in KeyId, without a passphrase.

    .PARAMETER KeyId
    The fingerprints of the signing keys.
    #>
    param(
        [string] $SuiteDirectory,
        [DateTimeOffset] $Date,
        [string] $GpgHome,
        [string[]] $KeyId
    )

    $text = New-ReleaseText -SuiteDirectory $SuiteDirectory -Date $Date
    $release = Join-Path $SuiteDirectory 'Release'
    [System.IO.File]::WriteAllText($release, $text, [System.Text.UTF8Encoding]::new($false))

    $signers = $KeyId | ForEach-Object { '--local-user', "$_!" }
    $output = & gpg --homedir $GpgHome --batch --yes --pinentry-mode loopback --passphrase '' `
        --digest-algo SHA512 @signers --clearsign --output (Join-Path $SuiteDirectory 'InRelease') $release 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Signing InRelease failed: $($output | Out-String)"
    }
}

Export-ModuleMember -Function New-ReleaseText, Write-SignedRelease
