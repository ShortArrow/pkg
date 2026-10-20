#Requires -Version 7
<#
.SYNOPSIS
Generates the repository's signing key and standby key in a throwaway GnuPG home.

.DESCRIPTION
Both keys are Ed25519. The signing key expires three years after creation and has no
passphrase, because it lives only in the `publish` environment's secrets. The standby key
never expires until it is promoted, and is protected by the given passphrase for offline
storage.

The public half of each key is written to the keyring directory as <fingerprint>.asc.
The secret directory receives signing.secret.asc, standby.secret.asc and one
<fingerprint>.rev revocation certificate per key. Nothing is written to the caller's
GnuPG home, and the throwaway home is deleted afterwards.

.PARAMETER KeyringDirectory
Where the public keys go; this repository's keyring/ by default.

.PARAMETER SecretDirectory
Where the secret keys and revocation certificates go. Must be outside the repository.

.PARAMETER StandbyPassphrase
The standby key's passphrase. Prompted for when omitted.
#>
param(
    [string] $KeyringDirectory = (Join-Path $PSScriptRoot '..' 'keyring'),

    [Parameter(Mandatory)]
    [string] $SecretDirectory,

    [securestring] $StandbyPassphrase
)

$ErrorActionPreference = 'Stop'

$signingUid = 'pkg.shortarrow.jp repository signing key'
$standbyUid = 'pkg.shortarrow.jp repository standby key'

function Assert-OutsideRepository([string] $Path) {
    $repository = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $full = [System.IO.Path]::GetFullPath($Path)
    $prefix = $repository.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($full -eq $repository -or $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "SecretDirectory must be outside the repository: $full"
    }
}

function Invoke-Gpg([string[]] $Arguments, [string] $Passphrase) {
    $all = @('--homedir', $gpgHome, '--batch', '--yes', '--pinentry-mode', 'loopback', '--passphrase-fd', '0') + $Arguments
    $output = $Passphrase | & gpg @all 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gpg $($Arguments -join ' ') failed: $($output | Out-String)"
    }
    $output
}

function Get-Fingerprint([string] $Uid) {
    $lines = & gpg --homedir $gpgHome --batch --with-colons --list-keys "=$Uid"
    ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
}

Assert-OutsideRepository $SecretDirectory
if (-not $StandbyPassphrase) {
    $StandbyPassphrase = Read-Host -AsSecureString -Prompt 'Standby key passphrase'
}
$standbySecret = ConvertFrom-SecureString $StandbyPassphrase -AsPlainText
if ([string]::IsNullOrEmpty($standbySecret)) {
    throw 'The standby key needs a passphrase.'
}

New-Item -ItemType Directory -Force -Path $KeyringDirectory, $SecretDirectory | Out-Null
$gpgHome = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $gpgHome | Out-Null
try {
    Invoke-Gpg @('--quick-generate-key', $signingUid, 'ed25519', 'sign', '3y') '' | Out-Null
    Invoke-Gpg @('--quick-generate-key', $standbyUid, 'ed25519', 'sign', 'never') $standbySecret | Out-Null
    $signing = Get-Fingerprint $signingUid
    $standby = Get-Fingerprint $standbyUid

    foreach ($fingerprint in $signing, $standby) {
        Invoke-Gpg @('--armor', '--output', (Join-Path $KeyringDirectory "$fingerprint.asc"), '--export', $fingerprint) '' | Out-Null
        Copy-Item (Join-Path $gpgHome 'openpgp-revocs.d' "$fingerprint.rev") (Join-Path $SecretDirectory "$fingerprint.rev")
    }
    Invoke-Gpg @('--armor', '--output', (Join-Path $SecretDirectory 'signing.secret.asc'), '--export-secret-keys', $signing) '' | Out-Null
    Invoke-Gpg @('--armor', '--output', (Join-Path $SecretDirectory 'standby.secret.asc'), '--export-secret-keys', $standby) $standbySecret | Out-Null

    Write-Output "signing $signing"
    Write-Output "standby $standby"
}
finally {
    & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
    Remove-Item -Recurse -Force $gpgHome -ErrorAction SilentlyContinue
}
