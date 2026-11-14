# transom-drivers

A signed catalog of Windows driver packages: which hardware each one drives, where it comes from, what its license says, and whether it has been seen working. Clients read only signed releases of this catalog, never the moving `main` branch.

"Unresolved" in a license field is honest metadata, never a quiet yes.

## Layout

- `drivers/<id>.json`: one entry per driver package version.
- `schema/entry.schema.json`: the entry schema (`schema_version` 1).
- `tools/`: pwsh 7 scripts. `Get-InfHardwareIds.ps1`, `New-Entry.ps1`, `Test-Entry.ps1`, `New-Release.ps1`; `tools/tests/Test-Tools.ps1` is the self-test; `tools/seed/Seed-Entries.ps1` shows how the first entries were made.
- `keys/`: the release public key (`driver-catalog.pub.hex`, the raw 32-byte Ed25519 key Transom ships; `driver-catalog.pub.pem` is the same key for openssl).

## An entry

| Field | Meaning |
| --- | --- |
| `id`, `name`, `version`, `date` | The package, as its INF's `DriverVer` says |
| `origin` | `vendor` (untouched vendor release), `official` (made by the Transom team), `community` |
| `verification` | `team`, `community`, `field`, `untested`. Only `team` and `untested` are set until the hosted statistics service exists |
| `tested` | Where the team verified it: `machine`, `transom` version, `capabilities` (`display`, `d3d11`, `wifi`, `ethernet`...) |
| `open_source`, `repo` | Whether the source is open, and where |
| `license`, `license_url`, `license_sha256` | SPDX id or the license's name, a link, and the hash of the license text in the package |
| `use` | May a user run it on Transom: `permitted`, `prohibited`, `unresolved` |
| `redistribution` | May Transom host or bundle it: `permitted`, `conditional`, `prohibited`, `unresolved`. Only `permitted` goes in a public image or a release asset |
| `hardware` | Hardware ids with the INF and model section they came from; generated from the INFs, never typed |
| `sources` | Download URLs with `sha256` and `size` of the download; `unverified: true` when nobody downloaded it |
| `extract` | Declarative only (`zip`, `cab`, `msi`, `7z`, `exe-7z`, `subfolder`, the kept files with their sha256). No scripts |
| `files` | The installed package: every file with sha256 and size, layout as in the original package |
| `stats` | `downloads`, `active`, `reverted`; empty until the hosted service exists |
| `notes` | Optional, plain-language caveats (an addition to the design's table) |

## Add an entry

1. Get the package into a folder, unpacked and unchanged (the layout becomes `files`).
2. Run `tools/New-Entry.ps1 -Path <folder> -Id <id> -Name ... -Origin vendor -License ... -Source @{ url = ...; sha256 = ...; size = ... }` with the license fields from the package's own license text. It writes `drivers/<id>.json` with the hash of every file and the hardware ids from the INFs. Leave `use` and `redistribution` at `unresolved` unless the license text clearly says otherwise. See `tools/seed/Seed-Entries.ps1` for worked calls.
3. Download the source yourself and check its hash before putting `sha256` in; otherwise pass `unverified = $true` and no hash.
4. `pwsh tools/Test-Entry.ps1 -Packages @{ '<id>' = '<folder>' }` checks every entry against the schema and, for packages you give it, the file hashes. `pwsh tools/tests/Test-Tools.ps1` runs the self-test.
5. Commit to a branch and open a pull request.

## Make a release

Only the catalog owner can: the private key (`%USERPROFILE%\.transom\keys\driver-catalog.pem`) never enters the repository.

```pwsh
pwsh tools/New-Release.ps1 -AssetDir <folder with <id>.zip for redistributable entries> -Publish
```

It runs `Test-Entry`, writes `out/catalog.json` (`schema_version`, `release`, `date`, `entries`; sorted keys, LF endings; `release` is one more than the newest `catalog-N` on GitHub, or `-Release N`), signs the exact bytes with `openssl pkeyutl -sign -rawin` (Ed25519), verifies the signature against `keys/driver-catalog.pub.pem`, and with `-Publish` creates the GitHub release `catalog-N` with `catalog.json`, `catalog.json.sig` and the package assets (only entries whose `redistribution` is `permitted`; vendor binaries are never uploaded). Transom checks the signature with the key it ships and refuses a release number below the highest it has seen.

Check a release by hand: `openssl pkeyutl -verify -rawin -pubin -inkey keys/driver-catalog.pub.pem -in catalog.json -sigfile catalog.json.sig`.
