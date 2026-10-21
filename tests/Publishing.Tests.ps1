#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptIndex.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'Publishing.psm1') -Force

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $path | Out-Null
        $path
    }

    function New-TestKey([string] $GpgHome, [string] $Uid, [string] $KeyringDirectory) {
        & gpg --homedir $GpgHome --batch --pinentry-mode loopback --passphrase '' --quick-generate-key $Uid ed25519 sign 1d 2>$null
        $lines = & gpg --homedir $GpgHome --batch --with-colons --list-keys "=$Uid"
        $fpr = ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
        & gpg --homedir $GpgHome --batch --yes --armor --output (Join-Path $KeyringDirectory "$fpr.asc") --export $fpr
        $fpr
    }

    <# Builds a release of runex with the given assets: 'deb' adds both architectures and SHA256SUMS. #>
    function New-TestRelease([string] $AssetDirectory, [string] $Tag, [bool] $Prerelease, [switch] $Packages) {
        $dir = Join-Path $AssetDirectory $Tag
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir 'runex-x86_64-linux.tar.gz') -Value 'archive' -NoNewline
        if ($Packages) {
            $version = ($Tag -replace '^v') -replace '-', '~'
            foreach ($arch in 'amd64', 'arm64') {
                $root = Join-Path $dir "root-$arch"
                New-Item -ItemType Directory -Force -Path (Join-Path $root 'DEBIAN') | Out-Null
                Set-Content -Path (Join-Path $root 'DEBIAN' 'control') -NoNewline `
                    -Value "Package: runex`nVersion: $version-1`nArchitecture: $arch`nMaintainer: Test <test@example.invalid>`nDescription: test`n"
                & chmod -R u=rwX,go=rX $root
                & dpkg-deb --root-owner-group --build $root (Join-Path $dir "runex_$version-1_$arch.deb") | Out-Null
                Remove-Item -Recurse -Force $root
            }
            $sums = Get-ChildItem $dir -Filter '*.deb' | ForEach-Object {
                "$((Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant())  $($_.Name)"
            }
            Set-Content -Path (Join-Path $dir 'SHA256SUMS') -Value (($sums -join "`n") + "`n") -NoNewline
        }
        [pscustomobject]@{
            tag_name   = $Tag
            prerelease = $Prerelease
            assets     = @(Get-ChildItem $dir -File | ForEach-Object { [pscustomobject]@{ name = $_.Name; url = $_.FullName } })
        }
    }

    function Get-Summary($Index) {
        @($Index | ForEach-Object { "$($_.Package) $($_.Version) $($_.Architecture)" })
    }
}

