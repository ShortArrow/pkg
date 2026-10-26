#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $workflows = Join-Path $PSScriptRoot '..' '.github' 'workflows'
}

Describe 'workflows' {
    It 'pin every action they use to a commit, with the tag in a comment' {
        $uses = Get-ChildItem $workflows -Filter '*.yml' | Select-String -Pattern '^\s*-?\s*uses:\s*(.+)$' |
            ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
        $uses | Should -Not -BeNullOrEmpty
        $uses | Where-Object { $_ -notmatch '^[\w.-]+/[\w./-]+@[0-9a-f]{40} # v\S+$' } | Should -BeNullOrEmpty
    }
}
