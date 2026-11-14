# Shared helpers, dot-sourced by the tools.

# JSON text with LF line endings and a final LF. -SortKeys orders every object's keys (ordinal), for byte-stable output.
function ConvertTo-StableJson([Parameter(Mandatory)][string]$Json, [switch]$SortKeys) {
    $sort = $null
    $sort = {
        param($n)
        if ($n -is [System.Collections.IDictionary]) {
            $o = [ordered]@{}
            foreach ($k in ($n.Keys | Sort-Object { $_ } -CaseSensitive)) { $o[$k] = & $sort $n[$k] }
            $o
        } elseif ($n -is [System.Collections.IList]) { , @($n | ForEach-Object { & $sort $_ }) }
        else { $n }
    }
    $obj = $Json | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
    if ($SortKeys) { $obj = & $sort $obj }
    $node = [System.Text.Json.Nodes.JsonNode]::Parse(($obj | ConvertTo-Json -Depth 50 -Compress))
    $opt = [System.Text.Json.JsonSerializerOptions]::new()
    $opt.WriteIndented = $true
    $opt.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    $node.ToJsonString($opt).Replace("`r`n", "`n") + "`n"
}

function Write-Utf8Lf([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false)) }

function Get-Sha256([string]$Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
