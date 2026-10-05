# Studio QA master run

One run covers the whole review stack. Nothing here has been executed yet: **every result below is PENDING** until this is run on a machine with Roblox Studio.

## 1. Automated master scenario (objective checks)

Infrastructure (existing): `tools\verify-engine.ps1 -Players 1,3,5` → run-in-roblox → `build/BlackoutBay-EngineTest.rbxl` → `tests/engine/driver.server.luau` under StudioTestService (1 client in play mode, 3 and 5 clients as real multiplayer tests). Evidence is written to `build/engine-results.txt` (every `GLASSHOUSE_*` line from all counts) and per count to `build/engine-<n>-results.txt`.

The scenario is split into independent **sections**, each tagged with a **system**. A failing section prints exactly one line and the run continues; a later section that depends on it prints a SKIP instead of a false failure.

```
GLASSHOUSE_ENGINE_FAIL system=<SYSTEM> test=<TEST> expected=<EXPECTED> actual=<ACTUAL>
GLASSHOUSE_ENGINE_SKIP <system> <section> dependency <failed section>
GLASSHOUSE_ENGINE_SUMMARY count=<n> passed=<a> failed=<b> skipped=<c>
GLASSHOUSE_ENGINE_RUN_PASSED <n>   |   GLASSHOUSE_ENGINE_RUN_FAILED <n> failed=<b> skipped=<c>
GLASSHOUSE_ENGINE_ALL_PASSED       (runner: every requested player count passed)
```

| Section | System | Players | Depends on | Success marker | What it proves |
|---|---|---|---|---|---|
| setup | setup | 1/3/5 | — | — | hook, control remote, profiles and crews ready |
| crew | crew | 1/3/5 | setup | — | join by code, crew size, hideout unit |
| startJob | heist | 1/3/5 | crew | — | job starts, guards frozen, baseline PERF sample |
| frontSmash | heist | 1/3/5 | startJob | — | alarm to Alert, smasher heat |
| caseCut | heist | 1/3/5 | startJob | — | case cut exposes loot, pick-up |
| drive | vehicles | 1/3/5 | caseCut | `GLASSHOUSE_ENGINE_CAR` | real client throttle moves the car > 20 studs; headlights on while driven; client dismount |
| trunk | heist | 1/3/5 | drive | — | stow and take |
| blackout | blackout | 1/3/5 | startJob | `GLASSHOUSE_ENGINE_BLACKOUT_SUCCESS` | forged trigger ignored; server-timed cut; lights dark, emergency lamps on; guard 55% / cop 60% vision; cameras dead; shields down; heat; second cut refused; reset restores everything; cooldown |
| weather | weather | 1/3/5 | setup | `GLASSHOUSE_ENGINE_WEATHER_SUCCESS` | Rain/Storm/Fog set and replicated; NPC vision factors 0.85/0.7/0.6; restored on Clear; PERF samples in rain and storm |
| deliver | heist | 1/3/5 | trunk | `GLASSHOUSE_ENGINE_HEIST_SUCCESS` | payout to stash, XP and win, free retry |
| fake | decoys | 1/3/5 | deliver | `GLASSHOUSE_ENGINE_FAKE_OK` | fake carried as a Jewel, worth nothing, never counted |
| jail | police | 1/3/5 | crew | — | arrest and release |
| convoy | convoy | 1/3/5 | crew | `GLASSHOUSE_ENGINE_CONVOY_MOVE`, `GLASSHOUSE_ENGINE_CONVOY_SUCCESS` | three vehicles move; breach refused while moving; forged trigger ignored; server-timed breach mints exactly the configured crates once; heat; one crate extracted and paid once across the crew; cleanup recovers loose crates and removes vehicles; cooldown; PERF sample |
| raid | raids | 3/5 | deliver | `GLASSHOUSE_ENGINE_RAID_SUCCESS` | full exposure, bundles delivered once, report, cooldown |
| recovery | raids | 3/5 | raid | `GLASSHOUSE_ENGINE_RECOVERY_SUCCESS` | exactly the stolen amount back, raider debited exactly, one claim chain |
| bounty | bounties | 3/5 | raid | `GLASSHOUSE_ENGINE_BOUNTY_SUCCESS` | prompt range = `Config.Bounty.TakedownRange`; contributor, forged trigger and out-of-range refused; hunter paid exactly once |
| torture | cross | 3/5 | blackout, convoy, bounty | `GLASSHOUSE_ENGINE_TORTURE_SUCCESS` | see §4 |
| tiers | performance | 1/3/5 | setup | `GLASSHOUSE_ENGINE_TIERS_SUCCESS` | Low/Medium/High/Max switch acknowledged by the client; PERF sample per tier |
| disconnect | crew | 3/5 | raid | `GLASSHOUSE_ENGINE_DISCONNECT_OK` | a leaving carrier drops the bag |

