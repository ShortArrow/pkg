#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptIndex.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptRelease.psm1') -Force

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $path | Out-Null
        $path
    }

    function New-TestKey([string] $GpgHome, [string] $Uid) {
        & gpg --homedir $GpgHome --batch --pinentry-mode loopback --passphrase '' --quick-generate-key $Uid ed25519 sign 1d 2>$null
        $lines = & gpg --homedir $GpgHome --batch --with-colons --list-keys "=$Uid"
        ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
    }

    function Get-ValidSignature([string] $Keyring, [string] $File) {
        $status = & gpgv --status-fd 1 --keyring $Keyring $File 2>$null
        [pscustomobject]@{
            Fingerprints = @($status | Where-Object { $_ -like '*VALIDSIG*' } | ForEach-Object { $_.Split(' ')[2] })
            Bad          = @($status | Where-Object { $_ -like '*BADSIG*' })
        }
    }
}

Describe 'Write-SignedRelease' -Tag 'gpg' {
    BeforeAll {
        $gpgHome = New-TempDirectory
        $current = New-TestKey $gpgHome 'current'
        $next = New-TestKey $gpgHome 'next'

        $suite = Join-Path (New-TempDirectory) 'stable'
        $binary = Join-Path $suite 'main' 'binary-amd64'
        New-Item -ItemType Directory -Force -Path $binary | Out-Null
        Set-Content -Path (Join-Path $binary 'Packages') -Value "Package: runex`n" -NoNewline
        $date = [DateTimeOffset]::new(2026, 10, 21, 0, 0, 0, [TimeSpan]::Zero)

        Write-SignedRelease -SuiteDirectory $suite -Date $date -GpgHome $gpgHome -KeyId $current, $next
        $inRelease = Join-Path $suite 'InRelease'
    }

    AfterAll {
        & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
        Remove-Item -Recurse -Force $gpgHome, (Split-Path $suite) -ErrorAction SilentlyContinue
    }

    It 'writes Release as New-ReleaseText gives it, with LF line ends and no byte order mark' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $suite 'Release'))
        $expected = [System.Text.Encoding]::UTF8.GetBytes((New-ReleaseText -SuiteDirectory $suite -Date $date))
        $bytes | Should -Be $expected
    }

    It 'clearsigns InRelease with SHA512 over the Release text' {
        $text = Get-Content -Raw $inRelease
        $text | Should -Match '(?m)^Hash: SHA512\r?$'
        $text | Should -Match '(?m)^Valid-Until: Tue, 19 Jan 2027 00:00:00 UTC\r?$'
    }

    It 'carries a valid signature by every given key' {
        $all = Join-Path $gpgHome 'all.gpg'
        & gpg --homedir $gpgHome --batch --yes --output $all --export $current $next
        $result = Get-ValidSignature $all $inRelease
        $result.Fingerprints | Sort-Object | Should -Be (@($current, $next) | Sort-Object)
        $result.Bad | Should -BeNullOrEmpty
    }
}
