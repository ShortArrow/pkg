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
