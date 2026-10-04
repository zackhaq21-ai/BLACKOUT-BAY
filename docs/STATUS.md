# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: review branch `claude/review-m5-recovery` (not merged)
Base: the merged reconciliation. Adds stolen-loot recovery missions (clue trail, physical intercept credit, recovery raid variant) on top of raids with full stash exposure. Builds to `build/BlackoutBay.rbxl` and `build/BlackoutBay-EngineTest.rbxl`.

### Done on this branch
- `HideoutRecord`: provisional reports opened at raid start and finalized in place; clues; `recoverable`, `noteRecovered`, `recover` (lock-gated, bounded by owed and by what that raid took, idempotent per raid id); 2 new tests.
- `RaidService`: bundles labelled "Stash of <victim>" with origin `raid:<id>`; clue trail from loot events; victim credit on delivery; `startRecovery`; recovery variant of the crack; recovery reports without a new window.
- Client: Hideout tab shows recovered amounts, the last clues and a "Recover N — trail goes cold in M min" button; raid HUD wording for both sides.
- Engine scenario: after the raid, the victim recovers exactly the stolen amount, the raider is debited exactly that, the victim's report shows it, and a second recovery is refused.

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 57/57 logic tests, both places build. Studio scenarios written, not run (no Studio here): `tools/verify-engine.ps1` on the prepared PC.

### Not implemented (from the full vision)
Decoy vehicles and fake bags; in-world bounties; player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; district blackouts; convoys; player combat; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools\verify-engine.ps1 -Players 1,2,5`; fix what it reports; play the raid and recovery by hand (`docs/LAUNCH.md`).
2. Merge this review branch if accepted.
3. Then: decoy vehicles and fake bags, then in-world bounties.
