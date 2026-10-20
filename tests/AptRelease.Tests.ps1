#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptIndex.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptRelease.psm1') -Force
}

Describe 'New-ReleaseText' {
    BeforeAll {
        $dists = Join-Path $TestDrive 'dists' 'stable'
        foreach ($arch in 'amd64', 'arm64') {
            $dir = Join-Path $dists 'main' "binary-$arch"
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'Packages') -Value "Package: $arch`n" -NoNewline
            Set-Content -Path (Join-Path $dir 'Packages.gz') -Value "gz $arch" -NoNewline
        }
        $date = [DateTimeOffset]::new(2026, 10, 21, 3, 4, 5, [TimeSpan]::Zero)

        $text = New-ReleaseText -SuiteDirectory $dists -Date $date
        $release = @(ConvertFrom-Deb822 $text)[0]
    }

    It 'describes the stable suite of the repository' {
        $release.Suite | Should -Be 'stable'
        $release.Codename | Should -Be 'stable'
        $release.Components | Should -Be 'main'
        $release.Architectures | Should -Be 'amd64 arm64'
    }

    It 'dates the signing and makes it valid for 90 days, in RFC 2822 form in UTC' {
        $release.Date | Should -Be 'Wed, 21 Oct 2026 03:04:05 UTC'
        $release.'Valid-Until' | Should -Be 'Tue, 19 Jan 2027 03:04:05 UTC'
    }

    It 'lists the SHA-256 and size of every index file, relative to the suite' {
        $lines = @($release.SHA256 -split "`n" | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        $lines.Count | Should -Be 4
        $packages = Join-Path $dists 'main' 'binary-arm64' 'Packages'
        $hash = (Get-FileHash -Algorithm SHA256 $packages).Hash.ToLowerInvariant()
        $size = (Get-Item $packages).Length
        $lines | Should -Contain "$hash $size main/binary-arm64/Packages"
    }

    It 'writes no Release or InRelease file of its own' {
        Join-Path $dists 'Release' | Should -Not -Exist
    }
}
