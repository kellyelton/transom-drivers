<#
.SYNOPSIS
    How the first entries were made, from the driver copies on the maintainer's PC (~\.transom) and the Windows DriverStore.
    Kept as provenance and as an example of New-Entry.ps1; a driver this PC lacks is skipped with a warning.
.PARAMETER Work
    Scratch folder (on F:) for staged packages and the release asset zips; assets land in <Work>\assets.
#>
param([string]$Work = 'F:\Source\transom-drivers-dl')
$ErrorActionPreference = 'Stop'
$new = Join-Path $PSScriptRoot '..\New-Entry.ps1'
$h = Join-Path $HOME '.transom'
$store = 'C:\Windows\System32\DriverStore\FileRepository'
$bsd = 'https://opensource.org/license/bsd-3-clause'
$virtio = 'https://github.com/virtio-win/kvm-guest-drivers-windows'
$asset = 'https://github.com/kellyelton/transom-drivers/releases/download/catalog-1'
$isoNote = 'The same files come from virtio-win-0.1.302.iso (https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso, 877373440 bytes, sha256 303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d, downloaded and hashed 2026-11-13). The catalog-1 asset zip repackages them unchanged (the ISO is 877 MB).'
function Skip($what, $path) { Write-Warning "$what is not on this PC ($path); skipped." }

# virtio-win: stage the package, zip it for the release, hash the zip.
New-Item -ItemType Directory -Force "$Work\assets", "$Work\pkg" | Out-Null
function Stage($id, $files) {
    $d = "$Work\pkg\$id"; Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $d | Out-Null
    $files | ForEach-Object { Copy-Item $_ $d }
    Copy-Item "$h\drivers\virtio-win-0.1.302\LICENSE.txt" $d
    $z = "$Work\assets\$id.zip"; Remove-Item $z -ErrorAction SilentlyContinue
    Compress-Archive -Path "$d\*" -DestinationPath $z
    $kept = @(Get-ChildItem $d -File | ForEach-Object { @{ path = $_.Name; sha256 = (Get-FileHash $_.FullName).Hash.ToLower() } })
    @{ dir = $d; zip = $z; sha = (Get-FileHash $z).Hash.ToLower(); size = (Get-Item $z).Length; kept = $kept }
}
$nk = "$h\virtio-win\NetKVM\2k25\amd64"; $vg = "$h\drivers\virtio-win-0.1.302"
if ((Test-Path "$nk\netkvm.sys") -and (Test-Path "$vg\viogpudo.sys")) {
    $p = Stage 'netkvm-100.103.104.30200' ("netkvm.inf", "netkvm.sys", "netkvm.cat", "netkvmp.exe" | ForEach-Object { "$nk\$_" })
    & $new -Path $p.dir -Id netkvm-100.103.104.30200 -Name 'VirtIO Ethernet Adapter (NetKVM), virtio-win 0.1.302' -Origin vendor -Verification team `
        -Tested @(@{ machine = 'QEMU virtio-net'; transom = '1.200'; capabilities = @('ethernet') }) `
        -OpenSource -Repo $virtio -License BSD-3-Clause -LicenseUrl $bsd -LicenseFile LICENSE.txt -Use permitted -Redistribution permitted `
        -Source @(@{ url = "$asset/netkvm-100.103.104.30200.zip"; sha256 = $p.sha; size = $p.size }) -Extract @{ type = 'zip'; kept = $p.kept } `
        -Notes "Windows 11 / Server 2025 build (virtio-win NetKVM\2k25\amd64). $isoNote The repository is private, so the asset needs a signed-in download until it is public."
    $p = Stage 'viogpudo-100.103.104.30200' ("viogpudo.inf", "viogpudo.sys", "viogpudo.cat" | ForEach-Object { "$vg\$_" })
    & $new -Path $p.dir -Id viogpudo-100.103.104.30200 -Name 'VirtIO GPU DOD (display-only), virtio-win 0.1.302' -Origin vendor -Verification team `
        -Tested @(@{ machine = 'QEMU virtio-vga'; transom = '1.191'; capabilities = @('display') }) `
        -OpenSource -Repo $virtio -License BSD-3-Clause -LicenseUrl $bsd -LicenseFile LICENSE.txt -Use permitted -Redistribution permitted `
        -Source @(@{ url = "$asset/viogpudo-100.103.104.30200.zip"; sha256 = $p.sha; size = $p.size }) -Extract @{ type = 'zip'; kept = $p.kept } `
        -Notes "viogpudo\w11\amd64. $isoNote The repository is private, so the asset needs a signed-in download until it is public."
} else { Skip 'virtio-win NetKVM/viogpudo' "$nk, $vg" }

