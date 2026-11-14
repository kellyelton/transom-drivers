# Self-test: pwsh tools/tests/Test-Tools.ps1
$ErrorActionPreference = 'Stop'
$r = @(& "$PSScriptRoot\..\Get-InfHardwareIds.ps1" "$PSScriptRoot\sample.inf")
$got = ($r | ForEach-Object { "$($_.Id)@$($_.Section)" } | Sort-Object) -join ';'
$want = (@('PCI\VEN_1234&DEV_0001@Acme.NTamd64', 'PCI\VEN_1234&DEV_0002&SUBSYS_00011234@Acme.NTamd64',
    'PCI\VEN_1234&DEV_0003@Acme.NTamd64.10.0...19041', 'PCI\VEN_1234&DEV_0006@Acme.NTamd64.10.0...19041.more', 'ROOT\SAMPLE@Other') | Sort-Object) -join ';'
if ($got -ne $want) { throw "Get-InfHardwareIds: got`n$got`nwanted`n$want" }
"ok: Get-InfHardwareIds"

# Test-Entry accepts a real entry and rejects broken ones (unknown field, bad enum, wrong id).
$tmp = Join-Path ([IO.Path]::GetTempPath()) "te-$([guid]::NewGuid().ToString('N'))"; New-Item -ItemType Directory $tmp | Out-Null
try {
    $good = Get-Content (Get-ChildItem "$PSScriptRoot\..\..\drivers\*.json" | Select-Object -First 1) -Raw
    $id = ($good | ConvertFrom-Json).id
    [IO.File]::WriteAllText("$tmp/$id.json", $good)
    & "$PSScriptRoot\..\Test-Entry.ps1" -Drivers $tmp | Out-Null
    foreach ($bad in @(($good -replace '"use": "[a-z]+"', '"use": "yes"'), ($good -replace '"stats":', '"zzz": 1, "stats":'))) {
        [IO.File]::WriteAllText("$tmp/$id.json", $bad)
        $failed = $false; try { & "$PSScriptRoot\..\Test-Entry.ps1" -Drivers $tmp *>$null } catch { $failed = $true }
        if (-not $failed) { throw 'Test-Entry accepted a broken entry.' }
    }
} finally { Remove-Item $tmp -Recurse -Force }
"ok: Test-Entry"
