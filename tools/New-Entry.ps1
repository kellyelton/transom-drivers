<#
.SYNOPSIS
    Writes drivers/<id>.json from a local package folder plus metadata.
.DESCRIPTION
    files: every file under -Path (sha256, size, path relative to -Path with "/"), the original layout.
    hardware: every id the package's INFs install (Get-InfHardwareIds), or -Hardware when the package has no INF
    (Wintun's INF is inside wintun.dll). version and date come from the first INF's DriverVer unless given.
.EXAMPLE
    .\tools\New-Entry.ps1 -Path D:\pkg\netkvm -Id netkvm-100.103.104.30200 -Name 'NetKVM' -Origin vendor -OpenSource `
        -Repo https://github.com/virtio-win/kvm-guest-drivers-windows -License BSD-3-Clause -LicenseFile LICENSE.txt `
        -Use permitted -Redistribution permitted -Source @{ url = 'https://...'; sha256 = '...'; size = 123 }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9._-]*$')][string]$Id,
    [Parameter(Mandatory)][string]$Name,
    [string]$Version, [string]$Date,
    [Parameter(Mandatory)][ValidateSet('vendor', 'official', 'community')][string]$Origin,
    [ValidateSet('team', 'community', 'field', 'untested')][string]$Verification = 'untested',
    [hashtable[]]$Tested = @(),
    [switch]$OpenSource, [string]$Repo,
    [Parameter(Mandatory)][string]$License, [string]$LicenseUrl,
    [string]$LicenseFile,   # relative to -Path; its sha256 becomes license_sha256
    [ValidateSet('permitted', 'prohibited', 'unresolved')][string]$Use = 'unresolved',
    [ValidateSet('permitted', 'conditional', 'prohibited', 'unresolved')][string]$Redistribution = 'unresolved',
    [hashtable[]]$Hardware,  # @{ id; inf; section } when there is no INF to parse
    [Parameter(Mandatory)][hashtable[]]$Source,  # @{ url; sha256; size; unverified }
    [hashtable]$Extract,     # @{ type; subfolder; kept = @(@{path; sha256}) }
    [string]$Notes,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\drivers')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
$root = (Resolve-Path $Path).Path.TrimEnd('\')

$files = @(Get-ChildItem $root -Recurse -File | Sort-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } -CaseSensitive | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($root.Length + 1).Replace('\', '/'); sha256 = Get-Sha256 $_.FullName; size = [int64]$_.Length } })
if (-not $files) { throw "$root has no files." }

$infs = @(Get-ChildItem $root -Recurse -File -Filter *.inf | Sort-Object FullName)
if ($infs -and ((-not $Version) -or (-not $Date))) {
    $dv = Select-String $infs[0].FullName -Pattern '^\s*DriverVer\s*=\s*(\d+)/(\d+)/(\d+)\s*,\s*([0-9.]+)' | Select-Object -First 1
    if (-not $dv) { throw "$($infs[0].Name) has no DriverVer; pass -Version and -Date." }
    $g = $dv.Matches[0].Groups
    if (-not $Date) { $Date = '{0:0000}-{1:00}-{2:00}' -f [int]$g[3].Value, [int]$g[1].Value, [int]$g[2].Value }
    if (-not $Version) { $Version = $g[4].Value }
}
if (-not $Version -or -not $Date) { throw 'No INF to read DriverVer from; pass -Version and -Date.' }

$hw = @(if ($Hardware) { $Hardware | ForEach-Object { [ordered]@{ id = $_.id; inf = $_.inf; section = $_.section } } }
      else { @($infs | ForEach-Object { & "$PSScriptRoot\Get-InfHardwareIds.ps1" $_.FullName } | Sort-Object Id, Inf, Section |
                ForEach-Object { [ordered]@{ id = $_.Id; inf = $_.Inf; section = $_.Section } }) })

$e = [ordered]@{ schema_version = 1; id = $Id; name = $Name; version = $Version; date = $Date; origin = $Origin; verification = $Verification
    tested = @($Tested | Where-Object { $_ } | ForEach-Object { $t = [ordered]@{ machine = $_.machine; transom = $_.transom; capabilities = @($_.capabilities) }; if ($_.note) { $t.note = $_.note }; $t })
    open_source = [bool]$OpenSource }
if ($Repo) { $e.repo = $Repo }
$e.license = $License
if ($LicenseUrl) { $e.license_url = $LicenseUrl }
if ($LicenseFile) { $e.license_sha256 = Get-Sha256 (Join-Path $root $LicenseFile) }
$e.use = $Use; $e.redistribution = $Redistribution
$e.hardware = $hw
$e.sources = @($Source | ForEach-Object { $s = [ordered]@{ url = $_.url }; foreach ($k in 'sha256', 'size', 'unverified') { if ($null -ne $_[$k]) { $s[$k] = $_[$k] } }; $s })
if ($Extract) {
    $x = [ordered]@{ type = $Extract.type }
    if ($Extract.subfolder) { $x.subfolder = $Extract.subfolder }
    $x.kept = @($Extract.kept | ForEach-Object { [ordered]@{ path = $_.path; sha256 = $_.sha256 } })
    $e.extract = $x
}
$e.files = $files
$e.stats = [ordered]@{}
if ($Notes) { $e.notes = $Notes }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$out = Join-Path $OutDir "$Id.json"
Write-Utf8Lf $out (ConvertTo-StableJson ($e | ConvertTo-Json -Depth 10))
"$out ($($files.Count) files, $($hw.Count) hardware ids)"
