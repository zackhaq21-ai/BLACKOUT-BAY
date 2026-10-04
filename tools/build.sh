#!/usr/bin/env bash
# Builds the native Roblox place file from source. Requires rojo 7.x on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build default.project.json -o build/Glasshouse.rbxl
rojo sourcemap default.project.json -o sourcemap.json
echo "Built build/Glasshouse.rbxl"
