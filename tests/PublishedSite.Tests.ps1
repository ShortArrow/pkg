#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptIndex.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptRelease.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'PublishedSite.psm1') -Force

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $path | Out-Null
        $path
    }

    function New-TestKey([string] $GpgHome, [string] $Uid, [string] $KeyringDirectory) {
        & gpg --homedir $GpgHome --batch --pinentry-mode loopback --passphrase '' --quick-generate-key $Uid ed25519 sign 1d 2>$null
        $lines = & gpg --homedir $GpgHome --batch --with-colons --list-keys "=$Uid"
        $fpr = ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
        if ($KeyringDirectory) {
            & gpg --homedir $GpgHome --batch --yes --armor --output (Join-Path $KeyringDirectory "$fpr.asc") --export $fpr
        }
        $fpr
    }

    function Write-TextFile([string] $Path, [string] $Text) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    <#
    Writes a signed site under <Root>/apt: one keyring package served by the site itself and
    one runex package under pool/, which the site redirects and never holds.
    #>
    function New-TestSite([string] $Root, [string] $GpgHome, [string] $KeyId) {
        $apt = Join-Path $Root 'apt'
        $deb = Join-Path $apt 'keyring' 'shortarrow-archive-keyring_2026.10.21.1_all.deb'
        Write-TextFile $deb 'keyring package'
        $keyringEntry = New-PackageEntry -Path $deb -Filename 'keyring/shortarrow-archive-keyring_2026.10.21.1_all.deb' `
            -Control (ConvertFrom-Deb822 "Package: shortarrow-archive-keyring`nVersion: 2026.10.21.1`nArchitecture: all`n")
        foreach ($arch in 'amd64', 'arm64') {
            $runex = [ordered]@{
                Package = 'runex'; Version = '0.1.21-1'; Architecture = $arch
                Filename = "pool/runex/v0.1.21/runex_0.1.21-1_$arch.deb"; Size = '1'; SHA256 = '0' * 64
            }
            Write-TextFile (Join-Path $apt 'dists' 'stable' 'main' "binary-$arch" 'Packages') (ConvertTo-Deb822 @($runex, $keyringEntry))
        }
        Write-SignedRelease -SuiteDirectory (Join-Path $apt 'dists' 'stable') -GpgHome $GpgHome -KeyId $KeyId `
            -Date ([DateTimeOffset]::new(2026, 10, 21, 0, 0, 0, [TimeSpan]::Zero))
    }

    function New-DirectoryFetch([string] $Root) {
        {
            param([string] $Path)
            $file = Join-Path $Root 'apt' $Path
            if (Test-Path $file) { [System.IO.File]::ReadAllBytes($file) } else { $null }
        }.GetNewClosure()
    }
}

Describe 'Import-PublishedSite' -Tag 'gpg' {
    BeforeAll {
        $gpgHome = New-TempDirectory
        $keyring = New-TempDirectory
        $signing = New-TestKey $gpgHome 'signing' $keyring
        $stranger = New-TestKey $gpgHome 'stranger'
    }

    AfterAll {
        & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
        Remove-Item -Recurse -Force $gpgHome, $keyring -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $site = New-TempDirectory
        $destination = New-TempDirectory
        $fetched = [System.Collections.Generic.List[string]]::new()
        $directoryFetch = New-DirectoryFetch $site
        $fetch = { param([string] $Path) $fetched.Add($Path); & $directoryFetch $Path }.GetNewClosure()
    }

    AfterEach {
        Remove-Item -Recurse -Force $site, $destination -ErrorAction SilentlyContinue
    }

    It 'returns the index of a site signed by a key under keyring/, and saves every file it fetched' {
        New-TestSite $site $gpgHome $signing

        $index = @(Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $destination)

        $index | ForEach-Object { "$($_.Package) $($_.Architecture)" } |
            Should -Be @('runex amd64', 'runex arm64', 'shortarrow-archive-keyring all')
        foreach ($path in 'dists/stable/InRelease', 'dists/stable/main/binary-arm64/Packages', 'keyring/shortarrow-archive-keyring_2026.10.21.1_all.deb') {
            Join-Path $destination 'apt' $path | Should -Exist
        }
    }

    It 'never fetches a package under pool/' {
        New-TestSite $site $gpgHome $signing

        Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $destination | Out-Null

        $fetched | Where-Object { $_ -like 'pool/*' } | Should -BeNullOrEmpty
    }

    It 'refuses an InRelease that no key under keyring/ signed' {
        New-TestSite $site $gpgHome $stranger

        { Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $destination } |
            Should -Throw '*InRelease*'
    }

    It 'refuses a Packages changed after signing' {
        New-TestSite $site $gpgHome $signing
        $packages = Join-Path $site 'apt' 'dists' 'stable' 'main' 'binary-amd64' 'Packages'
        Add-Content -Path $packages -Value 'X-Tampered: yes' -NoNewline

        { Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $destination } |
            Should -Throw '*main/binary-amd64/Packages*'
    }

    It 'refuses a file the site serves that differs from its Packages entry' {
        New-TestSite $site $gpgHome $signing
        Set-Content -Path (Join-Path $site 'apt' 'keyring' 'shortarrow-archive-keyring_2026.10.21.1_all.deb') -Value 'keyring packagE' -NoNewline

        { Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $destination } |
            Should -Throw '*shortarrow-archive-keyring_2026.10.21.1_all.deb*'
    }

    It 'refuses a site with no InRelease, which only a rebuild creates' {
        { Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $destination } |
            Should -Throw '*rebuild*'
    }
}
