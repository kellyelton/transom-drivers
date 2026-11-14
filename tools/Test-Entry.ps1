<#
.SYNOPSIS
    Checks every drivers/*.json against schema/entry.schema.json and, where the package is on this PC, its file hashes.
.PARAMETER Packages
    Map of entry id to the local package folder: @{ 'netkvm-...' = 'D:\pkg\netkvm' }. Entries not listed are looked
    up as <PackageRoot>\<id>; an entry whose package is not found is checked against the schema only.
#>
[CmdletBinding()]
param([hashtable]$Packages = @{}, [string]$PackageRoot, [string]$Drivers = (Join-Path $PSScriptRoot '..\drivers'))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
$schema = Join-Path $PSScriptRoot '..\schema\entry.schema.json'
$bad = 0; $n = 0
foreach ($f in Get-ChildItem $Drivers -Filter *.json | Sort-Object Name) {
    $n++
    $problems = @()
    $text = Get-Content $f.FullName -Raw
    $ok = Test-Json -Json $text -SchemaFile $schema -ErrorAction SilentlyContinue -ErrorVariable ev
    if (-not $ok -or $ev) { $problems += "schema: $($ev -join '; ')" }
    else {
        $e = $text | ConvertFrom-Json
        if ($f.BaseName -ne $e.id) { $problems += "file name is not the id '$($e.id)'" }
        if ($text.Contains("`r")) { $problems += 'CRLF line endings' }
        if ($e.verification -ne 'untested' -and -not $e.tested) { $problems += "verification '$($e.verification)' needs tested entries" }
        if ($e.verification -eq 'untested' -and $e.tested) { $problems += 'tested entries on an untested driver' }
        $dup = @($e.files | Group-Object path | Where-Object Count -gt 1)
        if ($dup) { $problems += "duplicate file paths: $($dup.Name -join ', ')" }
        $dir = if ($Packages.ContainsKey($e.id)) { $Packages[$e.id] } elseif ($PackageRoot) { Join-Path $PackageRoot $e.id }
        if ($dir -and (Test-Path $dir -PathType Container)) {
            foreach ($file in $e.files) {
                $p = Join-Path $dir $file.path
                if (-not (Test-Path $p)) { $problems += "missing $($file.path)" }
                elseif ((Get-Sha256 $p) -ne $file.sha256) { $problems += "hash differs: $($file.path)" }
            }
            $state = "hashes checked ($($e.files.Count) files)"
        } else { $state = 'schema only (package not local)' }
    }
    if ($problems) { $bad++; Write-Host "FAIL $($f.Name): $($problems -join ' | ')" -ForegroundColor Red }
    else { Write-Host "ok   $($f.Name): $state" }
}
if ($bad) { throw "$bad of $n entries failed." }
"$n entries ok"
