# Studio verification and human playtest checklist

Automated native Studio scenarios now cover quiet/forced extraction, car input,
capture/recovery/retry and multiplayer joins/disconnects. Exact completed crew counts
and results are recorded in VERIFICATION.md and dist/engine-multiplayer-results.txt.
Those scripts position characters and freeze patrols to isolate rules. The following
human navigation, difficulty, device and visual checks still need observation.

Use the native place in Studio. Record date, device, crew size, result, Output errors
and observed blockers for each case. Passing logic tests does not replace these tests.
Keep DataStoreEnabled and CommerceEnabled false. Do not publish or activate purchases.

| Check | Method | Expected |
|---|---|---|
| First spawn | Open file, Play | Island/HUD appear, Start run clickable, no Output errors |
| Solo quiet | One client; signals, grid, quiet vault, core, tunnel | Complete entirely alone |
| Solo forced | New run; force vault before signals | Heat +65, core available, tunnel viable |
| Curator release | Release and use canal | Heat reduced, canal available |
| Curator capture | Capture, then release | One signal only, heat consequence, later canal |
| Stealth | Walk into red patrol cone, hide behind cover | Exposure accumulates/decays, cover blocks sight |
| Stasis | Approach drone; use prompt | Server channel, 12s freeze, charge decrements once |
| Capture | Stay exposed; carry core/bonus | Recovery pad; bonus lost; core at clear gallery point |
| Recovery | Use coral pad alone | Re-enter free, mission timer -15 seconds |
| Failure | Let timer reach zero | Results, free retry after 5s, clean next run |
| Five players | Local Server & Clients = 5 | Ready/start works, four signals, distinct role labels |
| 2/3/4 players | Repeat local test at each count | Required counts 2/3/3, complete |
| Late join | Add client during Active | Next-crew state, cannot alter active mission |
| Carrier leaves | Disconnect carrier atop an exhibit | Core at clear recovery point; crew continues |
| Leader leaves | Disconnect leader | Host/roles reassigned; retry remains possible |
| Four leave | Five-member run reduces to one | Requirement drops to two; last player finishes |
| Everyone leaves | Empty active server | Run abandoned; no ghost rewards |
| Duplicate interactions | Two clients sync same node/take core | One signal/one carrier |
| Paid preview | Click unowned preview cosmetic | No Roblox purchase dialog |
| Earned unlock | Several wins; equip amber | Looks change, stats/objectives unchanged |
| Free retry ownership | Fail after earned unlock | Owned cosmetics retained during session |
| Car | Driver + four passengers; WASD then jump out | Steering works, seats secure, all can dismount |
| Three escapes | Drive/walk coast to tram/canal/tunnel | Navigation possible, extraction prompt works |
| Car recovery | Drive off island | Car respawns; no stranded/duplicated core |
| Phone layout | Studio device emulator, landscape + portrait | Readable text, tap targets, no critical overlap |
| Controller | Controller emulator/device | Prompts X/Y and GUI selection work |
| Exploit simulation | Fire invalid command/value; spam; distant prompts | No state/reward mutation |
| Retry cleanup | Ten retries | No extra guards/cars/prompts, memory stable |

A real-device and latency playtest is required before online testing. Observe seat input
replication, vehicle network ownership, touch driving, root-position tolerance and respawn
timing closely. Automated car movement does not establish smooth handling. Walking is
always available, so the heist never requires driving to reach a valid exit.

## Save/commerce testing, only after separate activation authorization

Use a separate private test experience/store namespace, never production data. Test
load failure without overwrite, UpdateAsync retry, two concurrent updates, reconnect,
shutdown during in-flight save, already-owned pass, duplicate receipt, receipt write
failure then retry, unknown product, absent player, and confirmed ownership reconciliation.
Never use a real purchase merely to test this local prototype.
