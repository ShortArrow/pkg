#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'GitHubRelease.psm1') -Force
}

Describe 'Test-StableRelease' {
    It 'accepts <Tag>' -ForEach @(
        @{ Tag = 'v0.1.21' }
        @{ Tag = 'v0.5.0' }
        @{ Tag = '1.2.3' }
    ) {
        Test-StableRelease -Tag $Tag -Prerelease $false | Should -BeTrue
    }

    It 'refuses <Tag>, which carries a - after its version' -ForEach @(
        @{ Tag = 'v0.5.0-beta.1' }
        @{ Tag = 'v0.3.0-rc.1' }
    ) {
        Test-StableRelease -Tag $Tag -Prerelease $false | Should -BeFalse
    }

    It 'refuses a release GitHub marks as a pre-release, whatever its tag' {
        Test-StableRelease -Tag 'v0.5.0' -Prerelease $true | Should -BeFalse
    }
}

Describe 'ConvertFrom-Sha256Sums' {
    It 'maps each file name to its lower-case hash, in text and binary mode' {
        $a = 'A' * 64
        $b = 'b' * 64
        $sums = ConvertFrom-Sha256Sums "$a  runex_0.1.21-1_amd64.deb`n$b *runex_0.1.21-1_arm64.deb`n"

        $sums['runex_0.1.21-1_amd64.deb'] | Should -Be ('a' * 64)
        $sums['runex_0.1.21-1_arm64.deb'] | Should -Be $b
    }

    It 'refuses a line that is not a hash and a file name' {
        { ConvertFrom-Sha256Sums "deadbeef  file.deb`n" } | Should -Throw '*deadbeef*'
    }
}

Describe 'Assert-Sha256Sum' {
    BeforeAll {
        $file = Join-Path $TestDrive 'runex_0.1.21-1_amd64.deb'
        Set-Content -Path $file -Value 'package' -NoNewline
        $hash = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLowerInvariant()
    }

    It 'passes a file whose hash matches its line' {
        { Assert-Sha256Sum -Path $file -Sums @{ 'runex_0.1.21-1_amd64.deb' = $hash } } | Should -Not -Throw
    }

    It 'refuses a file whose hash differs' {
        { Assert-Sha256Sum -Path $file -Sums @{ 'runex_0.1.21-1_amd64.deb' = '0' * 64 } } | Should -Throw '*does not match*'
    }

    It 'refuses a file SHA256SUMS does not list' {
        { Assert-Sha256Sum -Path $file -Sums @{} } | Should -Throw '*does not list*'
    }
}

