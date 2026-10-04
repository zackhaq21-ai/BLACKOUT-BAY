# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: reconciliation merged into `claude/roblox-dev-instructions-co8a58`
Base: the milestone 3 repository. The Studio-tested prototype (`prototype/aurora-v0`) was reconciled: its tested pieces were ported, nothing in the main game was replaced, and the raid rule was changed to the owner's high-stakes decision. Builds to `build/BlackoutBay.rbxl`; the engine-test place is `build/BlackoutBay-EngineTest.rbxl`.

### Done on this branch
- **Raids expose the full earned stash** (no floor / fraction / cap; one crack per raid lock). Player-facing warnings on the HUD, Hideout tab, Raids tab and stash signs. Cosmetics, entitlements, XP untouched.
- **Branding**: player-facing title Blackout Bay; internal codename Glasshouse kept in module names and log prefixes.
- **Ported from the prototype**: profile transaction model (run credited once per job id, receipt + entitlement together, pass, equip) applied to the stored profile inside UpdateAsync with a retry queue; commerce scaffold (disabled, zero ids, ProcessReceipt only after a durable write); cosmetics catalog with earned suits and a Looks tab; result tiers; relocation with network-ownership hold; character speed sanity; the StudioTestService harness (`tests/engine/`, `tools/verify-engine.ps1`).
- Milestone 2 and 3 systems preserved unchanged otherwise.

### Verification
`tools/check.sh`: type check 0 errors (now covering `tests/engine`), lint 0 warnings, 55/55 logic tests, both places build. See `docs/TEST_RESULTS.md`. **Studio scenarios are written but have not run** (no Studio here): run `tools/verify-engine.ps1` on the prepared PC.

### Not implemented (from the full vision)
Stolen-loot recovery missions (window recorded in reports); decoy vehicles and fake bags; in-world bounties; player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; district blackouts; convoys; player combat; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools/verify-engine.ps1` (counts 1, 2, 5). Fix anything the scenario reports, then play solo and a 2-client raid by hand (`docs/LAUNCH.md`).
2. Decided: banking stays enabled (`Config.Hideout.BankingEnabled = true`); review branch merged on 2026-10-04.
3. Next: stolen-loot recovery (use `report.recoveryUntil` and the bundle ids), decoys and fake bags, in-world bounties.
