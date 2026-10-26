#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

Describe 'decision records' {
    It 'carry no date, which git history already holds' {
        Get-ChildItem (Join-Path $PSScriptRoot '..' 'docs' 'adr') -Filter '*.md' |
            Select-String -Pattern '\b\d{4}-\d{2}-\d{2}\b' |
            ForEach-Object { "$($_.Filename):$($_.LineNumber)" } | Should -BeNullOrEmpty
    }
}
