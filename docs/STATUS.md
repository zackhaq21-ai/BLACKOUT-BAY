# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: completion & retention pass, batch 1 on `claude/review-m13-progression` (stacked on m12 `f001b44`)
Blackout Bay = Glasshouse, one game. Studio evidence pending (owner's PC); code-side systems designed and automatically tested now.

### Done on this branch
- Player-journey audit (code): the loop exists end to end; what was missing was *why continue* (progression beyond cosmetics), *what do I do first* (static idle line), and any pacing between jobs and the deeper systems.
- **Standing** (`Core/Standing`, `ProgressionService`): ranks on the existing durable XP channel; option unlocks (fakes/raids at Runner, bounties/convoy intel at Operator) enforced server-side at the action with a one-line reason; awards from convoy crates, raids, recovery, bounties, blackout resets through a merge-safe `Standing` profile op credited once per id with per-source daily diminishing against the stored counters and a crew bonus; jobs keep the `Run` op with the same diminishing. Rank-up toasts, Results "+N Standing", Looks header with rank and next unlock.
- **Onboarding** (`Core/Onboarding`, `OnboardingService`): monotonic first-session steps from observed play, one toast per step, idle objective hints, returning players skip, malformed stored steps reset; never locks anything.
- **Telemetry** (`TelemetryService`): internal bounded ring, Studio print, counts exposed to the engine hook; events for job start/close, standing awards, unlock blocks, onboarding steps, convoy breach/fence, raid/recovery end, bounty claim, blackout cut/reset.
- Profile schema v2 (`awardsSeen`, `standingDay`, `onboarding`) with validating migration; `ProfileOps.configure` injects Standing/Onboarding so CLI tests, server and Studio run the same code.
- Scenario sections `gates` (Drifter refusals) and `progression` (Standing rose, onboarding done, telemetry), marker `GLASSHOUSE_ENGINE_PROGRESSION_SUCCESS`.

### Verification
`tools/check.sh`: 0 type errors, 0 lint warnings, 99/99 logic tests; both places build; `tools/verify-stack.sh` passes. Studio: pending.

### Decisions in force
Full stash exposure; banking enabled; 7-stud takedowns; m6–m12 preserved unchanged; no merges without approval; no economy value changes, no StreamingEnabled, no asset fills until evidence; progression unlocks options only.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: check out `claude/review-m13-progression`, run `.\tools\verify-engine.ps1 -Players 1,3,5 -ExpectedBranch claude/review-m13-progression`, paste the `GLASSHOUSE_*` lines back; then the human checklist in `docs/STUDIO_QA_MASTER.md` including the new first-session row.
2. Batch 2 of the completion pass: contacts and in-world job discovery on the existing board/event plumbing (few memorable originals, config-driven), crew identity persistence (name, record), replay variation for the museum job (curated entry/security/weather/loot combinations), accomplishments. Each with tests; no economy value changes.