Notes: the torture section may wait out the blackout (300 s) and convoy (900 s) cooldowns left by the earlier sections; the whole 3- and 5-player runs can therefore take up to ~20 minutes. The runner continues past a failing count and reports all failures at the end.

## 2. Performance capture (objective, printed by the scenario)

`GLASSHOUSE_ENGINE_PERF phase=<p> tier=<t> players=<n> client=<name> fps= worstFrameMs= clientMemMb= sounds= emitters= fov= serverMemMb= instances= moving= physicsMs= heartbeatMs= sendKbps= recvKbps= worldParts= litLights= activeEmitters=`

Phases sampled: `normal` (per tier Low/Medium/High/Max on the leader, and once at default), `blackout`, `rain`, `storm`, `convoy`, `convoy+blackout` (3+ players), `after-torture`. Police activity is covered indirectly (heat is live during blackout and convoy phases). Each client reports its own render frame rate over two seconds, its worst frame, memory, playing sounds and enabled emitters; the server reports Stats memory, instance and moving-primitive counts, physics and heartbeat milliseconds, network kbps, world part count, lit lights and active emitters. Copy the lines into this table after the run:

| Phase | Tier | Players | FPS (min client) | Worst frame ms | Client MB | Server MB | Instances | Moving | Physics ms | Heartbeat ms | Send/Recv kbps | Lit lights | Emitters |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| normal | Low / Medium / High / Max | 1, 3, 5 | PENDING | | | | | | | | | | |
| blackout | default | 1, 3, 5 | PENDING | | | | | | | | | | |
| rain / storm | default | 1, 3, 5 | PENDING | | | | | | | | | | |
| convoy | default | 1, 3, 5 | PENDING | | | | | | | | | | |
| convoy+blackout | default | 3, 5 | PENDING | | | | | | | | | | |
| after-torture (leftovers) | default | 3, 5 | PENDING | | | | | | | | | | |

Not captured by the scenario (use the MicroProfiler / Developer Console by hand during the visual pass): script activity per script, physics cost breakdown, texture memory. **PERFORMANCE = UNVERIFIED until measured.**

## 3. Human visual checklist (PASS / TUNE / FAIL)

Run `build/BlackoutBay.rbxl` (Test → Clients and Servers, 1 then 3 then 5) and judge each line. Record the decision and a one-line note; "TUNE" means the system works but a number should change (see `Config.Presentation`, `Config.Vehicles`, `Config.WorldEvents`).

