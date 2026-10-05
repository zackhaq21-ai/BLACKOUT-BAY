# Native Roblox Studio scenarios for Blackout Bay (carried over from the prototype's harness).
# Needs: Roblox Studio signed in, and run-in-roblox.exe in tools\run-in-roblox\ (see prototype/aurora-v0/tools/TOOLING.md).
# Does not need Rojo or Node: build\BlackoutBay-EngineTest.rbxl is committed. Rebuild it with tools/build.sh after source edits.
#
# PREFLIGHT (runs first, stops on any mismatch so the wrong build is never tested):
#   repository remote must be zackhaq21-ai/BLACKOUT-BAY; the checked-out branch must equal -ExpectedBranch;
#   HEAD must equal -ExpectedHead when given; the working tree must be clean; the engine-test place must be the
#   committed one (blob hash equals HEAD:build/BlackoutBay-EngineTest.rbxl); the prototype harness is never used.
param(
    [int[]]$Players = @(1, 3, 5),
    [string]$ExpectedBranch = 'claude/review-m12-studio-fixes',
    [string]$ExpectedHead = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ($Players.Count -eq 0 -or @($Players | Where-Object { $_ -lt 1 -or $_ -gt 8 }).Count -gt 0) { throw 'Choose player counts from 1 through 8.' }

function Invoke-Git([string[]]$GitArgs) {
    $out = & git -C $projectRoot @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('git ' + ($GitArgs -join ' ') + ' failed: ' + ($out -join ' ')) }
    return ($out -join "`n").Trim()
}

Write-Host '== preflight'
$remote = Invoke-Git @('remote', 'get-url', 'origin')
if ($remote -notmatch 'zackhaq21-ai/BLACKOUT-BAY') { throw ('STOP: wrong repository remote: ' + $remote) }
$branch = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')
if ($branch -ne $ExpectedBranch) { throw ('STOP: wrong branch: ' + $branch + ' (expected ' + $ExpectedBranch + ')') }
$head = Invoke-Git @('rev-parse', '--short', 'HEAD')
$headFull = Invoke-Git @('rev-parse', 'HEAD')
if ($ExpectedHead -ne '' -and -not $headFull.StartsWith($ExpectedHead)) { throw ('STOP: wrong HEAD: ' + $head + ' (expected ' + $ExpectedHead + ')') }
$dirty = Invoke-Git @('status', '--porcelain', '--untracked-files=no')
if ($dirty -ne '') { throw ("STOP: working tree has uncommitted changes:`n" + $dirty) }
$place = Join-Path $projectRoot 'build\BlackoutBay-EngineTest.rbxl'
if (-not (Test-Path -LiteralPath $place)) { throw 'STOP: build\BlackoutBay-EngineTest.rbxl is missing. Run tools/build.sh (needs Rojo).' }
$placeHash = Invoke-Git @('hash-object', $place)
$committedHash = Invoke-Git @('rev-parse', 'HEAD:build/BlackoutBay-EngineTest.rbxl')
if ($placeHash -ne $committedHash) { throw 'STOP: build\BlackoutBay-EngineTest.rbxl differs from the committed place for this HEAD. Rebuild with tools/build.sh and commit, or check out the committed file.' }
$driver = Join-Path $projectRoot 'tests\engine\driver.server.luau'
if (-not (Test-Path -LiteralPath $driver)) { throw 'STOP: tests\engine\driver.server.luau is missing; this is not the review-stack checkout.' }
if ((Get-Content -Raw -LiteralPath $driver) -notmatch 'GLASSHOUSE_ENGINE_SUMMARY') { throw 'STOP: the scenario in this checkout is not the sectioned master scenario.' }
Write-Host ('   repo    ' + $remote)
Write-Host ('   branch  ' + $branch)
Write-Host ('   head    ' + $head)
Write-Host ('   place   build\BlackoutBay-EngineTest.rbxl (committed blob ' + $committedHash.Substring(0, 12) + ')')
Write-Host '   harness tests\engine (prototype/aurora-v0 is never executed by this script)'

$runner = Join-Path $PSScriptRoot 'run-in-roblox\run-in-roblox.exe'
if (-not (Test-Path -LiteralPath $runner)) { throw 'run-in-roblox.exe is missing in tools\run-in-roblox. See prototype/aurora-v0/tools/TOOLING.md for provenance.' }
$template = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'tests\engine\runner.template.luau')
$generated = Join-Path $projectRoot 'tests\engine\runner.generated.luau'
$combined = Join-Path $projectRoot 'build\engine-results.txt'
$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add('Blackout Bay native Studio verification / ' + (Get-Date -Format o))
$evidence.Add('GLASSHOUSE_ENGINE_PREFLIGHT repo=' + $remote + ' branch=' + $branch + ' head=' + $head + ' place=' + $committedHash.Substring(0, 12))
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
