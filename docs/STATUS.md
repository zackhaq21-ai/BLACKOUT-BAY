# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: evidence-driven phase on `claude/review-m12-studio-fixes` (stacked on m11 `8ea2970`)
Blackout Bay (player-facing) = Glasshouse (codename): one game, one repository. Freeze partially lifted: changes need Studio evidence, a real bug, an incomplete journey step or a measurement.

### Done on this branch
- Studio evidence #1 (1-player run, character ~113 studs from an "Enter" interaction): classified TEST-HARNESS. "Enter" belongs to the preserved prototype harness, not this scenario. Same hazard class guarded here: `move()` confirms server-side arrival (6 studs) with up to three relocate retries and a measured-distance failure; `trigger()` reports distance on refusal. No gameplay distance or security rule changed.
- Dead config flag `Config.Mission.TutorialHints` (never read) removed.
- Journey audit (code-level, see below). Stack manifest and verifier extended to m12.

### Player-journey audit (code-level; Studio observation pending)
- BLOCKS PLAY: none found in code.
- BROKEN: none found in code; Studio evidence is the arbiter.
- INCOMPLETE: settings surface is graphics-only (no volume controls; moot while every audio id is blank); no in-game explanation of raids/bounties beyond board text and toasts.
- FUNCTIONAL BUT ROUGH: onboarding is a welcome toast plus the idle objective "Open the job board at your pier" and a controls hint; the Results screen is the only progression recap.
- POLISH / OPTIONAL: see `docs/STUDIO_VERIFICATION_PENDING.md` and `docs/ASSET_INVENTORY.md`.

### Verification
`tools/check.sh`: 0 type errors, 0 lint warnings, 90/90 logic tests; both places build; `tools/verify-stack.sh` passes. Studio: the current scenario has not yet run on the prepared PC.

### Decisions in force
Full stash exposure; banking enabled; 7-stud takedowns; m6–m11 preserved unchanged; no merges without approval; no economy changes, no StreamingEnabled, no asset fills until evidence.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: check out `claude/review-m12-studio-fixes`, run `tools\verify-engine.ps1 -Players 1,3,5` against `build/BlackoutBay-EngineTest.rbxl` (not the prototype harness), paste the `GLASSHOUSE_*` lines back; then the human checklist in `docs/STUDIO_QA_MASTER.md`.
2. Diagnose each failure (game / harness / timing / physics / DataStore / UI / tuning / performance), fix the root cause here, rerun gates, retest.
