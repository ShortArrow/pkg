#Requires -Version 7
<#
.SYNOPSIS
Reads, writes and edits APT package indexes, one entry per package, version and architecture.

.DESCRIPTION
An entry is an ordered dictionary of the fields of one stanza of a `Packages` file, in the
order they were written. A multi-line value holds its continuation lines, leading space
included, joined by "`n". Every function here leaves its inputs unchanged.
#>

function ConvertFrom-Deb822 {
    <#
    .SYNOPSIS
    Parses deb822 text, such as a `Packages` file, into one entry per stanza.
    #>
    param([AllowEmptyString()] [string] $Text)

    $entry = $null
    $field = $null
    foreach ($line in $Text -split "`r?`n") {
        if ($line -eq '') {
            if ($entry) { $entry }
            $entry = $null
        }
        elseif ($line -match '^[ \t]' -and $field) {
            $entry[$field] += "`n$line"
        }
        elseif ($line -match '^([^:\s]+):\s?(.*)$') {
            $entry ??= [ordered]@{}
            $field = $Matches[1]
            $entry[$field] = $Matches[2]
        }
        else {
            throw "Line is not a field or a continuation: '$line'"
        }
    }
    if ($entry) { $entry }
}

function ConvertTo-Deb822 {
    <#
    .SYNOPSIS
    Writes entries as deb822 text: stanzas separated by one blank line, ending with a newline.
    #>
    param([AllowEmptyCollection()] [System.Collections.IDictionary[]] $Entries)

    $stanzas = foreach ($entry in $Entries) {
        ($entry.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "`n"
    }
    if (-not $stanzas) { return '' }
    ($stanzas -join "`n`n") + "`n"
}

function Get-EntryKey([System.Collections.IDictionary] $Entry) {
    "$($Entry.Package) $($Entry.Version) $($Entry.Architecture)"
}

function Get-SortedEntry([System.Collections.IDictionary[]] $Entries) {
    $Entries | Sort-Object { $_.Package }, { $_.Version }, { $_.Architecture }
}

function Set-PackageVersion {
    <#
    .SYNOPSIS
    Returns the index with every entry for the package versions in Entries replaced by Entries.

    .DESCRIPTION
    All architectures of a package version are replaced together, so an architecture a
    re-run no longer builds leaves the index. The result is ordered by package, version and
    architecture.
    #>
    param(
        [AllowEmptyCollection()] [System.Collections.IDictionary[]] $Index,
        [System.Collections.IDictionary[]] $Entries
    )

    $replaced = @($Entries | ForEach-Object { "$($_.Package) $($_.Version)" })
    $kept = @($Index | Where-Object { "$($_.Package) $($_.Version)" -notin $replaced })
    Get-SortedEntry ($kept + $Entries)
}

function Remove-PackageVersion {
    <#
    .SYNOPSIS
    Returns the index without any architecture of one package version; refuses a version it does not hold.
    #>
    param(
        [System.Collections.IDictionary[]] $Index,
        [string] $Package,
        [string] $Version
    )

    $removed = { $_.Package -eq $Package -and $_.Version -eq $Version }
    if (-not ($Index | Where-Object $removed)) {
        throw "The index holds no $Package $Version."
    }
    $Index | Where-Object { -not (& $removed) }
}

function Join-PackageIndex {
    <#
    .SYNOPSIS
    Merges per-architecture indexes into one, holding each package, version and architecture once.

    .DESCRIPTION
    An architecture-independent entry appears in every architecture's `Packages`; it is
    kept once. Two entries for the same package, version and architecture that differ in
    any field are refused, because the published site would then contradict itself.
    #>
    param([object[]] $Indexes)

    $byKey = [ordered]@{}
    foreach ($entry in $Indexes | ForEach-Object { $_ }) {
        $key = Get-EntryKey $entry
        if (-not $byKey.Contains($key)) {
            $byKey[$key] = $entry
        }
        elseif ((ConvertTo-Deb822 $byKey[$key]) -cne (ConvertTo-Deb822 $entry)) {
            throw "The indexes hold different entries for $key."
        }
    }
    Get-SortedEntry @($byKey.Values)
}

function Select-ArchitectureIndex {
    <#
    .SYNOPSIS
    Returns the entries that belong in one architecture's `Packages`: its own and the architecture-independent ones.
    #>
    param(
        [System.Collections.IDictionary[]] $Index,
        [string] $Architecture
    )

    $Index | Where-Object { $_.Architecture -in $Architecture, 'all' }
}

Export-ModuleMember -Function ConvertFrom-Deb822, ConvertTo-Deb822, Set-PackageVersion, Remove-PackageVersion, Join-PackageIndex, Select-ArchitectureIndex
