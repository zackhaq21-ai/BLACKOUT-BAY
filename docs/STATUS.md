# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current milestone: `m3-hideouts` (milestone 3 of the brief: stash and raids)
**Playable on paper, not yet playtested.** Milestone 2 (first heist) plus hideout stash, six defence tiers, offline-safe raids with an exclusive store lock, retention, live defender alerts and raid reports. Builds to `build/Glasshouse.rbxl`. No Studio session has run it.

### Implemented (SOURCE IMPLEMENTED + AUTOMATED CHECKS PASSED)
- Everything from milestone 2 (world, Aurora Exchange heist, crews, physical loot, missions and payouts, NPC police and jail, persistence, client).
- **Milestone 3**: `StashRules` and `HideoutRecord` (pure, tested), `HideoutStore` (DataStore + ordered index + memory fallback), `DefenseBuilder` (safe, alarm, shield + breaker, pier door, lasers), `RaidService` (lock claim, entry, server-timed crew-assisted safe crack, bundle minting, laser stun + bag drop, retention, reports, lockup lifecycle, live raid HUD for raiders and defenders), payouts to stash, bank/upgrade from the board's Hideout tab, Raids tab listing richest hideouts and online leaders, raid reports with unread marking and a "raided while away" alert, nameplates show stash and tier.
- Pure logic with tests but **not integrated**: `RareCarCycle`, `BountyPool`.

### Not implemented (from the full vision)
Stolen-loot recovery missions (the report records the window); decoy vehicles and fake bags; in-world bounties; player police faction, helicopter/plane/flying bike, vehicle earning; rare car in-world and its persistence decision; district blackouts; armored convoys; player combat (defenders cannot fight intruders); cosmetics and purchases; sound assets; custom meshes/animations; performance profiling.

### Key decisions (see docs/DESIGN.md)
Rojo layout as the build process. Shared museum, no instancing. Fixed NPC difficulty config. Payouts to the raidable stash with fee-based banking (**ASSUMPTION**). Separate hideout DataStore with pure transforms inside UpdateAsync. Online leaders raided at their pier, everyone else at the Breakwater Lockup. Audio ids left blank.

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 52/52 logic tests, place builds. See `docs/TEST_RESULTS.md`. Studio playtest: **not done** (no Studio in this environment).

### Blockers
Roblox Studio access is required to playtest, tune vehicles and defences, confirm NPC rigs/navmesh, verify DataStore behaviour across two servers, and measure performance.

### Next task
1. Studio: play the milestone 2 loop end to end (see docs/LAUNCH.md), then the raid loop: earn a stash, upgrade to tier 3+, have a second client raid it (pier raid while online, lockup raid after the owner leaves), confirm the lock blocks a third client, confirm the report appears on rejoin.
2. Fix what breaks, in this order: vehicle handling, guard movement, prompt reachability, laser heights vs. jump, HUD layout on a phone emulator.
3. Then: stolen-loot recovery missions (use `report.recoveryUntil` / `recoveryRaider`), decoy vehicles and fake bags, in-world bounties.
