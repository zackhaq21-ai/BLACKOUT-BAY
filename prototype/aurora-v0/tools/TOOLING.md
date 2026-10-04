# Tool provenance

- Official Luau 0.741 portable Windows tools:
  https://github.com/luau-lang/luau/releases/tag/0.741
- Download: https://github.com/luau-lang/luau/releases/download/0.741/luau-windows.zip
- Downloaded archive SHA-256:
  BE90C3223F3DC26777EF234244C2B1EAE16B3C574F1AB7D1446972F72C28CAB1
- Binaries are local validators, not game dependencies. The source bundle does not need
  them to open in Studio. No PATH/system-tool configuration was changed.
- Roblox Studio installer: https://setup.rbxcdn.com/RobloxStudioInstaller.exe
  Authenticode: Valid, Roblox Corporation. Installed after explicit user authorization.
- Installed executable observed:
  %LOCALAPPDATA%\Roblox\Versions\version-76e1a02649ad4f35\RobloxStudioBeta.exe
- Build tool uses only Node.js built-in fs/path/crypto/url modules. No npm installation.

- Native Studio automation: run-in-roblox 0.3.0, from the MIT-licensed
  https://github.com/rojo-rbx/run-in-roblox project. This is a third-party development
  helper, not an official Roblox product. Its Rust/Luau source was reviewed before use.
  Downloaded release archive SHA-256:
  590738BF134C0A1D3D6F865089BEC8288FE7B7EC388471780F1F48B22D12440F.
  It installs a temporary local plugin, opens its own Studio process, communicates
  through localhost, and removes the plugin/closes its own process on completion.
  It does not upload or publish the place. License notices accompany both tools.
- Tests use Roblox's official StudioTestService ExecutePlayModeAsync and
  ExecuteMultiplayerTestAsync APIs in a separate local test document:
  https://create.roblox.com/docs/reference/engine/classes/StudioTestService.
- tools/verify-engine.ps1 runs the full 1-5 native matrix, opening local client windows.
  tools/play-now.ps1 opens a solo play session with only an ordinary Start command.
  Run one Studio helper at a time. Stop the play session to close the helper's instance.
  Existing user-opened Studio instances are not closed by these scripts.

The inherited computer-use skill was read, but this delegated tool catalog does not
expose node_repl, the required desktop automation runtime. No UI was clicked or
captured. The native place was opened with an authorized Start-Process command.
Studio's process title subsequently contained the full BlackoutBay.rbxlx path.
