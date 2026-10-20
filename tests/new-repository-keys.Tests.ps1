#Requires -Version 7
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script = Join-Path $PSScriptRoot '..' 'scripts' 'new-repository-keys.ps1'

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $path | Out-Null
        $path
    }

    function Invoke-Gpg([string] $GpgHome, [string[]] $Arguments, [string] $InputText) {
        $all = @('--homedir', $GpgHome, '--batch', '--yes') + $Arguments
        if ($PSBoundParameters.ContainsKey('InputText')) {
            $output = $InputText | & gpg @all 2>&1
        }
        else {
            $output = & gpg @all 2>&1
        }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    }

    function Stop-Agent([string] $GpgHome) {
        & gpgconf --homedir $GpgHome --kill gpg-agent 2>$null
    }

    function Get-KeyRecord([string] $GpgHome, [string] $File) {
        $lines = & gpg --homedir $GpgHome --batch --with-colons --show-keys $File
        $pub = ($lines | Where-Object { $_ -like 'pub:*' -or $_ -like 'sec:*' } | Select-Object -First 1).Split(':')
        $fpr = ($lines | Where-Object { $_ -like 'fpr:*' } | Select-Object -First 1).Split(':')[9]
        [pscustomobject]@{ Algorithm = $pub[3]; Created = [long] $pub[5]; Expires = $pub[6]; Curve = $pub[16]; Fingerprint = $fpr }
    }
}

Describe 'new-repository-keys.ps1' {
    BeforeAll {
        $keyring = New-TempDirectory
        $secrets = New-TempDirectory
        $ambientHome = New-TempDirectory
        $savedHome = $env:GNUPGHOME
        $env:GNUPGHOME = $ambientHome
        $passphrase = ConvertTo-SecureString 'standby-test-passphrase' -AsPlainText -Force

        & $script -KeyringDirectory $keyring -SecretDirectory $secrets -StandbyPassphrase $passphrase

        $env:GNUPGHOME = $savedHome
        $inspectHome = New-TempDirectory
        $publicFiles = @(Get-ChildItem $keyring -Filter '*.asc')
        $records = $publicFiles | ForEach-Object { Get-KeyRecord $inspectHome $_.FullName }
        $signing = Get-KeyRecord $inspectHome (Join-Path $secrets 'signing.secret.asc')
        $standby = Get-KeyRecord $inspectHome (Join-Path $secrets 'standby.secret.asc')
    }

    AfterAll {
        foreach ($dir in $keyring, $secrets, $ambientHome, $inspectHome) {
            Stop-Agent $dir
            Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
        }
    }

    It 'writes one public key per role to the keyring directory, named by fingerprint' {
        $publicFiles.Count | Should -Be 2
        $publicFiles.BaseName | Sort-Object | Should -Be ($records.Fingerprint | Sort-Object)
        $records.Fingerprint | Sort-Object | Should -Be (@($signing.Fingerprint, $standby.Fingerprint) | Sort-Object)
    }

    It 'makes both keys Ed25519' {
        $records | ForEach-Object {
            $_.Algorithm | Should -Be '22'
            $_.Curve | Should -Be 'ed25519'
        }
    }

    It 'expires the signing key three years after creation and the standby key never' {
        $created = [DateTimeOffset]::FromUnixTimeSeconds($signing.Created)
        $expires = [DateTimeOffset]::FromUnixTimeSeconds([long] $signing.Expires)
        $expires | Should -BeGreaterThan $created.AddYears(3).AddDays(-2)
        $expires | Should -BeLessThan $created.AddYears(3).AddDays(2)
        $standby.Expires | Should -BeNullOrEmpty
    }

    It 'produces a signing secret whose clearsigned output verifies against the public keys alone' {
        $signerHome = New-TempDirectory
        $verifyHome = New-TempDirectory
        try {
            (Invoke-Gpg $signerHome @('--import', (Join-Path $secrets 'signing.secret.asc'))).ExitCode | Should -Be 0
            $release = Join-Path $signerHome 'Release'
            Set-Content -Path $release -Value 'Origin: test' -NoNewline
            $inRelease = Join-Path $signerHome 'InRelease'
            (Invoke-Gpg $signerHome @('--pinentry-mode', 'loopback', '--passphrase', '', '--clearsign', '--output', $inRelease, $release)).ExitCode | Should -Be 0

            $trusted = Join-Path $verifyHome 'trusted.gpg'
            foreach ($file in $publicFiles) {
                (Invoke-Gpg $verifyHome @('--no-default-keyring', '--keyring', $trusted, '--import', $file.FullName)).ExitCode | Should -Be 0
            }
            & gpgv --keyring $trusted $inRelease 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            foreach ($dir in $signerHome, $verifyHome) { Stop-Agent $dir; Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
        }
    }

    It 'protects the standby secret with the given passphrase' {
        $standbyHome = New-TempDirectory
        try {
            (Invoke-Gpg $standbyHome @('--pinentry-mode', 'loopback', '--passphrase', 'standby-test-passphrase', '--import', (Join-Path $secrets 'standby.secret.asc'))).ExitCode | Should -Be 0
            $data = Join-Path $standbyHome 'data'
            Set-Content -Path $data -Value 'x' -NoNewline
            (Invoke-Gpg $standbyHome @('--pinentry-mode', 'loopback', '--passphrase', 'wrong', '--clearsign', '--output', "$data.wrong", $data)).ExitCode | Should -Not -Be 0
            Stop-Agent $standbyHome
            (Invoke-Gpg $standbyHome @('--pinentry-mode', 'loopback', '--passphrase', 'standby-test-passphrase', '--clearsign', '--output', "$data.right", $data)).ExitCode | Should -Be 0
        }
        finally {
            Stop-Agent $standbyHome
            Remove-Item -Recurse -Force $standbyHome -ErrorAction SilentlyContinue
        }
    }

    It 'writes a revocation certificate for each key' {
        foreach ($fpr in $signing.Fingerprint, $standby.Fingerprint) {
            Join-Path $secrets "$fpr.rev" | Should -Exist
        }
    }

    It 'leaves the ambient GNUPGHOME untouched' {
        @(Get-ChildItem $ambientHome -Force).Count | Should -Be 0
    }
}

Describe 'new-repository-keys.ps1 with a secret directory inside the repository' {
    It 'refuses before generating anything' {
        $keyring = New-TempDirectory
        $inside = Join-Path $PSScriptRoot '..' 'secrets-must-not-be-here'
        try {
            $passphrase = ConvertTo-SecureString 'x' -AsPlainText -Force
            { & $script -KeyringDirectory $keyring -SecretDirectory $inside -StandbyPassphrase $passphrase } | Should -Throw '*outside the repository*'
            $inside | Should -Not -Exist
            @(Get-ChildItem $keyring).Count | Should -Be 0
        }
        finally {
            Remove-Item -Recurse -Force $keyring, $inside -ErrorAction SilentlyContinue
        }
    }
}
