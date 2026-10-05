# Test Results — review branch `claude/review-m8-blackouts` (2026-10-05)

Verification levels: **SOURCE IMPLEMENTED** → **AUTOMATED CHECKS PASSED** → **STUDIO PLAYTESTED** → **LIVE VERIFIED**.

This environment has no Roblox Studio and no Roblox network access. Everything below the "automated" line is **not** verified.

## Automated checks (passed)
| Check | Result |
|---|---|
| `luau-lsp analyze` against Roblox API definitions, `src/` and `tests/engine/` | 0 errors |
| Selene lint (`roblox.yml` globals, Luau mode) | 0 errors, 0 warnings |
| Logic tests via the Luau CLI (`tools/run-tests.luau`) | 65 passed, 0 failed |
| `rojo build` → `build/BlackoutBay.rbxl` and `build/BlackoutBay-EngineTest.rbxl` | built |
| Map invariants (roads on-island and axis aligned; buildings never overlap roads, reserved zones or each other; 6 spaced hideouts; one connected drivable road network; pedestrian lanes excluded from driving) | passed |

Logic tests cover: loot identity and one-time delivery, hands-full and trunk capacity, trunk spills, arrest drops; payout split validation, forfeits and rounding; job phases, auto-close reasons, bounded log, "Busted/Clean/Loud/Empty" headlines; security escalation, sneaking rate, decay, lockdown timing, calm-down, camera/power windows; police heat levels, decay-only-when-unseen, vehicle recognition expiry; rate limiting; rare-car weekly cycle, 120 s break-in interruption, repeated steal-backs, weekly reset; bounty stacking on a record, single payout, self/contributor/crewmate/cooldown rejection, refunds; road graph connectivity; stash exposure (floor, fraction, cap), bundle splitting, tier unlocks and crack/breaker times, bank fee; hideout record migration, deposit/upgrade/bank rules, the exclusive raid lock across servers and attackers (wrong holder cannot crack or release, expiry takeover, cooldown), owner blocked from banking/upgrading mid-raid, retention, report cap and unread count, minted bundles advancing a job; full-exposure raids (no floor/fraction/cap) and one crack per lock; profile ops (run credited once, receipt replay, pass idempotent, equip requires ownership); recovery (window, bounded by lost, lock-gated recover, one claim chain per raid, partial stash, clue cap, provisional report finalized in place); stash spend bounds and raid lock; world events (start, expiry, early stop, cooldown from either end, unknown ids); blackout eligibility (alive, jailed, seated, job required), reset open to anyone, clamped NPC vision scale, bounded duration/cooldown; the substation inside the crane yard and off roads.

## Native Studio scenarios (written, not yet run)
`tests/engine/driver.server.luau` runs under StudioTestService for 1, 2 or 5 local clients: crew join by code, start job, front smash → alarm + heat, case cut and take, real client car input (> 20 studs), trunk stow/take, delivery, job close with stash payout and XP, free retry, a fake bag minted, carried as a Jewel and delivered for nothing, arrest + release; a blackout (forged trigger ignored, server-timed cut, every grid light dark and emergency lamps on, cameras dead, guard/cop vision scaled, pier shields down, saboteur heat up, second cut refused, reset by another player restores everything, cooldown refuses a re-cut); with 2+ players: leave crew, raid the leader's live pier, server-timed crack, **full stash stolen**, every bundle picked up once and delivered, raid report with lost = stash, cooldown blocks a second raid, (3+ players) a bounty is funded by the raider and collected once by a third player who left the crew while the contributor is refused, the victim recovers exactly the stolen amount (raider debited exactly that, report credited, second recovery refused), carrier disconnect. Evidence is written to `build/engine-results.txt` by `tools/verify-engine.ps1`. The prototype's own evidence for its baseline is in `prototype/aurora-v0/dist/`.

## Required journeys — status
| Journey | Status |
|---|---|
| Complete solo heist, payout, second run | SOURCE IMPLEMENTED, not playtested |
| Complete five-player heist; intermediate crew sizes | SOURCE IMPLEMENTED (one code path for 1–5), not playtested |
| Player leaving during objective or escape | SOURCE IMPLEMENTED (forfeit + drop/keep rules), logic-tested in MissionFlow, not playtested |
| Multiple crews interacting | SOURCE IMPLEMENTED (shared museum, drops, trunks), not playtested |
| Mission failure then clean retry | SOURCE IMPLEMENTED, not playtested |
| Simultaneous claims on one bag | Ledger is single-threaded on the server: second pickUp fails ("not available"); logic-tested |
| Invalid / repeated / out-of-range requests | Rate limiter tested; distance validation implemented, not playtested |
| Stacked bounties, one payout | Logic-tested and integrated (record-held, takedown claim); engine scenario for 3+ players; not playtested |
| Concurrent access to an offline stash | Logic-tested (`hideout_record.spec`): one lock, atomic debit on the stored value, no cached writes. **Not verified against a live DataStore from two servers.** |
| Human police arriving during NPC fallback | **Not implemented** (no human police faction yet) |
| Interrupted rare-car theft, repeated transfers, weekly reset | Logic-tested; **not integrated** |
| Saving and rejoining | SOURCE IMPLEMENTED (session lock, never-overwrite-on-failure), not verified against a live DataStore |
| Cosmetic ownership surviving defeat and raids | Profile field exists and raids never touch profiles; no cosmetics exist yet |
| Hideout raid: entry, crack, bundles, retention, report | SOURCE IMPLEMENTED, not playtested |
| Blackout: eligibility, bounded duration, cooldown, effects, reset, reconnect banner | SOURCE IMPLEMENTED, logic-tested, engine scenario written; not playtested |
| Touch and controller completion | Bindings and touch buttons implemented; not device-tested |
| Performance (30 FPS midrange mobile, 60 FPS desktop) | **Not measured**. Part budget: roughly 2,000–2,500 generated parts, ~60 point/spot lights, 14 NPCs, 15 constraint vehicles. |

## Known risks to check first in Studio
1. Constraint car feel (wheel friction, steering lock, flip-over) in `VehicleBuilder` / `VehicleController`.
2. NPC rigs: `Players:CreateHumanoidModelFromDescription` may fail offline; the block-rig fallback has no walk animation either way.
3. Navmesh for guard chases on the generated museum (PathfindingService on runtime-built parts).
4. `SetNetworkOwner` on driven cars is wrapped in `pcall`; verify ownership transfers on seat/unseat.
5. Dropped bags near walls (spawned 2.5 studs ahead of the player) could clip; a 8 s underground recovery exists.
6. Laser beam heights (1.8 low / 6.4 high) against R15 jump height; `Touched` on anchored non-colliding beams.
7. OrderedDataStore index for the raid list and the per-join `GetAsync` budget with 12 players (about 24 reads/min plus writes on payouts).
