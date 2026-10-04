$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$output = Join-Path $projectRoot 'dist\BlackoutBay-Source.zip'
$files = [System.Collections.Generic.List[string]]::new()
foreach ($folder in @('src', 'docs', 'experimental', 'tests')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -File -Recurse) {
        if ($file.Name -notlike '*.generated.luau') { $files.Add($file.FullName) }
    }
}
foreach ($folder in @('tools\luau', 'tools\run-in-roblox')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -File) { $files.Add($file.FullName) }
}
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File) {
    if ($file.Extension -in @('.ps1', '.mjs', '.md')) { $files.Add($file.FullName) }
}
foreach ($name in @('README.md','Play Blackout Bay.cmd','default.project.json','dist\BlackoutBay.rbxlx','dist\manifest.json','dist\verification.txt','dist\engine-multiplayer-results.txt')) {
    $item = Join-Path $projectRoot $name
    if (Test-Path -LiteralPath $item) { $files.Add($item) }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [System.IO.File]::Open($output, [System.IO.FileMode]::Create)
try {
    $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in $files) {
            $entry = 'BlackoutBay/' + $file.Substring($projectRoot.Length + 1).Replace('\','/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file, $entry) | Out-Null
        }
    } finally { $archive.Dispose() }
} finally { $stream.Dispose() }
$check = [System.IO.Compression.ZipFile]::OpenRead($output)
try {
    if ($check.Entries.Count -ne $files.Count) { throw 'ZIP entry count mismatch' }
    if (-not $check.GetEntry('BlackoutBay/dist/BlackoutBay.rbxlx')) { throw 'Place missing from archive' }
    foreach ($entry in $check.Entries) {
        if ($entry.FullName -match 'library-identity|library-transfer|RobloxStudioInstaller|EngineTest|\.lock$') { throw 'Unexpected internal file in source archive' }
    }
    Write-Output ('ZIP PASS: ' + $check.Entries.Count + ' selected project files; no installers, Library metadata, or test place.')
} finally { $check.Dispose() }
Get-FileHash -LiteralPath $output -Algorithm SHA256
