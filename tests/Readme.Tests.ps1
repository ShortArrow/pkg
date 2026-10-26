#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'Keyring.psm1') -Force
    $root = Join-Path $PSScriptRoot '..'
}

Describe 'keyring/fingerprints' -Tag 'gpg' {
    It 'lists the fingerprint of exactly the keys under keyring/, one per line' {
        $listed = [System.IO.File]::ReadAllLines((Join-Path $root 'keyring' 'fingerprints')) | Sort-Object
        $keys = (Get-KeyringKey -KeyringDirectory (Join-Path $root 'keyring')).Fingerprint | Sort-Object
        $listed | Should -Be $keys
    }
}

Describe 'docs/installing.md' {
    It 'adds the same source line as the README, and links to it' {
        $readme = [System.IO.File]::ReadAllText((Join-Path $root 'README.md'))
        $guide = [System.IO.File]::ReadAllText((Join-Path $root 'docs' 'installing.md'))
        $line = [regex]::Match($readme, 'deb \[signed-by=[^\]]+\] \S+ stable main').Value
        $line | Should -Not -BeNullOrEmpty
        $guide | Should -Match ([regex]::Escape($line))
        $readme | Should -Match ([regex]::Escape('(docs/installing.md)'))
    }
}

Describe 'README' {
    It 'checks the keyring against keyring/fingerprints, off the host that serves the keyring' {
        [System.IO.File]::ReadAllText((Join-Path $root 'README.md')) |
            Should -Match ([regex]::Escape('https://raw.githubusercontent.com/ShortArrow/pkg/main/keyring/fingerprints'))
    }
}
