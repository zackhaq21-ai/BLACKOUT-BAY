# Test Results — milestone `m2-first-heist` (2026-10-04)

Verification levels: **SOURCE IMPLEMENTED** → **AUTOMATED CHECKS PASSED** → **STUDIO PLAYTESTED** → **LIVE VERIFIED**.

This environment has no Roblox Studio and no Roblox network access. Everything below the "automated" line is **not** verified.

## Automated checks (passed)
| Check | Result |
|---|---|
| `luau-lsp analyze` against Roblox API definitions, whole `src/` | 0 errors |
| Selene lint (`roblox.yml` globals, Luau mode) | 0 errors, 0 warnings |
| Logic tests via the Luau CLI (`tools/run-tests.luau`) | 42 passed, 0 failed |
| `rojo build` → `build/Glasshouse.rbxl` | built (130 KB) |
| Map invariants (roads on-island and axis aligned; buildings never overlap roads, reserved zones or each other; 6 spaced hideouts; one connected drivable road network; pedestrian lanes excluded from driving) | passed |

Logic tests cover: loot identity and one-time delivery, hands-full and trunk capacity, trunk spills, arrest drops; payout split validation, forfeits and rounding; job phases, auto-close reasons, bounded log, "Busted/Clean/Loud/Empty" headlines; security escalation, sneaking rate, decay, lockdown timing, calm-down, camera/power windows; police heat levels, decay-only-when-unseen, vehicle recognition expiry; rate limiting; rare-car weekly cycle, 120 s break-in interruption, repeated steal-backs, weekly reset; bounty stacking, single payout, self/contributor/crewmate/cooldown rejection, refunds; road graph connectivity.

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
| Stacked bounties, one payout | Logic-tested; **not integrated** into the world |
| Concurrent access to an offline stash | **Not implemented** (raids are a later milestone) |
| Human police arriving during NPC fallback | **Not implemented** (no human police faction yet) |
| Interrupted rare-car theft, repeated transfers, weekly reset | Logic-tested; **not integrated** |
| Saving and rejoining | SOURCE IMPLEMENTED (session lock, never-overwrite-on-failure), not verified against a live DataStore |
| Cosmetic ownership surviving defeat | Profile field exists; no cosmetics exist yet |
| Touch and controller completion | Bindings and touch buttons implemented; not device-tested |
| Performance (30 FPS midrange mobile, 60 FPS desktop) | **Not measured**. Part budget: roughly 2,000–2,500 generated parts, ~60 point/spot lights, 14 NPCs, 15 constraint vehicles. |

## Known risks to check first in Studio
1. Constraint car feel (wheel friction, steering lock, flip-over) in `VehicleBuilder` / `VehicleController`.
2. NPC rigs: `Players:CreateHumanoidModelFromDescription` may fail offline; the block-rig fallback has no walk animation either way.
3. Navmesh for guard chases on the generated museum (PathfindingService on runtime-built parts).
4. `SetNetworkOwner` on driven cars is wrapped in `pcall`; verify ownership transfers on seat/unseat.
5. Dropped bags near walls (spawned 2.5 studs ahead of the player) could clip; a 8 s underground recovery exists.
