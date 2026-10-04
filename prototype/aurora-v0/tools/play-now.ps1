$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $PSScriptRoot 'run-in-roblox\run-in-roblox.exe'
if (-not (Test-Path -LiteralPath $runner)) { throw 'Local Roblox launcher is missing. Open dist/BlackoutBay.rbxlx in Studio and press F5 instead.' }
& $runner --place (Join-Path $projectRoot 'dist\BlackoutBay.rbxlx') --script (Join-Path $projectRoot 'tests\play-now.luau')
