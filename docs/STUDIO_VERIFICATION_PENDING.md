# Studio verification debt

Everything here is SOURCE IMPLEMENTED and AUTOMATED CHECKS PASSED (type check, lint, logic tests, place builds) but **not** STUDIO PLAYTESTED or LIVE VERIFIED. No Roblox Studio exists in the build environment. Run `tools\verify-engine.ps1 -Players 1,3,5` on the prepared Windows PC; it writes `build/engine-results.txt`. Then play by hand per `docs/LAUNCH.md`. Tick a row only with observed evidence.

Legend per row: AUTOMATED (what already passed here) · 1P / 3P / 5P (Studio Clients-and-Servers runs) · DATASTORE (live persistence) · VISUAL (looked right) · PERF (measured) · MARKER (printed line or on-screen result that proves success).

| Feature | Branch | Automated | 1P | 3P | 5P | DataStore | Visual | Perf | Expected success marker |
|---|---|---|---|---|---|---|---|---|---|
| Core heist loop (crew, job, smash, cut, drive, trunk, deliver, retry) | `claude/roblox-dev-instructions-co8a58` | PASSED | PENDING | PENDING | PENDING | PENDING (profile save/load) | PENDING | PENDING | `GLASSHOUSE_ENGINE_CAR`, payout in stash, job closes |
| Full-exposure raids, retention, reports, lock + cooldown | dev branch (merged) | PASSED | n/a | PENDING | PENDING | PENDING (two servers, one record) | PENDING | PENDING | `GLASSHOUSE_ENGINE_RAID_SUCCESS`, owner stash 0, bundles delivered once |
| Stolen-loot recovery (exact amount, one claim chain) | dev branch (merged) | PASSED | n/a | PENDING | PENDING | PENDING | PENDING | PENDING | `GLASSHOUSE_ENGINE_RECOVERY_SUCCESS` |
| Fake bags and decoy cars | `claude/review-m6-decoys` (unmerged) | PASSED | PENDING | PENDING | PENDING | n/a | PENDING (nameplate shows a Jewel) | PENDING | "That bag was a fake." on delivery |
| Bounties: funding, contributor/crewmate refused, forged trigger refused, 7-stud range, one payout | `claude/review-m7-bounties` (unmerged) | PASSED | n/a | PENDING | PENDING | PENDING (bounty held on the target's record) | PENDING | PENDING | `GLASSHOUSE_ENGINE_BOUNTY_SUCCESS`, hunter stash +exactly the bounty |
| Bounty concurrency (two hunters finish the same second) | `claude/review-m7-bounties` | logic-tested (one claim) | n/a | PENDING | PENDING | PENDING | n/a | n/a | one payout, second hunter told "no bounty" |
| Disconnect/respawn during takedown, crack, hold | m7 | guarded in code | PENDING | PENDING | PENDING | n/a | n/a | n/a | no duplicate payout, no stuck bars |
| Blackout: eligibility, server-timed cut, lights/sky/emergency, cameras, shields, vision scale, heat | `claude/review-m8-blackouts` (unmerged) | PASSED (logic + scenario written) | PENDING | PENDING | PENDING | n/a | PENDING (moonlit, not black; amber lamps) | PENDING (Lighting tween + ~300 part property writes) | `GLASSHOUSE_ENGINE_BLACKOUT_SUCCESS`, banner countdown |
| Blackout: reset counterplay, cooldown, expiry restore, late-join banner | m8 | PASSED (logic) | PENDING | PENDING | PENDING | n/a | PENDING | n/a | lights return, cabinet shows the cooldown, a joiner during the blackout sees the banner |
| Blackout: raid during blackout (shield open without the breaker, lasers off, breaker then grid restore does not re-raise) | m8 | code-reviewed | n/a | PENDING | PENDING | n/a | PENDING | n/a | raider enters the bay with no breaker prompt needed |
| Convoy: spawn validity (off players, on road, facing the route), three vehicles drive the route in formation, checkpoint halts, arrival at the depot | `claude/review-m9-convoys` (unmerged) | PASSED (logic + scenario written) | PENDING | PENDING | PENDING | n/a | PENDING (heavy transport reads heavy; amber strobes) | PENDING (3 NPC vehicles + 0.1 s tick) | `GLASSHOUSE_ENGINE_CONVOY_MOVE` > 8 studs, convoy reaches its end landmark |
| Convoy: breach refused while moving, forged trigger ignored, server-timed breach, crates minted once, second breach refused, one crate paid once | m9 | PASSED (logic) | PENDING | PENDING | PENDING | PENDING (payout through the job path) | PENDING | n/a | `GLASSHOUSE_ENGINE_CONVOY_SUCCESS` |
| Convoy: ramming damage and cripple at half health, blocking patience/back-out, escorts' sight raising alert and heat, police dispatch via heat, doors sealing after an interrupted hold | m9 | code-reviewed | PENDING | PENDING | PENDING | n/a | PENDING | n/a | strobes on, "called the police", cruisers arrive |
| Convoy: blackout interaction (6 s breach, reduced escort sight), cleanup on expiry/cancel/shutdown, late joiner sees the banner, crew switch while carrying a crate, arrest drops a crate | m8+m9 | PASSED (logic for the factor) | PENDING | PENDING | PENDING | n/a | PENDING | n/a | banner shows the convoy for a joiner; no vehicles or crates left after the event |
| Touch and controller: all prompts, holds, board, keypad | all | bindings exist | PENDING (device) | n/a | n/a | n/a | PENDING | n/a | every hold completes on touch |
| Performance tiers (desktop 60, mid mobile 30) | all | not measured | PENDING | PENDING | PENDING | n/a | n/a | PENDING | MicroProfiler frame times recorded |
| Persistence after a failed load (never overwrite with defaults) | dev | logic-tested | PENDING | n/a | n/a | PENDING | n/a | n/a | "NOT SAVING" note, data intact after rejoin |

Merge order once verified: `claude/review-m6-decoys` → `claude/review-m7-bounties` → `claude/review-m8-blackouts` → `claude/review-m9-convoys` (each fast-forwards onto the previous).
