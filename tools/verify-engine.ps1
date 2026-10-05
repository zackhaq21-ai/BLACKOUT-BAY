# Native Roblox Studio scenarios for Blackout Bay (carried over from the prototype's harness).
# Needs: Roblox Studio signed in, and run-in-roblox.exe in tools\run-in-roblox\ (see prototype/aurora-v0/tools/TOOLING.md).
# Does not need Rojo or Node: build\BlackoutBay-EngineTest.rbxl is committed. Rebuild it with tools/build.sh after source edits.
param([int[]]$Players = @(1, 3, 5))
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ($Players.Count -eq 0 -or @($Players | Where-Object { $_ -lt 1 -or $_ -gt 8 }).Count -gt 0) { throw 'Choose player counts from 1 through 8.' }
$runner = Join-Path $PSScriptRoot 'run-in-roblox\run-in-roblox.exe'
if (-not (Test-Path -LiteralPath $runner)) { throw 'run-in-roblox.exe is missing in tools\run-in-roblox. See prototype/aurora-v0/tools/TOOLING.md for provenance.' }
$place = Join-Path $projectRoot 'build\BlackoutBay-EngineTest.rbxl'
if (-not (Test-Path -LiteralPath $place)) { throw 'build\BlackoutBay-EngineTest.rbxl is missing. Run tools/build.sh (needs Rojo).' }
$template = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'tests\engine\runner.template.luau')
$generated = Join-Path $projectRoot 'tests\engine\runner.generated.luau'
$combined = Join-Path $projectRoot 'build\engine-results.txt'
$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add('Blackout Bay native Studio verification / ' + (Get-Date -Format o))
$failedCounts = @()
foreach ($count in $Players) {
    Set-Content -LiteralPath $generated -Value ($template.Replace('--[[COUNTS]] 1', [string]$count)) -Encoding utf8
    $resultPath = Join-Path $projectRoot ('build\engine-' + $count + '-results.txt')
    & $runner --place $place --script $generated 2>&1 | Tee-Object -FilePath $resultPath
    if ($LASTEXITCODE -ne 0) { $failedCounts += $count }
    foreach ($line in (Get-Content -LiteralPath $resultPath)) { if ($line -match 'GLASSHOUSE_') { $evidence.Add(($line -replace '^.*?(GLASSHOUSE_)', '$1')) } }
}
$evidence | Set-Content -LiteralPath $combined -Encoding utf8
Write-Host ('Evidence written to ' + $combined)
$fails = @($evidence | Where-Object { $_ -match '^GLASSHOUSE_ENGINE_FAIL ' })
$perf = @($evidence | Where-Object { $_ -match '^GLASSHOUSE_ENGINE_PERF ' })
Write-Host ('Sections failed: ' + $fails.Count + ' / performance samples: ' + $perf.Count)
foreach ($f in $fails) { Write-Host $f }
if ($failedCounts.Count -gt 0) { throw ('Native Studio scenario failed for player counts: ' + ($failedCounts -join ', ') + '. One line per failed section above (system / test / expected / actual).') }
