# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: FROZEN review stack, QA pack on `claude/review-m11-studio-qa`
Development is frozen at `claude/review-m10-polish` `c99420b`. Stack and recovery: `docs/REVIEW_STACK.md` (`tools/verify-stack.sh`). Nothing merged.

### Done on `claude/review-m11-studio-qa` (QA pack, no new gameplay or presentation systems)
- `tests/engine/driver.server.luau` restructured into independent sections per system (crew, heist, vehicles, blackout, weather, decoys, police, convoy, raids, bounties, cross-system torture, performance tiers, disconnect). One `GLASSHOUSE_ENGINE_FAIL system= test= expected= actual=` line per failure, dependents SKIP instead of cascading, `GLASSHOUSE_ENGINE_SUMMARY` at the end. Existing success markers kept; new: WEATHER, TORTURE, TIERS, PERF lines.
- Performance capture: server `Stats` and per-client frame timing / memory / sound / emitter counts per phase (normal per tier, blackout, rain, storm, convoy, convoy+blackout, after-torture). Not run; `PERFORMANCE = UNVERIFIED`.
- Runner and `tools/verify-engine.ps1` continue past a failing player count and list every failed section; default counts 1,3,5.
- `tools/verify-stack.sh` verifies remote parity and fast-forward order of the whole stack.
- Config consistency: five UI/prompt strings now format their numbers from `Config` (bounty hold/range/cooldown on the Wanted tab, drill and lockdown seconds in objectives, dock-door and dual-swipe seconds, garage seat/bag counts). `Config.Museum.DockOpenSeconds` added for a previously literal 25.
- Docs: `STUDIO_QA_MASTER.md` (workflow, section map, markers, visual PASS/TUNE/FAIL checklist, perf table, torture plan), `ECONOMY_AUDIT.md`, `ASSET_INVENTORY.md`, `REVIEW_STACK.md`.

### Verification
`tools/check.sh`: 0 type errors, 0 lint warnings, 90/90 logic tests; both places build; `tools/verify-stack.sh` passes. Studio: not run.

### Decisions in force
Full stash exposure; banking enabled; 7-stud takedowns; m8 `9e259d6`, m9 `2f0ab3b`, m10 `c99420b` frozen; no merges; no new systems; tuning (wet-road traction, custom animations, StreamingEnabled, lighting budgets, vehicle numbers, camera feel, weather intensity, particle rates) waits for observed Studio results.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On a machine with Roblox Studio: check out `claude/review-m11-studio-qa`, run `tools\verify-engine.ps1 -Players 1,3,5`, then the human checklist in `docs/STUDIO_QA_MASTER.md`; record decisions and PERF lines there.
2. Tune only from that evidence; then merge the stack fast-forward in order (`docs/REVIEW_STACK.md`).
