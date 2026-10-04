param([int[]]$Players = @(1,2,3,4,5))
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ($Players.Count -eq 0 -or @($Players | Where-Object { $_ -lt 1 -or $_ -gt 5 }).Count -gt 0) { throw 'Choose crew counts from 1 through 5.' }
$combined = Join-Path $projectRoot 'dist\engine-multiplayer-results.txt'
foreach ($count in $Players) {
    & node (Join-Path $PSScriptRoot 'build-engine-test.mjs') $count
    if ($LASTEXITCODE -ne 0) { throw 'Test-place generation failed.' }
    $resultPath = Join-Path $projectRoot ('dist\engine-' + $count + '-results.txt')
    & (Join-Path $PSScriptRoot 'run-in-roblox\run-in-roblox.exe') --place (Join-Path $projectRoot 'dist\BlackoutBay-EngineTest.rbxlx') --script (Join-Path $projectRoot 'tests\engine_runner.generated.luau') 2>&1 | Tee-Object -FilePath $resultPath
    if ($LASTEXITCODE -ne 0) { throw ('Native Studio scenario failed for ' + $count + ' players. See ' + $resultPath) }
}
$evidence = [System.Collections.Generic.List[string]]::new()
$evidence.Add('Native Roblox Studio verification / ' + (Get-Date -Format o))
foreach ($count in $Players) {
    $content = Get-Content -LiteralPath (Join-Path $projectRoot ('dist\engine-' + $count + '-results.txt'))
    foreach ($line in $content) { if ($line -match '^GLASSHOUSE_') { $evidence.Add($line) } }
}
$evidence | Set-Content -LiteralPath $combined -Encoding utf8
