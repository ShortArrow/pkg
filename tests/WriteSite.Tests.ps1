#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptIndex.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'PublishedSite.psm1') -Force

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $path | Out-Null
        $path
    }

    function Get-RelativeFile([string] $Root) {
        Get-ChildItem $Root -Recurse -File | ForEach-Object {
            [System.IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/'
        } | Sort-Object
    }

    function Read-Gzip([string] $Path) {
        $stream = [System.IO.Compression.GZipStream]::new([System.IO.File]::OpenRead($Path), [System.IO.Compression.CompressionMode]::Decompress)
        try { [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
    }
}

Describe 'Write-Site' -Tag 'gpg' {
    BeforeAll {
        $gpgHome = New-TempDirectory
        $keyring = New-TempDirectory
        & gpg --homedir $gpgHome --batch --pinentry-mode loopback --passphrase '' --quick-generate-key 'signing' ed25519 sign 1d 2>$null
        $lines = & gpg --homedir $gpgHome --batch --with-colons --list-keys '=signing'
        $signing = ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
        & gpg --homedir $gpgHome --batch --yes --armor --output (Join-Path $keyring "$signing.asc") --export $signing
        & gpg --homedir $gpgHome --batch --pinentry-mode loopback --passphrase '' --quick-generate-key 'standby <b>' ed25519 sign never 2>$null
        $lines = & gpg --homedir $gpgHome --batch --with-colons --list-keys '=standby <b>'
        $standby = ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
        & gpg --homedir $gpgHome --batch --yes --armor --output (Join-Path $keyring "$standby.asc") --export $standby

        $source = New-TempDirectory
        $kept = Join-Path $source 'apt' 'keyring' 'shortarrow-archive-keyring_2026.10.21.1_all.deb'
        New-Item -ItemType Directory -Force -Path (Split-Path $kept) | Out-Null
        Set-Content -Path $kept -Value 'keyring package' -NoNewline
        $dropped = Join-Path $source 'apt' 'keyring' 'shortarrow-archive-keyring_2026.10.20.1_all.deb'
        Set-Content -Path $dropped -Value 'withdrawn keyring package' -NoNewline
        $redirects = Join-Path $source '_redirects'
        Set-Content -Path $redirects -Value '/apt/pool/:repo/:tag/:file https://example.invalid/:repo/:tag/:file 302' -NoNewline

        $keyringEntry = New-PackageEntry -Path $kept -Filename 'keyring/shortarrow-archive-keyring_2026.10.21.1_all.deb' `
            -Control (ConvertFrom-Deb822 "Package: shortarrow-archive-keyring`nVersion: 2026.10.21.1`nArchitecture: all`n")
        $index = @(
            [ordered]@{ Package = 'runex'; Version = '0.1.21-1'; Architecture = 'amd64'; Filename = 'pool/runex/v0.1.21/runex_0.1.21-1_amd64.deb'; Size = '1'; SHA256 = '0' * 64 }
            [ordered]@{ Package = 'runex'; Version = '0.1.21-1'; Architecture = 'arm64'; Filename = 'pool/runex/v0.1.21/runex_0.1.21-1_arm64.deb'; Size = '1'; SHA256 = '1' * 64 }
            $keyringEntry
        )
        $date = [DateTimeOffset]::new(2026, 10, 21, 0, 0, 0, [TimeSpan]::Zero)

        $site = Join-Path (New-TempDirectory) 'public'
        Write-Site -Destination $site -SourceDirectory $source -Redirects $redirects -Index $index `
            -KeyringDirectory $keyring -Date $date -GpgHome $gpgHome -KeyId $signing
    }

    AfterAll {
        & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
        Remove-Item -Recurse -Force $gpgHome, $keyring, $source, (Split-Path $site) -ErrorAction SilentlyContinue
    }

    It 'writes the redirects, the front page, the keyring, the files the index names off pool/, and the signed index, and nothing else' {
        Get-RelativeFile $site | Should -Be @(
            '_redirects'
            'apt/dists/stable/InRelease'
            'apt/dists/stable/main/binary-amd64/Packages'
            'apt/dists/stable/main/binary-amd64/Packages.gz'
            'apt/dists/stable/main/binary-arm64/Packages'
            'apt/dists/stable/main/binary-arm64/Packages.gz'
            'apt/dists/stable/Release'
            'apt/keyring/shortarrow-archive-keyring_2026.10.21.1_all.deb'
            'apt/shortarrow-archive-keyring.gpg'
            'index.html'
        )
    }

    It 'names on the front page every key under keyring/, with its fingerprint and its user ID escaped' {
        $page = [System.IO.File]::ReadAllText((Join-Path $site 'index.html'))
        $page | Should -Match ([regex]::Escape(($signing -replace '(.{4})(?!$)', '$1 ')))
        $page | Should -Match ([regex]::Escape(($standby -replace '(.{4})(?!$)', '$1 ')))
        $page | Should -Match 'standby &lt;b&gt;'
        $page | Should -Not -Match 'standby <b>'
        $page | Should -Match 'href="/apt/shortarrow-archive-keyring.gpg"'
    }

    It 'puts each architecture''s own entries and the architecture-independent ones in its Packages, and the same text in Packages.gz' {
        $binary = Join-Path $site 'apt' 'dists' 'stable' 'main' 'binary-arm64'
        $text = [System.IO.File]::ReadAllText((Join-Path $binary 'Packages'))
        @(ConvertFrom-Deb822 $text) | ForEach-Object { "$($_.Package) $($_.Architecture)" } |
            Should -Be @('runex arm64', 'shortarrow-archive-keyring all')
        Read-Gzip (Join-Path $binary 'Packages.gz') | Should -BeExactly $text
    }

    It 'reads back through Import-PublishedSite as the same index' {
        $root = $site
        $fetch = {
            param([string] $Path)
            $file = Join-Path $root 'apt' $Path
            if (Test-Path $file) { [System.IO.File]::ReadAllBytes($file) } else { $null }
        }.GetNewClosure()
        $imported = New-TempDirectory
        try {
            $read = @(Import-PublishedSite -Fetch $fetch -KeyringDirectory $keyring -Destination $imported)
            ConvertTo-Deb822 $read | Should -BeExactly (ConvertTo-Deb822 (Join-PackageIndex @(, $index)))
        }
        finally {
            Remove-Item -Recurse -Force $imported -ErrorAction SilentlyContinue
        }
    }

    It 'refuses an index naming a file off pool/ that the source does not hold' {
        $missing = [ordered]@{ Package = 'shortarrow-archive-keyring'; Version = '2026.10.22.1'; Architecture = 'all'; Filename = 'keyring/missing.deb'; Size = '1'; SHA256 = '0' * 64 }
        $other = Join-Path (New-TempDirectory) 'public'
        { Write-Site -Destination $other -SourceDirectory $source -Redirects $redirects -Index @($missing) `
                -KeyringDirectory $keyring -Date $date -GpgHome $gpgHome -KeyId $signing } | Should -Throw '*keyring/missing.deb*'
    }

    It 'refuses a destination that already holds files' {
        { Write-Site -Destination $site -SourceDirectory $source -Redirects $redirects -Index $index `
                -KeyringDirectory $keyring -Date $date -GpgHome $gpgHome -KeyId $signing } | Should -Throw '*not empty*'
    }
}
