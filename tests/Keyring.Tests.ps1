#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'scripts' 'Keyring.psm1') -Force

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $path | Out-Null
        $path
    }
}

Describe 'Get-NextKeyringVersion' {
    It 'starts a new day at counter 1' {
        Get-NextKeyringVersion -Published @('2026.10.20.1', '2026.10.20.2') -Date ([DateTime]'2026-10-21') |
            Should -Be '2026.10.21.1'
    }

    It 'counts on from the highest counter published the same day' {
        Get-NextKeyringVersion -Published @('2026.10.21.9', '2026.10.21.10', '2026.10.20.11') -Date ([DateTime]'2026-10-21') |
            Should -Be '2026.10.21.11'
    }

    It 'starts at counter 1 when nothing is published' {
        Get-NextKeyringVersion -Published @() -Date ([DateTime]'2026-10-21') | Should -Be '2026.10.21.1'
    }
}

Describe 'New-KeyringPackage' -Tag 'gpg', 'dpkg' {
    BeforeAll {
        $gpgHome = New-TempDirectory
        $keyring = New-TempDirectory
        $output = New-TempDirectory
        $inspect = New-TempDirectory
        $fingerprints = foreach ($uid in 'signing', 'standby') {
            & gpg --homedir $gpgHome --batch --pinentry-mode loopback --passphrase '' --quick-generate-key $uid ed25519 sign 1d 2>$null
            $lines = & gpg --homedir $gpgHome --batch --with-colons --list-keys "=$uid"
            $fpr = ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
            & gpg --homedir $gpgHome --batch --yes --armor --output (Join-Path $keyring "$fpr.asc") --export $fpr
            $fpr
        }

        $result = New-KeyringPackage -KeyringDirectory $keyring -Version '2026.10.21.1' -OutputDirectory $output
    }

    AfterAll {
        & gpgconf --homedir $gpgHome --kill gpg-agent 2>$null
        Remove-Item -Recurse -Force $gpgHome, $keyring, $output, $inspect -ErrorAction SilentlyContinue
    }

    It 'writes a binary keyring holding every key under the keyring directory' {
        $lines = & gpg --homedir $inspect --batch --with-colons --show-keys $result.Keyring
        @($lines | Where-Object { $_ -like 'fpr:*' } | ForEach-Object { $_.Split(':')[9] }) | Sort-Object |
            Should -Be (@($fingerprints) | Sort-Object)
        [System.IO.File]::ReadAllText($result.Keyring) | Should -Not -Match 'BEGIN PGP'
    }

    It 'names the package file by its name, version and architecture' {
        Split-Path -Leaf $result.Package | Should -Be 'shortarrow-archive-keyring_2026.10.21.1_all.deb'
    }

    It 'gives the package its name, version and architecture' {
        & dpkg-deb -f $result.Package Package Version Architecture |
            Should -Be @('Package: shortarrow-archive-keyring', 'Version: 2026.10.21.1', 'Architecture: all')
    }

    It 'installs the keyring at the path the source line names, owned by root and readable by all' {
        $listing = & dpkg-deb -c $result.Package | Where-Object { $_ -match 'shortarrow-archive-keyring\.gpg$' }
        $listing | Should -Match '^-rw-r--r-- root/root .* \./usr/share/keyrings/shortarrow-archive-keyring\.gpg$'
        $extracted = Join-Path $inspect 'root'
        & dpkg-deb -x $result.Package $extracted
        (Get-FileHash (Join-Path $extracted 'usr' 'share' 'keyrings' 'shortarrow-archive-keyring.gpg')).Hash |
            Should -Be (Get-FileHash $result.Keyring).Hash
    }
}
