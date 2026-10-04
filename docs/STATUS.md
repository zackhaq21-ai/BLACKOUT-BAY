# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: review branch `claude/review-m6-decoys` (not merged)
Base: the merged recovery branch. Adds fake bags and the decoy-vehicle tactic on top of raids and recovery.

### Done on this branch
- `Config.Decoys`; `HideoutRecord.spend` (raid-locked, tested); `LootService.mintFake` / `clearFakes`; fakes mimic a kind visually and on nameplates, are always light, reveal themselves to non-crew on pickup, deliver as nothing, are never job loot, and expire at job close; zero-value bags are cleaned up by hideout retention.
- Job board: "Getaway kit" buttons (fake Trinket / Relic / Jewel / Core / stash) with the tactic note; engine scenario covers minting, carrying under the mimic label, delivery for nothing, and stash unchanged.

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 58/58 logic tests, both places build. Studio scenarios written, not run (no Studio here).

### Not implemented (from the full vision)
In-world bounties; player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; district blackouts; convoys; player combat; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools\verify-engine.ps1 -Players 1,2,5`; fix what it reports; play by hand per `docs/LAUNCH.md`.
2. Merge this review branch if accepted.
3. Then: in-world bounties (pure `BountyPool` is already tested), then blackouts.
