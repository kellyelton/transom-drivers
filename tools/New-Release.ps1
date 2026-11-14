<#
.SYNOPSIS
    Builds catalog.json from drivers/*.json, signs it with Ed25519 and optionally publishes GitHub release catalog-N.
.DESCRIPTION
    catalog.json = { schema_version, release, date, entries[] }, keys sorted, LF endings, entries ordered by id.
    The signature (catalog.json.sig, raw 64 bytes) is over the exact bytes of catalog.json:
        openssl pkeyutl -sign -rawin -inkey KEY -in catalog.json -out catalog.json.sig
    It is verified against keys/driver-catalog.pub.pem before anything is published. The private key stays outside
    the repository. -Publish creates the release with catalog.json, catalog.json.sig and the package assets in
    -AssetDir (<id>.zip) for entries whose redistribution is 'permitted' and that have a source under this release's
    download URL. Never put vendor-licensed binaries in -AssetDir.
.PARAMETER Release
    The release number. Default: one more than the newest catalog-N release on GitHub (1 when there is none).
#>
[CmdletBinding()]
param(
    [int]$Release,
    [string]$Key = (Join-Path $HOME '.transom\keys\driver-catalog.pem'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out'),
    [string]$AssetDir,
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& "$PSScriptRoot\Test-Entry.ps1" | Out-Null

if (-not $Release) {
    $tags = @(gh release list --repo kellyelton/transom-drivers --limit 200 --json tagName --jq '.[].tagName' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'gh release list failed; pass -Release.' }
    $max = ($tags | ForEach-Object { if ($_ -match '^catalog-(\d+)$') { [int]$Matches[1] } } | Measure-Object -Maximum).Maximum
    $Release = [int]$max + 1
}

$entries = @(Get-ChildItem (Join-Path $repoRoot 'drivers') -Filter *.json | Sort-Object { $_.BaseName } -CaseSensitive | ForEach-Object { Get-Content $_.FullName -Raw })
$doc = '{"schema_version":1,"release":' + $Release + ',"date":"' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') + '","entries":[' + ($entries -join ',') + ']}'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$cat = Join-Path $OutDir 'catalog.json'; $sig = "$cat.sig"
Write-Utf8Lf $cat (ConvertTo-StableJson $doc -SortKeys)

if (-not (Test-Path $Key)) { throw "Signing key not found: $Key" }
openssl pkeyutl -sign -rawin -inkey $Key -in $cat -out $sig
if ($LASTEXITCODE) { throw 'openssl sign failed.' }

# The pem and the hex file must be the same key; the OS ships the hex form.
$pem = Join-Path $repoRoot 'keys\driver-catalog.pub.pem'
$der = [Convert]::FromBase64String(((Get-Content $pem) -notmatch '-----' -join ''))
$hex = [BitConverter]::ToString($der[($der.Length - 32)..($der.Length - 1)]).Replace('-', '').ToLowerInvariant()
if ($hex -ne (Get-Content (Join-Path $repoRoot 'keys\driver-catalog.pub.hex') -Raw).Trim()) { throw 'keys/driver-catalog.pub.pem and .pub.hex are different keys.' }
openssl pkeyutl -verify -rawin -pubin -inkey $pem -in $cat -sigfile $sig
if ($LASTEXITCODE) { throw 'The signature does not verify against keys/driver-catalog.pub.pem.' }
"catalog-$Release : $cat ($($entries.Count) entries), signature verified"

if ($Publish) {
    $assets = @()
    if ($AssetDir) {
        foreach ($t in $entries | ConvertFrom-Json) {
            if ($t.redistribution -ne 'permitted') { continue }
            if (-not ($t.sources | Where-Object { $_.url -like "*/releases/download/catalog-$Release/*" })) { continue }
            $z = Join-Path $AssetDir "$($t.id).zip"
            if (-not (Test-Path $z)) { throw "Asset $z is missing." }
            $assets += $z
        }
    }
    gh release create "catalog-$Release" $cat $sig @assets --repo kellyelton/transom-drivers --title "Catalog $Release" --notes "Signed driver catalog, release $Release. Verify catalog.json.sig (Ed25519, raw) against keys/driver-catalog.pub.hex."
    if ($LASTEXITCODE) { throw 'gh release create failed.' }
}
