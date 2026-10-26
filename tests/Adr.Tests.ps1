#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $root = Join-Path $PSScriptRoot '..'
}

Describe 'decision records' {
    It 'carry no date, which git history already holds' {
        Get-ChildItem (Join-Path $root 'docs' 'adr') -Filter '*.md' |
            Select-String -Pattern '\b\d{4}-\d{2}-\d{2}\b' |
            ForEach-Object { "$($_.Filename):$($_.LineNumber)" } | Should -BeNullOrEmpty
    }

    It 'are named in the documents only through links that resolve' {
        $documents = @(Get-Item (Join-Path $root 'README.md')) + @(Get-ChildItem (Join-Path $root 'docs') -Filter '*.md' -Recurse)
        $broken = foreach ($document in $documents) {
            foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($document.FullName), '\]\(([^)#]*\.md)(#[^)]*)?\)')) {
                $target = $match.Groups[1].Value
                if ($target -notmatch '^https?:' -and -not (Test-Path (Join-Path $document.DirectoryName $target))) {
                    "$($document.Name) -> $target"
                }
            }
        }
        $broken | Should -BeNullOrEmpty
    }

    It 'are not named by a section of another record' {
        $documents = @(Get-Item (Join-Path $root 'README.md')) + @(Get-ChildItem (Join-Path $root 'docs') -Filter '*.md' -Recurse)
        $documents | Select-String -Pattern '§\d' | ForEach-Object { "$($_.Filename):$($_.LineNumber)" } | Should -BeNullOrEmpty
    }
}
