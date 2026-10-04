# Launch Guide (beginner friendly)

You need Roblox Studio. You do **not** need Rojo to play the prebuilt file.

## Option A — open the prebuilt place
1. Download `build/BlackoutBay.rbxl` from this repository.
2. Double-click it (or in Roblox Studio: **File → Open from File**).
3. Press **Play** (F5). Expected: a short load while the island is generated, then you stand inside a harbour pier unit with a neon letter over the bay. Top-left says "Open the job board at your pier".
4. Walk to the dark **JOB BOARD** on the back wall and press **E** (or tap the prompt). Press **Start job (solo)**.
5. Press **E** on the wooden partition to roll out the **Kestrel**, walk into the driver seat, drive out of the bay and turn right onto Dockside Street. The objective card shows the distance and direction to the Aurora Exchange.

## Option B — build from source (if you change code)
Requires [Rojo 7](https://rojo.space/) on your PATH.
```
tools/build.sh        # writes build/BlackoutBay.rbxl
```
Or run `rojo serve` and connect the Rojo Studio plugin to live-sync.

## Multiplayer test in Studio
1. **Test** tab → **Clients and Servers** → set players to 2–5 → **Start**.
2. In one client, open the job board and read the 4-letter **join code** on the crew card (top-right). In another client, type it in the board's **Crew code** box and press **Join crew**. The joiner is moved to the crew's pier.
3. Expected: the crew card lists both players and their split; the leader can change the split with +5 / −5 before pressing Start.

## Raid test (two clients)
1. Client A runs a heist and delivers; the payout lands in A's **stash** (top-right, under cash). Open the board → **Hideout** tab → upgrade to tier 3 when the stash allows (1,500 + 3,000 + 5,000).
2. Client B opens the board → **Raids** tab → **Raid** on A. Expected: B's objective says "Break into A's hideout" at A's pier (A is online and leads a crew). A sees a red raid panel.
3. B cuts the **shield breaker** on the unit's outside wall (hold E), walks to the safe, holds the prompt once; a gold "Cracking the safe" bar fills over ~25 s. Expected: bundles for A's ENTIRE stash appear by the safe; A's stash reads 0 and A is told the safe was cracked.
4. B leaves a bundle on the floor for 8 s: it vanishes and A's stash goes back up ("defences kept"). B carries another bundle to B's own pier delivery table: B's stash goes up after the job closes.
5. A leaves the server. B opens Raids again: A is now listed at the **Breakwater Lockup** (east of the piers). A rejoining later gets "Your hideout was raided while you were away" and the report in the Hideout tab.

## Controls
| Action | Keyboard / mouse | Controller | Touch |
|---|---|---|---|
| Interact | E (hold for timed actions) | X | tap the prompt |
| Sprint | Left Shift | L3 | RUN button |
| Sneak (half detection speed) | C | B | SNEAK button |
| Drop bag | G | Y | DROP button |
| Crew log | L | D-pad up | LOG button |
| Drive | W A S D | thumbsticks | on-screen |
| Leave vehicle | Space | A | jump button |

## Native Studio scenarios (prepared Windows PC)
```
tools\verify-engine.ps1 -Players 1,2,5
```
Needs run-in-roblox.exe in `tools\run-in-roblox\` (provenance in `prototype/aurora-v0/tools/TOOLING.md`). It opens its own Studio process per count, runs the scripted heist and raid against `build/BlackoutBay-EngineTest.rbxl`, and writes `build/engine-results.txt`. Nothing is published.

## Checks (developers)
```
tools/check.sh    # type check (luau-lsp + Roblox API), Selene lint, 42 logic tests
```
Tool versions used: Rojo 7.5.1, luau-lsp 1.52.0 with `tools/globalTypes.d.luau` from the same tag, Selene 0.29.0 with the local `roblox.yml`, Luau CLI (October 2025 release).
