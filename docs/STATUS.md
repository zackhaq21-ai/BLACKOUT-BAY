# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current milestone: `m2-first-heist` (milestones 1 + 2 of the brief)
**Playable on paper, not yet playtested.** The full solo/crew loop for the Aurora Exchange exists in source and builds to `build/Glasshouse.rbxl`. No Studio session has run it.

### Implemented (SOURCE IMPLEMENTED + AUTOMATED CHECKS PASSED)
- World generated from data: island, roads with overpass, canal, 34 buildings, plaza, Lantern Cross, lighthouse, parking deck + gantry, police station + jail, six pier hideouts, street cars. `src/shared/MapBlueprint.luau`, `src/server/Builders/*`.
- Aurora Exchange: three entries, mezzanine, vault with dual readers and drill, security office (code board, CCTV switch, keycard), loading dock keypad/release, alley junction box, 4 guards with doorway-safe patrols and navmesh chases, 4 sweeping cameras, alarm lights, shutter, lockdown, restock cycle.
- Crews 1–5 with join codes, leader split, kick, leave; one hideout unit per crew; delivery table; garage spawns Kestrel/Courier.
- Physical loot ledger with carry/drop/trunk/deliver; heavy vs light movement rules; theft attribution and crew evidence log.
- Mission flow with phases, auto-close rules (25 s grace), payouts by frozen split, results screen with the story log.
- Police heat, vehicle recognition, 10 NPC cruisers with dispatcher (delay + cap), road-graph driving, ramming, cuffing, barricade at Lantern Cross; jail with lockpick / auto-release / lobby switch.
- Persistence with session locking and never-overwrite-on-failure; dev data prefix.
- Client: HUD (objective + direction, crew card, carry card, threat eye with watcher direction, security/police pills, cash, toasts, cuffing bar, jail panel, vehicle health, crew log), job board, keypad, results, keyboard/controller/touch bindings, constraint-car driving, nameplates showing cash/carry/wanted, audio cue hooks with visual equivalents.
- Pure logic with tests but **not integrated**: `RareCarCycle`, `BountyPool`.

### Not implemented (from the full vision)
Hideout raids/defences/upgrade tiers and offline stash; bounties in-world; player police faction, helicopter/plane/flying bike and vehicle earning; rare car in-world and its persistence decision; blackouts beyond the museum power cut; armored convoys; stolen-loot recovery missions; decoy vehicles and fake bags; cosmetics and any purchase flow; sound assets; custom meshes/animations; performance profiling.

### Key decisions (see docs/DESIGN.md for the full list)
Rojo project layout as the build process (**ASSUMPTION**; no prior workflow existed). Shared museum with no per-crew instancing. Fixed NPC difficulty config. Six hideout units shared round-robin if more than six crews. Audio ids left blank rather than invented.

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 42/42 logic tests, place builds. See `docs/TEST_RESULTS.md`. Studio playtest: **not done** (no Studio in this environment).

### Blockers
Roblox Studio access is required to playtest, tune vehicles, confirm NPC rigs/navmesh, and measure performance.

### Next task
1. Open `build/Glasshouse.rbxl` in Studio, Play solo: confirm spawn at a pier, board opens, job starts, Kestrel drives, museum front smash → case cut → carry → trunk → deliver → results. Fix anything that breaks, in this order: vehicle handling, guard movement, prompt reachability, HUD layout on a phone emulator.
2. Then a 2–5 client server test: join by code, split, dual swipe, theft of a dropped bag between crews, arrest + lobby release.
3. Then milestone 3: hideout stash and raids (design the exposed-stash rule explicitly first), decoy vehicles/fake bags, bounties in-world.
