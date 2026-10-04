# Opens the shipped place in a Studio play session through run-in-roblox (optional helper; File > Open works too).
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $PSScriptRoot 'run-in-roblox\run-in-roblox.exe'
if (-not (Test-Path -LiteralPath $runner)) { throw 'Local launcher missing. Open build\BlackoutBay.rbxl in Studio and press F5 instead.' }
& $runner --place (Join-Path $projectRoot 'build\BlackoutBay.rbxl') --script (Join-Path $projectRoot 'tests\engine\play-now.luau')
