# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: review branch `claude/review-m7-bounties` (stacked on `claude/review-m6-decoys`, neither merged)
Adds in-world bounties on top of fake bags, recovery and raids.

### Done on this branch
- `BountyRecord` (pure, tested) replaces the unused `BountyPool`: contributions stack on the target's hideout record, one atomic claim, refusals for self/contributor/crewmate/cooldown, refunds.
- `BountyService`: debit-then-credit placement with refund on failure, takedown prompt on wanted players (2 s hold, 7 studs, on foot only), stun + bag drop, payout to the hunter's stash, logs and notices; Wanted tab with amount box; "Put 500 on <raider>" on raid reports; nameplates show bounties; engine scenario for 3+ players (contributor refused, hunter paid exactly once).

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 58/58 logic tests, both places build. Studio scenarios written, not run (no Studio here).

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; district blackouts; convoys; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools\verify-engine.ps1 -Players 1,3,5`; fix what it reports; play by hand per `docs/LAUNCH.md`.
2. Merge `claude/review-m6-decoys` then `claude/review-m7-bounties` if accepted (fast-forward in that order).
3. Then: crew-triggered blackouts (district outage with bounded duration and cooldown), then armored convoys.
