# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: review branch `claude/review-m9-convoys` (stacked on m8 ← m7 ← m6 ← dev; none merged)
Adds the armored convoy world event on top of blackouts, bounties, fakes, recovery and raids.

### Done on this branch
- `ConvoyRules` (pure, tested): bounded definition, server-owned cargo validation with an economy ceiling, route choice (never the last route, away from players, malformed input ignored), breach eligibility, blackout breach factor, cargo claimed exactly once, monotone escalation, formation speed, abandonment, client-safe public state. Four `Blueprint.ConvoyRoutes` validated against the road graph.
- `ConvoyDriver` (NPC): waypoint driving on server-owned physics, obstruction probe (players and player cars), back-out when stuck. `ConvoyService`: anticipation → vehicles (two `Escort`, one `Armored`; seats disabled) → checkpoint halts → perception (escort sight scaled by the police vision scale) → escalation (alert/engaged/lockdown, strobes, heat, police through the existing dispatcher) → breach (server-timed hold at the rear doors, sealing after interruption) → crates minted as ledger items → extraction via the normal delivery/job payout → abandonment recovery → idempotent teardown; auto-scheduling with cooldown and jitter.
- Vehicles: `Armored` and `Escort` kinds with cargo box, armour plates, rear doors, cargo indicator, amber strobes, decals; an engine `Sound` hook on every chassis (ids blank). Audio cue hooks for announce/alert/breach/lost/delivered/radio (blank).
- Client: convoy line in the event banner (phase, nearest landmark, cargo state, crate count; red title once engaged), bootstrap and late-join sync. Engine scenario step `convoy` for 1/3/5 players.
- Consistency: blackout and convoy tests now read `Config.WorldEvents` directly, so every constant has one source (6 s / 75 s / 8 s / 300 s / +60 / 55% / 60% asserted once in `blackout_rules.spec`).

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 74/74 logic tests, both places build. Studio scenarios written, not run (no Studio here). Merge of the whole stack is HELD pending the owner's live verification.

### Earlier decisions still in force
Full stash exposure on raids; banking enabled; bounty takedown range 7 studs everywhere; m8 stays at `9e259d6`; keep m6–m9 pushed, separate, unmerged, in dependency order.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools\verify-engine.ps1 -Players 1,3,5`; fix what it reports; play by hand per `docs/LAUNCH.md`.
2. Merge m6 → m7 → m8 → m9 if accepted (fast-forward in that order).
3. Then the premium polish pass on the existing game (movement, animation transitions, camera, vehicle feel, lighting, weather, VFX, sound architecture, HUD, NPC perception, mobile/controller, performance, consistency, exploit regression) on a new review branch stacked on m9. No new large features.
