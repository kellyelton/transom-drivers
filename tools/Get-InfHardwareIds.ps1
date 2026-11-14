<#
.SYNOPSIS
    Lists the hardware ids an INF (or every INF under a folder) installs, with the INF name and model section.
.DESCRIPTION
    Pure text parsing, no Windows APIs. Reads [Manufacturer], follows each "Name=Models[,TargetOS...]" to its
    model sections (Models, Models.NTamd64, Models.NTamd64.10.0...), and emits the first id of each model line
    (compatible ids after it are ignored). NTx86, NTarm and NTarm64 sections are skipped. Ids are upper-cased.
.OUTPUTS
    Objects with Id, Inf (file name) and Section (the section name as written in the INF).
#>
[CmdletBinding()]
param([Parameter(Mandatory, ValueFromPipeline)][string[]]$Path)
process {
    foreach ($p in $Path) {
        $files = if (Test-Path $p -PathType Container) { Get-ChildItem $p -Recurse -File -Filter *.inf } else { Get-Item $p }
        foreach ($file in $files) {
            # Sections: name -> lines, comments stripped (a ';' outside quotes), "\" continuations joined.
            $sec = @{}; $cur = $null; $carry = ''
            foreach ($raw in Get-Content $file.FullName) {
                $line = $carry + (($raw -replace '^((?:[^";]|"[^"]*")*);.*$', '$1').Trim()); $carry = ''
                if ($line.EndsWith('\')) { $carry = $line.TrimEnd('\').TrimEnd() + ' '; continue }
                if ($line -match '^\[(.+)\]$') { $cur = $Matches[1].Trim().ToLowerInvariant(); if (-not $sec.ContainsKey($cur)) { $sec[$cur] = [System.Collections.Generic.List[string]]::new() }; continue }
                if ($cur -and $line) { $sec[$cur].Add($line) }
            }
            $str = @{}
            foreach ($l in $sec['strings']) { if ($l -match '^([^=]+?)\s*=\s*"?(.*?)"?$') { $str[$Matches[1].ToLowerInvariant()] = $Matches[2] } }
            $sub = { param($s) [regex]::Replace($s.Trim().Trim('"'), '%([^%]+)%', { param($m) $v = $str[$m.Groups[1].Value.ToLowerInvariant()]; if ($null -ne $v) { $v } else { $m.Value } }) }
            $seen = @{}
            foreach ($m in $sec['manufacturer']) {
                $parts = $m -split '=', 2
                if ($parts.Count -ne 2) { continue }
                $f = @($parts[1] -split ',' | ForEach-Object { (& $sub $_).Trim() })
                $base = $f[0]
                $names = @($base) + @($f[1..($f.Count - 1)] | Where-Object { $_ } | ForEach-Object { "$base.$_" })
                if ($f.Count -eq 1) { $names = @($base, "$base.NTamd64") }  # no TargetOS list: Windows also tries the plain section
                foreach ($n in $names) {
                    if ($n -match '\.NT(x86|arm|arm64)(\.|$)') { continue }
                    foreach ($l in $sec[$n.ToLowerInvariant()]) {
                        $kv = $l -split '=', 2
                        if ($kv.Count -ne 2) { continue }
                        $cols = @($kv[1] -split ',')
                        if ($cols.Count -lt 2) { continue }
                        # "desc = install, hwid" or "desc = install,, hwid" (an empty reserved column, as Intel's Wi-Fi INFs write it).
                        $id = "$($cols[1..($cols.Count - 1)] | ForEach-Object { & $sub $_ } | Where-Object { $_ } | Select-Object -First 1)".ToUpperInvariant()
                        if (-not $id) { continue }
                        $key = "$id|$n"
                        if ($seen.ContainsKey($key)) { continue }
                        $seen[$key] = 1
                        [pscustomobject]@{ Id = $id; Inf = $file.Name; Section = $n }
                    }
                }
            }
        }
    }
}
