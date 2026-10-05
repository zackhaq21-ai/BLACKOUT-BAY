# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: review branch `claude/review-m8-blackouts` (stacked on m7 ← m6 ← dev; none of the three merged)
Adds the crew-triggered harbour blackout and a small world-event framework on top of bounties, fakes, recovery and raids.

### Done on this branch
- `WorldEventRules` (pure, tested): one active instance per event id, bounded duration, per-event cooldown counted from expiry or early stop. `WorldEventService`: registry + handlers + `WorldEvent` replication (server-clock `endsAt`), late-join sync, bootstrap snapshot.
- `BlackoutRules` (pure, tested): sabotage eligibility (alive, on foot, not jailed, crew job active), reset open to anyone on foot, clamped NPC vision scale, clamped duration/cooldown.
- `BlackoutService`: Harbour Substation prompts (server-timed holds; forged triggers ignored), grid-light inventory (lamps, lit windows, neon signs, pier lamps; lighthouse and police station keep power), moonlit Lighting tween (never black), battery emergency lamps, museum power cut + shutter lift via `SecurityService.setGridPower`, pier shields down + lasers unpowered via `RaidService.setGridDown`, guard/cop vision scale, no new plate reads, saboteur heat +60, announcements, crew log, idempotent restore.
- Client: bottom-centre event banner with countdown, generic hold bar, bootstrap/reconnect handling. Engine scenario step `blackout` for 1/3/5 players; `docs/STUDIO_VERIFICATION_PENDING.md` created.

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 65/65 logic tests, both places build. Studio scenarios written, not run (no Studio here). Owner review of m7 (2026-10-05): merge HELD until live verification; m8 inherits that hold.

### Earlier decisions still in force
Full stash exposure on raids; banking enabled; bounty takedown range 7 studs everywhere; keep m6 and m7 pushed, separate, unmerged, in dependency order.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; convoys; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools\verify-engine.ps1 -Players 1,3,5`; fix what it reports; play by hand per `docs/LAUNCH.md`.
2. Merge `claude/review-m6-decoys`, then `claude/review-m7-bounties`, then `claude/review-m8-blackouts` if accepted (fast-forward in that order).
3. Then: armored convoys on `claude/review-m9-convoys` (stacked on m8, using `WorldEventService`), then polish batches.
