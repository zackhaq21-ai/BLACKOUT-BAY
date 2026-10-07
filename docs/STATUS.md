# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: completion & retention pass, batch 2 on `claude/review-m14-living-world` (stacked on m13 `5e88d86`)
Blackout Bay = Glasshouse. Studio evidence pending; code-side systems designed and automatically tested.

### Done on this branch
- **Contacts** (`Core/ContactRules`, `ContactService`): Ines Varga (Dockmaster, museum brief + richest stash), Teo Lindqvist (deck mechanic, bucketed convoy ETA, storm warning; Operator), Priya Sandoval (Lineman, grid state/cooldown/duration; Runner). NPC rigs with Talk prompts; lines from authoritative state via `Dialogue` remote; telemetry.
- **Persistent crew identity** (`Core/CrewRecord`, `CrewStore`): durable record per owner, bounded members/history/milestones, validated + TextService-filtered rename with cooldown and per-request spacing, summary in the crew snapshot, rename UI for the leader.
- **Crew ledger wall**: physical board in every pier's living space written from the record on bind and on every note (jobs, raids taken/suffered, recovery, convoy crates, bounties, blackout resets, arrests, milestones).
- **Museum replay variation** (`Core/MuseumVariants`): five curated variants picked per restock (weighted, never the last, weather-gated), applied through existing systems: loot mix, lockdown delay, guard speed bonus, camera sweep, service entry (shutter down + dock open), maintenance power cut. Restock toast and job-start brief.
- **Storm convoy**: rare curated variant (Seawall Loop, one Heavy sealed crate of 5,000) through the existing convoy, weather and loot systems; banner line; `ConvoyState.variant`.
- **Accomplishments** (`Core/Accomplishments`, `AccomplishmentService`): ten originals, exactly-once `Accomplish` profile op with own Standing, crew milestones, museum entry detection (front/dock/roof) stored per profile.
- Scenario sections `contacts`, `identity`, `variant`, `accomplishments`, `stormConvoy`; hook actions for each.

### Verification
`tools/check.sh`: 0 type errors, 0 lint warnings, 114/114 logic tests; both places build; `tools/verify-stack.sh` passes. Studio: pending (TextService filtering, rigs, wall readability, variant effects, heavy carry are visual/live items).

### Decisions in force
Full stash exposure; banking enabled; 7-stud takedowns; progression thresholds and gates unchanged (200/600/1500/4000); m6–m13 preserved; no merges without approval; no economy value changes; no asset fills; no new currency.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: check out `claude/review-m14-living-world`, run `.\tools\verify-engine.ps1 -Players 1,3,5 -ExpectedBranch claude/review-m14-living-world`, paste the `GLASSHOUSE_*` lines back; then the human checklist in `docs/STUDIO_QA_MASTER.md` including the new first-session row.
2. Content density pass from `docs/DENSITY_AUDIT.md`: give purpose to empty blocks and rarely met mechanics without new systems; then Studio evidence decides tuning.
