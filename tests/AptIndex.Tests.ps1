#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'AptIndex.psm1') -Force

    function New-Entry([string] $Package, [string] $Version, [string] $Architecture) {
        [ordered]@{
            Package      = $Package
            Version      = $Version
            Architecture = $Architecture
            Filename     = "pool/$Package/v$Version/${Package}_${Version}_$Architecture.deb"
        }
    }

    function Get-Key($Entries) {
        @($Entries | ForEach-Object { "$($_.Package) $($_.Version) $($_.Architecture)" })
    }
}

Describe 'ConvertFrom-Deb822' {
    It 'reads each stanza as an ordered set of fields, keeping continuation lines' {
        $text = "Package: runex`nVersion: 0.1.21-1`nDescription: one`n two`n .`n three`n`nPackage: ivicli`nVersion: 0.5.0-1`n"

        $entries = @(ConvertFrom-Deb822 $text)

        $entries.Count | Should -Be 2
        @($entries[0].Keys) | Should -Be @('Package', 'Version', 'Description')
        $entries[0].Description | Should -Be "one`n two`n .`n three"
        $entries[1].Package | Should -Be 'ivicli'
    }

    It 'reads an empty text as no stanzas' {
        @(ConvertFrom-Deb822 '').Count | Should -Be 0
    }

    It 'ignores carriage returns and extra blank lines between stanzas' {
        $entries = @(ConvertFrom-Deb822 "`r`n`r`nPackage: a`r`n`r`n`r`nPackage: b`r`n")

        $entries.Package | Should -Be @('a', 'b')
    }

    It 'refuses a line that is neither a field nor a continuation' {
        { ConvertFrom-Deb822 "Package: a`nnot a field`n" } | Should -Throw '*not a field*'
    }
}

Describe 'ConvertTo-Deb822' {
    It 'writes stanzas separated by one blank line, ending with a newline' {
        $text = "Package: runex`nVersion: 0.1.21-1`nDescription: one`n two`n`nPackage: ivicli`nVersion: 0.5.0-1`n"

        ConvertTo-Deb822 (ConvertFrom-Deb822 $text) | Should -BeExactly $text
    }

    It 'writes no stanzas as an empty text' {
        ConvertTo-Deb822 @() | Should -BeExactly ''
    }
}

Describe 'Set-PackageVersion' {
    It 'replaces every architecture of the same package and version, and keeps the rest' {
        $index = @(
            New-Entry 'runex' '0.1.21-1' 'amd64'
            New-Entry 'runex' '0.1.21-1' 'arm64'
            New-Entry 'runex' '0.1.20-1' 'amd64'
            New-Entry 'ivicli' '0.5.0-1' 'amd64'
        )
        $rebuilt = New-Entry 'runex' '0.1.21-1' 'amd64'
        $rebuilt.SHA256 = 'new'

        $result = @(Set-PackageVersion -Index $index -Entries @($rebuilt))

        Get-Key $result | Should -Be @('ivicli 0.5.0-1 amd64', 'runex 0.1.20-1 amd64', 'runex 0.1.21-1 amd64')
        ($result | Where-Object Version -EQ '0.1.21-1').SHA256 | Should -Be 'new'
    }

    It 'adds a version the index does not hold, in package, version and architecture order' {
        $index = @(New-Entry 'runex' '0.1.20-1' 'amd64')
        $new = @((New-Entry 'runex' '0.1.21-1' 'arm64'), (New-Entry 'runex' '0.1.21-1' 'amd64'))

        Get-Key (Set-PackageVersion -Index $index -Entries $new) |
            Should -Be @('runex 0.1.20-1 amd64', 'runex 0.1.21-1 amd64', 'runex 0.1.21-1 arm64')
    }

    It 'leaves the given index unchanged' {
        $index = @(New-Entry 'runex' '0.1.21-1' 'amd64')

        Set-PackageVersion -Index $index -Entries @(New-Entry 'runex' '0.1.21-1' 'arm64') | Out-Null

        Get-Key $index | Should -Be @('runex 0.1.21-1 amd64')
    }
}

Describe 'Remove-PackageVersion' {
    It 'removes every architecture of one package version' {
        $index = @(
            New-Entry 'runex' '0.1.21-1' 'amd64'
            New-Entry 'runex' '0.1.21-1' 'arm64'
            New-Entry 'runex' '0.1.20-1' 'amd64'
        )

        Get-Key (Remove-PackageVersion -Index $index -Package 'runex' -Version '0.1.21-1') |
            Should -Be @('runex 0.1.20-1 amd64')
    }

    It 'refuses a version the index does not hold' {
        $index = @(New-Entry 'runex' '0.1.21-1' 'amd64')

        { Remove-PackageVersion -Index $index -Package 'runex' -Version '0.1.2-1' } | Should -Throw '*runex 0.1.2-1*'
    }
}

Describe 'Join-PackageIndex' {
    It 'merges per-architecture indexes, holding an architecture-independent entry once' {
        $keyring = New-Entry 'shortarrow-archive-keyring' '2026.10.21.1' 'all'
        $amd64 = @((New-Entry 'runex' '0.1.21-1' 'amd64'), $keyring)
        $arm64 = @((New-Entry 'runex' '0.1.21-1' 'arm64'), $keyring)

        Get-Key (Join-PackageIndex $amd64, $arm64) |
            Should -Be @('runex 0.1.21-1 amd64', 'runex 0.1.21-1 arm64', 'shortarrow-archive-keyring 2026.10.21.1 all')
    }

    It 'refuses two different entries for the same package, version and architecture' {
        $one = New-Entry 'shortarrow-archive-keyring' '2026.10.21.1' 'all'
        $other = New-Entry 'shortarrow-archive-keyring' '2026.10.21.1' 'all'
        $other.SHA256 = 'different'

        { Join-PackageIndex @($one), @($other) } | Should -Throw '*shortarrow-archive-keyring 2026.10.21.1 all*'
    }
}

Describe 'Select-ArchitectureIndex' {
    It 'keeps the entries of one architecture and the architecture-independent ones' {
        $index = @(
            New-Entry 'runex' '0.1.21-1' 'amd64'
            New-Entry 'runex' '0.1.21-1' 'arm64'
            New-Entry 'shortarrow-archive-keyring' '2026.10.21.1' 'all'
        )

        Get-Key (Select-ArchitectureIndex -Index $index -Architecture 'arm64') |
            Should -Be @('runex 0.1.21-1 arm64', 'shortarrow-archive-keyring 2026.10.21.1 all')
    }
}

Describe 'New-PackageEntry' {
    It 'adds the file name, size and SHA-256 of the package before its description' {
        $deb = Join-Path $TestDrive 'runex_0.1.21-1_amd64.deb'
        Set-Content -Path $deb -Value 'package' -NoNewline
        $control = ConvertFrom-Deb822 "Package: runex`nVersion: 0.1.21-1`nArchitecture: amd64`nDescription: one`n two`n"

        $entry = New-PackageEntry -Control $control -Path $deb -Filename 'pool/runex/v0.1.21/runex_0.1.21-1_amd64.deb'

        @($entry.Keys) | Should -Be @('Package', 'Version', 'Architecture', 'Filename', 'Size', 'SHA256', 'Description')
        $entry.Filename | Should -Be 'pool/runex/v0.1.21/runex_0.1.21-1_amd64.deb'
        $entry.Size | Should -Be '7'
        $entry.SHA256 | Should -Be (Get-FileHash -Algorithm SHA256 $deb).Hash.ToLowerInvariant()
        @($control.Keys) | Should -Not -Contain 'Filename'
    }
}