Describe 'Get-ReleasePackageEntry' -Tag 'dpkg' {
    BeforeAll {
        $assets = Join-Path $TestDrive 'assets'
        foreach ($arch in 'amd64', 'arm64') {
            $root = Join-Path $TestDrive "root-$arch"
            New-Item -ItemType Directory -Force -Path (Join-Path $root 'DEBIAN'), (Join-Path $root 'usr' 'bin') | Out-Null
            Set-Content -Path (Join-Path $root 'usr' 'bin' 'runex') -Value $arch -NoNewline
            Set-Content -Path (Join-Path $root 'DEBIAN' 'control') -Value "Package: runex`nVersion: 0.1.21-1`nArchitecture: $arch`nMaintainer: Test <test@example.invalid>`nDescription: test package`n multi-line`n" -NoNewline
            & chmod -R u=rwX,go=rX $root
            New-Item -ItemType Directory -Force -Path $assets | Out-Null
            & dpkg-deb --root-owner-group --build $root (Join-Path $assets "runex_0.1.21-1_$arch.deb") | Out-Null
        }
        $sums = (Get-ChildItem $assets -Filter '*.deb' | ForEach-Object {
                "$((Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant())  $($_.Name)"
            }) -join "`n"
        Set-Content -Path (Join-Path $assets 'SHA256SUMS') -Value "$sums`n" -NoNewline
        Set-Content -Path (Join-Path $assets 'runex-x86_64-linux.tar.gz') -Value 'archive' -NoNewline

        function Get-Asset([string[]] $Name) {
            $Name | ForEach-Object { [pscustomobject]@{ name = $_; url = (Join-Path $assets $_) } }
        }
    }

    BeforeEach {
        $work = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $work | Out-Null
        $downloaded = [System.Collections.Generic.List[string]]::new()
        $download = { param([string] $Url, [string] $Path) $downloaded.Add((Split-Path -Leaf $Url)); Copy-Item $Url $Path }.GetNewClosure()
    }

    It 'returns one entry per package, read from the package and placed under pool/ by repository and tag' {
        $entries = @(Get-ReleasePackageEntry -Repository 'runex' -Tag 'v0.1.21' -WorkDirectory $work -Download $download `
                -Assets (Get-Asset 'runex_0.1.21-1_amd64.deb', 'runex_0.1.21-1_arm64.deb', 'SHA256SUMS', 'runex-x86_64-linux.tar.gz'))

        $entries | ForEach-Object { "$($_.Package) $($_.Version) $($_.Architecture) $($_.Filename)" } | Should -Be @(
            'runex 0.1.21-1 amd64 pool/runex/v0.1.21/runex_0.1.21-1_amd64.deb'
            'runex 0.1.21-1 arm64 pool/runex/v0.1.21/runex_0.1.21-1_arm64.deb'
        )
        $amd64 = Join-Path $assets 'runex_0.1.21-1_amd64.deb'
        $entries[0].SHA256 | Should -Be (Get-FileHash -Algorithm SHA256 $amd64).Hash.ToLowerInvariant()
        $entries[0].Size | Should -Be ([string] (Get-Item $amd64).Length)
        $entries[0].Description | Should -Be "test package`n multi-line"
        $downloaded | Should -Not -Contain 'runex-x86_64-linux.tar.gz'
    }

    It 'returns nothing and downloads nothing for a release without packages' {
        $entries = @(Get-ReleasePackageEntry -Repository 'runex' -Tag 'v0.1.20' -WorkDirectory $work -Download $download `
                -Assets (Get-Asset 'runex-x86_64-linux.tar.gz'))

        $entries.Count | Should -Be 0
        $downloaded.Count | Should -Be 0
    }

    It 'refuses a release with packages but no SHA256SUMS' {
        { Get-ReleasePackageEntry -Repository 'runex' -Tag 'v0.1.21' -WorkDirectory $work -Download $download `
                -Assets (Get-Asset 'runex_0.1.21-1_amd64.deb') } | Should -Throw '*SHA256SUMS*'
    }

    It 'refuses a package that does not match SHA256SUMS' {
        $other = Join-Path $TestDrive 'other'
        New-Item -ItemType Directory -Force -Path $other | Out-Null
        Copy-Item (Join-Path $assets 'runex_0.1.21-1_arm64.deb') (Join-Path $other 'runex_0.1.21-1_amd64.deb')
        Copy-Item (Join-Path $assets 'SHA256SUMS') $other
        $swapped = @('runex_0.1.21-1_amd64.deb', 'SHA256SUMS') | ForEach-Object { [pscustomobject]@{ name = $_; url = (Join-Path $other $_) } }

        { Get-ReleasePackageEntry -Repository 'runex' -Tag 'v0.1.21' -WorkDirectory $work -Download $download -Assets $swapped } |
            Should -Throw '*does not match*'
    }
}

Describe 'Find-UnpublishedRelease' {
    BeforeAll {
        function New-Release([string] $Tag, [bool] $Prerelease = $false, [string[]] $Asset = @('runex_1_amd64.deb', 'SHA256SUMS')) {
            [pscustomobject]@{ tag_name = $Tag; prerelease = $Prerelease; assets = @($Asset | ForEach-Object { [pscustomobject]@{ name = $_ } }) }
        }
        $index = @([ordered]@{ Package = 'runex'; Version = '0.1.21-1'; Architecture = 'amd64'; Filename = 'pool/runex/v0.1.21/runex_0.1.21-1_amd64.deb' })
    }

    It 'returns the stable releases with packages that the index does not hold and no run was started for' {
        $releases = @(
            New-Release 'v0.1.23'
            New-Release 'v0.1.22'
            New-Release 'v0.1.21'
            New-Release 'v0.2.0-rc.1' $true
            New-Release 'v0.1.20' -Asset @('runex.tar.gz')
        )

        Find-UnpublishedRelease -Repository 'runex' -Releases $releases -Index $index -StartedRuns @('publish runex v0.1.23') |
            Should -Be @('v0.1.22')
    }

    It 'returns nothing when every release is published' {
        Find-UnpublishedRelease -Repository 'runex' -Releases @(New-Release 'v0.1.21') -Index $index -StartedRuns @() |
            Should -BeNullOrEmpty
    }
}
