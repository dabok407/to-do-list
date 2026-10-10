$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$storeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../store'))
$report = Get-Content -LiteralPath (Join-Path $storeRoot 'assets/image-verification.json') -Raw | ConvertFrom-Json
if ($report.screenshots -ne 56 -or $report.assets -ne 4) { throw 'Verify the current KO/EN images including both iPhone sizes before packaging.' }
$names = @('01-calendar','02-overdue','03-start','04-repeat','05-stats-detail','06-stats','07-privacy')
$packages = @()
foreach ($language in @('ko', 'en')) {
    $suffix = if ($language -eq 'en') { '-en' } else { '' }
    foreach ($platform in @('app-store', 'play-store')) {
        $devices = if ($platform -eq 'app-store') { @('iphone', 'iphone-large', 'ipad') } else { @('android') }
        $files = [System.Collections.Generic.List[object]]::new()
        foreach ($device in $devices) {
            foreach ($name in $names) {
                $relative = if ($language -eq 'en') { "screenshots/en/$device/$name.png" } else { "screenshots/$device/$name.png" }
                $entry = $report.results | Where-Object file -EQ $relative
                if (-not $entry -or $entry.language -ne $language) { throw "Missing verified image: $relative" }
                $source = Join-Path $storeRoot $relative
                if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "Image changed since verification: $relative" }
                $files.Add(@{ source = $source; entry = "$device/$name.png" })
            }
        }
        $icon = if ($platform -eq 'app-store') { 'app-store-icon-1024.png' } else { 'play-icon-512.png' }
        $files.Add(@{ source = (Join-Path $storeRoot "assets/$icon"); entry = "assets/$icon" })
        if ($platform -eq 'play-store') {
            $feature = "play-feature-1024x500$suffix.png"
            $files.Add(@{ source = (Join-Path $storeRoot "assets/$feature"); entry = "assets/$feature" })
        }
        foreach ($file in $files) {
            if ($file.entry.StartsWith('assets/')) {
                $assetEntry = $report.results | Where-Object file -EQ $file.entry
                if (-not $assetEntry -or -not $assetEntry.sha256) { throw "Missing verified store asset: $($file.entry)" }
                if ((Get-FileHash -LiteralPath $file.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $assetEntry.sha256) { throw "Asset changed since verification: $($file.entry)" }
            }
        }
        $zipPath = Join-Path $storeRoot "assets/$platform-images$suffix.zip"
        # FileMode.Create overwrites only this explicitly named generated archive.
        $zipStream = [IO.File]::Open($zipPath, [IO.FileMode]::Create)
        $archive = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in $files) {
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.source, $file.entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } finally { $archive.Dispose(); $zipStream.Dispose() }
        $check = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            if ($check.Entries.Count -ne $files.Count) { throw "Wrong archive entry count: $zipPath" }
            foreach ($file in $files) {
                $entryStream = $check.GetEntry($file.entry).Open()
                try {
                    $hasher = [Security.Cryptography.SHA256]::Create()
                    try { $actual = [Convert]::ToHexString($hasher.ComputeHash($entryStream)).ToLowerInvariant() }
                    finally { $hasher.Dispose() }
                } finally { $entryStream.Dispose() }
                if ($actual -ne (Get-FileHash -LiteralPath $file.source -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Archive content mismatch: $($file.entry)" }
            }
        } finally { $check.Dispose() }
        $packages += @{ file = [IO.Path]::GetFileName($zipPath); language = $language; entries = $files.Count; sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant() }
        Write-Output "PASS $platform $language archive: $($files.Count) entries match the verified PNGs."
    }
}
@{ verified_at = [DateTime]::UtcNow.ToString('o'); packages = $packages } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $storeRoot 'assets/package-verification.json') -Encoding utf8