Describe 'Invoke-RegistryUpdate' -Tag 'gpg', 'dpkg' {
    BeforeAll {
        $gpgHome = New-TempDirectory
        $keyring = New-TempDirectory
        $signing = New-TestKey $gpgHome 'signing' $keyring
        $redirects = Join-Path $keyring '..' "$(Split-Path -Leaf $keyring).redirects"
        Set-Content -Path $redirects -Value '/apt/pool/:repo/:tag/:file https://example.invalid/:repo/:tag/:file 302' -NoNewline

        $assetDirectory = New-TempDirectory
        $releases = @{
            'v0.1.20'     = New-TestRelease $assetDirectory 'v0.1.20' $false
            'v0.1.21'     = New-TestRelease $assetDirectory 'v0.1.21' $false -Packages
            'v0.2.0-rc.1' = New-TestRelease $assetDirectory 'v0.2.0-rc.1' $true -Packages
            'v0.1.22'     = New-TestRelease $assetDirectory 'v0.1.22' $false -Packages
        }
        $listed = @($releases['v0.1.20'], $releases['v0.1.21'], $releases['v0.2.0-rc.1'])

        $script:live = $null
        $common = @{
            FetchSite        = { param([string] $Path) $file = Join-Path $script:live 'apt' $Path; if (Test-Path $file) { [System.IO.File]::ReadAllBytes($file) } }
            GetRelease       = { param([string] $Repository, [string] $Tag) $releases[$Tag] }.GetNewClosure()
            GetReleases      = { param([string] $Repository) $listed }.GetNewClosure()
            Download         = { param([string] $Url, [string] $Path) Copy-Item $Url $Path }
            KeyringDirectory = $keyring
            Redirects        = $redirects
            GpgHome          = $gpgHome
            KeyId            = @($signing)
            Date             = [DateTimeOffset]::new(2026, 10, 21, 0, 0, 0, [TimeSpan]::Zero)
        }

        function Invoke-Update([hashtable] $Arguments) {
            $destination = Join-Path (New-TempDirectory) 'public'
            $result = Invoke-RegistryUpdate @common @Arguments -Destination $destination -WorkDirectory (New-TempDirectory)
            if (Test-Path $destination) { $script:live = $destination }
            $result
        }
    }

    AfterAll {
        & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
        Remove-Item -Recurse -Force $gpgHome, $keyring, $assetDirectory, $redirects -ErrorAction SilentlyContinue
    }

    It 'rebuilds from every stable release with packages, adding a keyring package built from keyring/' {
        $result = Invoke-Update @{ Operation = 'Rebuild'; Repositories = @('runex') }

        Get-Summary $result.Index | Should -Be @(
            'runex 0.1.21-1 amd64'
            'runex 0.1.21-1 arm64'
            'shortarrow-archive-keyring 2026.10.21.1 all'
        )
        Join-Path $script:live 'apt' 'keyring' 'shortarrow-archive-keyring_2026.10.21.1_all.deb' | Should -Exist
    }

    It 'publishes a new release on top of the live site, keeping what it holds' {
        $result = Invoke-Update @{ Operation = 'Publish'; Repository = 'runex'; Tag = 'v0.1.22' }

        Get-Summary $result.Index | Should -Be @(
            'runex 0.1.21-1 amd64'
            'runex 0.1.21-1 arm64'
            'runex 0.1.22-1 amd64'
            'runex 0.1.22-1 arm64'
            'shortarrow-archive-keyring 2026.10.21.1 all'
        )
        $result.Index | Where-Object Version -EQ '0.1.22-1' | Select-Object -First 1 |
            ForEach-Object { $_.Filename } | Should -Be 'pool/runex/v0.1.22/runex_0.1.22-1_amd64.deb'
    }

    It 'refuses to publish a pre-release' {
        { Invoke-Update @{ Operation = 'Publish'; Repository = 'runex'; Tag = 'v0.2.0-rc.1' } } | Should -Throw '*not a stable release*'
    }

    It 'skips a release without packages, writing no site' {
        $before = $script:live
        $result = Invoke-Update @{ Operation = 'Publish'; Repository = 'runex'; Tag = 'v0.1.20' }

        $result.Skipped | Should -BeTrue
        $script:live | Should -Be $before
    }

    It 'withdraws one package version' {
        $result = Invoke-Update @{ Operation = 'Withdraw'; Package = 'runex'; Version = '0.1.21-1' }

        Get-Summary $result.Index | Should -Be @(
            'runex 0.1.22-1 amd64'
            'runex 0.1.22-1 arm64'
            'shortarrow-archive-keyring 2026.10.21.1 all'
        )
    }

    It 're-signs, adding a keyring package when keyring/ gained a key and keeping the earlier one' {
        New-TestKey $gpgHome 'next' $keyring | Out-Null

        $result = Invoke-Update @{ Operation = 'Resign' }

        Get-Summary $result.Index | Should -Be @(
            'runex 0.1.22-1 amd64'
            'runex 0.1.22-1 arm64'
            'shortarrow-archive-keyring 2026.10.21.1 all'
            'shortarrow-archive-keyring 2026.10.21.2 all'
        )
    }

    It 're-signs without a new keyring package when keyring/ is unchanged' {
        $result = Invoke-Update @{ Operation = 'Resign' }

        @($result.Index | Where-Object Package -EQ 'shortarrow-archive-keyring').Count | Should -Be 2
    }
}
