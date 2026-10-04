$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$compiler = Join-Path $PSScriptRoot 'luau\luau-compile.exe'
$runner = Join-Path $PSScriptRoot 'luau\luau.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Official portable Luau validator is missing; see tools/TOOLING.md.' }
$log = [System.Collections.Generic.List[string]]::new()
$log.Add('Glasshouse verification / ' + (Get-Date -Format o))
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Filter '*.luau' -Recurse) {
    $out = & $compiler --null $file.FullName 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $($file.FullName) $out" }
    $log.Add('COMPILE PASS ' + $file.Name)
}
$tests = & $runner (Join-Path $projectRoot 'tests\gameplay.luau') 2>&1
if ($LASTEXITCODE -ne 0) { throw "Logic test failure: $tests" }
foreach ($line in $tests) { $log.Add([string]$line) }
foreach ($test in @('experimental\WorldEconomy.spec.luau', 'experimental\district_tests.luau')) {
    $result = & $runner (Join-Path $projectRoot $test) 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Experimental model test failure: $result" }
    foreach ($line in $result) { $log.Add([string]$line) }
}
$build = & node (Join-Path $PSScriptRoot 'build.mjs') 2>&1
if ($LASTEXITCODE -ne 0) { throw "Build failed: $build" }
$log.Add([string]$build)
[xml]$xml = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $projectRoot 'dist\BlackoutBay.rbxlx')
$scripts = $xml.SelectNodes('//Item[@class="Script" or @class="LocalScript" or @class="ModuleScript"]')
if ($scripts.Count -ne 8) { throw "Expected 8 scripts, found $($scripts.Count)" }
foreach ($script in $scripts) {
    $name = $script.Properties.SelectSingleNode('string[@name="Name"]').InnerText
    $source = $script.Properties.SelectSingleNode('ProtectedString[@name="Source"]').InnerText
    $candidate = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src') -Recurse -File |
        Where-Object { ($_.Name -replace '(\.server|\.client)?\.luau$','') -eq $name }
    if (@($candidate).Count -ne 1) { throw "Ambiguous source mapping $name" }
    $original = Get-Content -Raw -Encoding UTF8 -LiteralPath $candidate.FullName
    if ($source -cne $original) { throw "Embedded source mismatch: $name" }
}
$log.Add('XML PASS: 8 script sources match editable source exactly.')
$hash = Get-FileHash -LiteralPath (Join-Path $projectRoot 'dist\BlackoutBay.rbxlx') -Algorithm SHA256
$log.Add('PLACE SHA256 ' + $hash.Hash)
$log.Add('LIMIT: No Studio Play-mode, rendering, physics, or multiplayer verification in this tool run.')
$log | Set-Content -LiteralPath (Join-Path $projectRoot 'dist\verification.txt') -Encoding utf8
$log | Write-Output