# Intel HD graphics 31.0.101.2115 (the IT-pro zip; its Graphics folder is the package).
$ig = "$h\drivers\intel-gfx-31.0.101.2115\Graphics"
if (Test-Path $ig) {
    $kept = @('iigd_dch.inf', 'igdlh.cat', 'iglhxs64.vp' | ForEach-Object { @{ path = $_; sha256 = (Get-FileHash "$ig\$_").Hash.ToLower() } })
    & $new -Path $ig -Id intel-gfx-31.0.101.2115 -Name 'Intel Graphics driver 31.0.101.2115 (6th-10th Gen, DCH)' -Origin vendor -Verification team `
        -Tested @(@{ machine = 'Lenovo Yoga 900 (Intel HD 520)'; transom = '1.382'; capabilities = @('display') }, @{ machine = 'Lenovo Yoga 900 (Intel HD 520)'; transom = '1.391'; capabilities = @('d3d11') }) `
        -License 'Intel Graphics Drivers Software License Agreement (January 2020)' -LicenseUrl 'https://www.intel.com/content/www/us/en/download/762755/intel-6th-gen-processor-graphics-windows.html' -LicenseFile '..\license.txt' `
        -Use unresolved -Redistribution conditional `
        -Source @(@{ url = 'https://downloadmirror.intel.com/764512/gfx_win_101.2115.zip'; sha256 = '6f055541b3421db3527bf70bc21d13d5a6b26579e21ca454a66db957bcbfbc9a'; size = 521046942 }) `
        -Extract @{ type = 'zip'; subfolder = 'Graphics'; kept = $kept } `
        -Notes "Package = the zip's Graphics folder; the license text is the zip's top-level license.txt (hash checked against the download). Redistribution is conditional: Appendix B lets an OEM, IHV or ISV distribute the object code only embedded in or for an Intel-based product under an end-user license at least as restrictive as Appendix A, and the end-user terms (Appendix A) forbid distributing it; whether Transom qualifies is unresolved, as is use under another OS. Binaries are cab-compressed individually (.dl_/.sy_); the files Transom runs (igdkmd64.sys, igd10iumd64.dll, ...) are their expanded forms."
} else { Skip 'Intel graphics' $ig }

# NVIDIA 475.14 (only nv_dispi.inf and nvlddmkm.sys are on this PC; the INF was compared with the download's).
$nv = "$h\n1-nvidia"
if (Test-Path "$nv\nv_dispi.inf") {
    $stage = "$Work\pkg\nvidia-30.0.14.7514"; Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $stage | Out-Null
    Copy-Item "$nv\nv_dispi.inf", "$nv\nvlddmkm.sys" $stage
    & $new -Path $stage -Id nvidia-30.0.14.7514 -Name 'NVIDIA GeForce display driver 475.14 (DCH)' -Origin vendor -Verification untested `
        -License 'NVIDIA Software License Agreement (no license text in the local copy)' -Use unresolved -Redistribution unresolved `
        -Source @(@{ url = 'https://us.download.nvidia.com/Windows/475.14/475.14-desktop-win10-win11-64bit-international-dch-whql.exe'; sha256 = 'd602d0a5635ed492261dd8df34f4d159b36289cbdcb1c88b9f3b0c7947184ff5'; size = 740751984 }) `
        -Extract @{ type = 'exe-7z'; subfolder = 'Display.Driver'; kept = @(@{ path = 'nv_dispi.inf'; sha256 = (Get-FileHash "$nv\nv_dispi.inf").Hash.ToLower() }) } `
        -Notes 'files lists only the two files kept on the team PC (nv_dispi.inf, whose hash equals the one inside the download, and nvlddmkm.sys expanded from nvlddmkm.sy_); the full package also has the .cat and user-mode files. The team has not run this driver on real hardware to a verified result.'
} else { Skip NVIDIA $nv }