| Area | Check | Decision | Note |
|---|---|---|---|
| MOVEMENT | responsive; not slippery | PENDING | |
| MOVEMENT | sprint feels faster without excessive FOV (70 → 76) | PENDING | |
| MOVEMENT | landing has weight; camera dip not annoying (≤ 1.6 studs, hard landings only) | PENDING | |
| MOVEMENT | carrying loot still feels usable (heavy: 11 studs/s, no jump/climb) | PENDING | |
| CAMERA | smooth; no nausea over a 5-minute session | PENDING | |
| CAMERA | no clipping (default collision intact), interiors usable | PENDING | |
| CAMERA | vehicle camera readable; FOV only widens above a third of top speed | PENDING | |
| CAMERA | FOV changes subtle (bounds 55–85) | PENDING | |
| ANIMATION | no obvious foot sliding at 9 / 16 / 21 studs/s | PENDING | |
| ANIMATION | no snapping into or out of seats | PENDING | |
| ANIMATION | carrying / downed transitions acceptable with the default set | PENDING | |
| VEHICLES | Kestrel responsive; Courier/Commuter softer | PENDING | |
| VEHICLES | cruiser controlled, not an arcade toy | PENDING | |
| VEHICLES | armored transport feels heavy (slow hands, less lock) | PENDING | |
| VEHICLES | brake-then-reverse transition natural | PENDING | |
| VEHICLES | high-speed steering not twitchy | PENDING | |
| VEHICLES | no physics instability (flip, jitter, wheel pop) | PENDING | |
| LIGHTING | readable at 19.6 h; interiors readable | PENDING | |
| LIGHTING | materials believable (Limestone / Concrete / Brick / CorrodedMetal / Glass) | PENDING | |
| LIGHTING | no excessive bloom, no crushed blacks, no blown highlights | PENDING | |
| WEATHER | transitions smooth (25 s) | PENDING | |
| WEATHER | rain convincing; fog playable (view ≥ 260 studs) | PENDING | |
| WEATHER | storm atmospheric; lightning lights WORLD and CLOUDS, never a white screen | PENDING | |
| WEATHER | wet roads subtle (reflectance ≤ 0.14), not mirrors | PENDING | |
| BLACKOUT | dramatic yet playable; moonlit not black | PENDING | |
| BLACKOUT | emergency amber lamps useful for routes | PENDING | |
| BLACKOUT | lighthouse and police station visibly keep power | PENDING | |
| CONVOY | each of the four routes completes; formation believable | PENDING | |
| CONVOY | checkpoint halts read as security checks | PENDING | |
| CONVOY | vehicles do not constantly collide; back-out from obstruction acceptable | PENDING | |
| CONVOY | interception readable (strobes, "called the police", sealed doors) | PENDING | |
| VFX | useful, not spammy; no emitter left running after events | PENDING | |
| AUDIO (needs licensed ids) | positional falloff; no clipping; weather beds natural; engines readable; event cues appropriate | PENDING | |
| UI | clean, consistent, no overlaps at 1280×720 and 375×812 | PENDING | |
| UI | important info obvious; no permanent clutter; banner fades when idle | PENDING | |
| UI | Wanted / bounty / event information updates live | PENDING | |
| MOBILE | touch controls unobstructed (vehicle, hint and carry panels moved); RUN/SNEAK/DROP/LOG reachable | PENDING | |
| CONTROLLER | every heist action completable; board buttons selectable with feedback | PENDING | |
| NPC | sprinting past a guard inside raises the threat eye; sneaking does not | PENDING | |

## 4. Cross-system torture test (automated, 3+ players)

Sequence: crew on a job → bounty on the leader → blackout cut by the leader → convoy (route 2) starts inside the blackout → cargo breached by the hunter in under the normal 10 s (blackout factor) → hunter gains heat (police escalation through the existing dispatcher) → leader picks up a crate → hunter takes the leader down while carrying (crate drops, bounty paid exactly once) → blackout reset while the convoy is active (NPC vision and cameras restore) → convoy cancelled with loose crates (crates recovered, vehicles gone, both events inactive and replicated inactive) → cooldowns still refuse both events → total money across every stash unchanged (only the bounty transferred) → server and client emitter counts back to the pooled baseline. Disconnect is covered by the `disconnect` section; **reconnect/rejoin is not automatable in StudioTestService** and stays on the manual list: rejoin during a blackout and during a convoy and confirm the banner and lighting state arrive from the bootstrap.

Manual torture additions: two hunters finishing a takedown in the same second (one payout); a raid started during a blackout (shield already open) that outlasts it (shield stays down for that raid, raises again for others); DataStore: the same owner raided from two servers (one lock).

## 5. Where the other QA material lives
- Studio debt table (what is pending per branch): `docs/STUDIO_VERIFICATION_PENDING.md`
- Economy audit before merge: `docs/ECONOMY_AUDIT.md`
- Blank asset hooks inventory: `docs/ASSET_INVENTORY.md`
- Stack manifest and recovery: `docs/REVIEW_STACK.md`
- Hand-play walkthroughs: `docs/LAUNCH.md`
