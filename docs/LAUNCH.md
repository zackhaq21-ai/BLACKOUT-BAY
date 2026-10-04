# Launch Guide (beginner friendly)

You need Roblox Studio. You do **not** need Rojo to play the prebuilt file.

## Option A — open the prebuilt place
1. Download `build/Glasshouse.rbxl` from this repository.
2. Double-click it (or in Roblox Studio: **File → Open from File**).
3. Press **Play** (F5). Expected: a short load while the island is generated, then you stand inside a harbour pier unit with a neon letter over the bay. Top-left says "Open the job board at your pier".
4. Walk to the dark **JOB BOARD** on the back wall and press **E** (or tap the prompt). Press **Start job (solo)**.
5. Press **E** on the wooden partition to roll out the **Kestrel**, walk into the driver seat, drive out of the bay and turn right onto Dockside Street. The objective card shows the distance and direction to the Aurora Exchange.

## Option B — build from source (if you change code)
Requires [Rojo 7](https://rojo.space/) on your PATH.
```
tools/build.sh        # writes build/Glasshouse.rbxl
```
Or run `rojo serve` and connect the Rojo Studio plugin to live-sync.

## Multiplayer test in Studio
1. **Test** tab → **Clients and Servers** → set players to 2–5 → **Start**.
2. In one client, open the job board and read the 4-letter **join code** on the crew card (top-right). In another client, type it in the board's **Crew code** box and press **Join crew**. The joiner is moved to the crew's pier.
3. Expected: the crew card lists both players and their split; the leader can change the split with +5 / −5 before pressing Start.

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

## Checks (developers)
```
tools/check.sh    # type check (luau-lsp + Roblox API), Selene lint, 42 logic tests
```
Tool versions used: Rojo 7.5.1, luau-lsp 1.52.0 with `tools/globalTypes.d.luau` from the same tag, Selene 0.29.0 with the local `roblox.yml`, Luau CLI (October 2025 release).