# Intel Wi-Fi: one entry per original DriverStore package Get-WifiDriver.ps1 -PciId all picks.
$wifi = @{
    'netwtw02.inf_amd64_669639d5a41714fa' = @{ v = '18.33.11.2'; fam = 'Netwtw02'; chips = 'Wireless 7260 family' }
    'netwtw04.inf_amd64_28271e5be9a9f6f4' = @{ v = '19.51.15.3'; fam = 'Netwtw04'; chips = 'Wireless 7265 / 3165 family' }
    'netwtw06.inf_amd64_c5f16d20642e3070' = @{ v = '20.70.3.3'; fam = 'Netwtw06'; chips = 'Wireless-AC 8260 / 8265 family' }
    'netwtw08.inf_amd64_0528484aad19a013' = @{ v = '24.80.0.2'; fam = 'Netwtw08'; chips = 'Wi-Fi 6 / 6E / 7 and Wireless-AC 9000 family, also carries Netwtw10/14/16' }
}
foreach ($dir in $wifi.Keys | Sort-Object) {
    $w = $wifi[$dir]; $pkg = Join-Path $store $dir
    if (-not (Test-Path $pkg)) { Skip "Intel Wi-Fi $($w.fam)" $pkg; continue }
    $team = $w.fam -eq 'Netwtw06'
    $tested = if ($team) { @(@{ machine = 'Lenovo Yoga 900 (Wireless-AC 8260)'; transom = '1.231'; capabilities = @('wifi'); note = 'Per the Transom team; the repo docs record the start and firmware load on a simulated 8260 (1.231).' }) } else { @() }
    & $new -Path $pkg -Id "intel-wifi-$($w.fam.ToLower())-$($w.v)" -Name "Intel Wi-Fi driver $($w.fam) $($w.v) ($($w.chips))" -Origin vendor `
        -Verification $(if ($team) { 'team' } else { 'untested' }) -Tested $tested `
        -License 'Intel proprietary (the package carries no license text)' -Use unresolved -Redistribution unresolved `
        -Source @(@{ url = "https://www.catalog.update.microsoft.com/Search.aspx?q=$($w.fam)%20$($w.v)"; unverified = $true }) `
        -Notes "Whole DriverStore package $dir, copied from the team PC's Windows install. The download location is Microsoft Update Catalog's search for this version; nobody has downloaded the original, so no hash and unverified. Intel also publishes Wi-Fi driver bundles at https://www.intel.com/content/www/us/en/download/19351/windows-10-and-windows-11-wi-fi-drivers-for-intel-wireless-adapters.html (not checked)."
}

# Wintun 0.14.1: the download is the zip; wintun.sys and its INF live in wintun.dll's resources.
$wz = "$Work\wintun"
if (Test-Path "$wz\wintun\bin\amd64\wintun.dll") {
    & $new -Path "$wz\wintun" -Id wintun-0.14.1 -Name 'Wintun 0.14.1 (layer 3 TUN adapter driver, inside wintun.dll)' -Origin vendor -Verification team `
        -Tested @(@{ machine = 'QEMU'; transom = '1.217'; capabilities = @('tunnel-adapter', 'tailscale'); note = "Tailscale 1.104's copy of wintun.dll (same hash as bin/amd64/wintun.dll here) creates its adapter and carries a ping through the ring; Tailscale reaches its sign-in (T8)." }) `
        -OpenSource -Repo 'https://git.zx2c4.com/wintun' -License 'Wintun Prebuilt Binaries License (WireGuard LLC)' -LicenseUrl 'https://www.wintun.net/' -LicenseFile 'LICENSE.txt' `
        -Use permitted -Redistribution conditional -Version 0.14.1 -Date '2021-10-17' `
        -Hardware @(@{ id = 'WINTUN'; inf = '(inside wintun.dll resources)'; section = 'Wintun' }) `
        -Source @(@{ url = 'https://www.wintun.net/builds/wintun-0.14.1.zip'; sha256 = '07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51'; size = 750540 }) `
        -Extract @{ type = 'zip'; subfolder = 'wintun'; kept = @(@{ path = 'bin/amd64/wintun.dll'; sha256 = (Get-FileHash "$wz\wintun\bin\amd64\wintun.dll").Hash.ToLower() }, @{ path = 'LICENSE.txt'; sha256 = (Get-FileHash "$wz\wintun\LICENSE.txt").Hash.ToLower() }) } `
        -Notes "There is no INF or .sys file to ship: wintun.dll carries wintun.sys and its INF as resources and installs them when it creates an adapter. The source is dual-licensed GPL-2.0 / MIT, but the prebuilt binaries (this download) are under a proprietary license: use is allowed; redistribution only alongside software that uses the DLL through the permitted API (wintun.h), otherwise with WireGuard LLC's written consent. date is the download's build date (the embedded INF's DriverVer was not read). The hardware id is Wintun's adapter id, not parsed from a file."
} else { Skip Wintun $wz }
