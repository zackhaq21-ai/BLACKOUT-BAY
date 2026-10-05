# GLASSHOUSE — Design Record

Working title: **GLASSHOUSE**. Creative promise: build a fortune in a city where everyone can see what you have, and someone you trust may help them take it.

This file records decisions, labelled assumptions and the system shapes. Detailed progress lives in `docs/STATUS.md`, not here.

## Decision order used
1. Owner's explicit decisions and corrections.
2. Confirmed requirements in the build brief (five pillars, approved features, canceled items).
3. Existing implementation that satisfies those requirements (none existed: the repository was empty).
4. Clearly labelled, reversible assumptions (marked **ASSUMPTION** below).

## Pillars → systems
| Pillar | Where it lives |
|---|---|
| Agency | Three entries (front / dock / roof), two vault methods (dual swipe / drill), any exit, route choice on the island. |
| Consequences | Security levels (Quiet → Suspicious → Alert → Lockdown) change available exits; police heat follows you and your car; dropped bags can be taken by anyone. |
| Cooperation | Dual keycard swipe opens the vault instantly; one carries, one drives, one cuts power; cell release in the police lobby. |
| Betrayal | Physical bags: anyone can pick up a drop or raid an open trunk; leaving a crew keeps what you carry; a leader can cut a member from the split by kicking them. Every such act is logged with a landmark. |
| Mastery | Guard patrol timing (office guard leaves for ~45 s per loop), camera sweeps, the dock code on the office board, pickpocketing from behind, lockdown timing, the power-cut window, road knowledge. |

## The island (compact first footprint)
1240 × 1000 studs, generated from `src/shared/MapBlueprint.luau` at server start. Key places: Aurora Exchange (museum, north-centre), Aurora Plaza (front), Parking Deck (east, roof gantry to the museum roof), Canal Lane and the Cut (quiet pedestrian route west), Seawall Overpass (fast, exposed), Lantern Cross (memorable intersection; police barricade point), Harbour Piers A–F (hideouts, south-west), Police Station + jail (south-east), Lighthouse Point (landmark). `tools/map_preview.py` renders it.

**ASSUMPTION — one shared museum, no instancing.** Security and loot are world state; several crews can be inside at once and race for the same cases. This produced rivalry for free and kept the server simple. Reversible: a per-crew lockout is a small change in `SecurityService`.

## First heist: the Aurora Exchange
Sequence: board → approach → entry → cases/vault → escalation → carry out → getaway → delivery table → payout → board again.

- **Front**: smash the glass (3 s). Instant Alert, heat for the smasher. Cars wait on the Boulevard. Lockdown drops the shutter 25 s after Alert.
- **Service**: dock keypad (4-digit code shown on the security office board; the office guard patrols out for ~45 s of a ~60 s loop). Lane is bollarded: no cars until Market Street or Dockside.
- **Roof**: parking deck ramp → gantry → ladder → open skylight → mezzanine. Heavy loot cannot climb or jump; light bags can be thrown off the roof (drop) and collected below.
- **Vault**: two readers (any two keycard swipes within 4 s: office desk card + captain's pocket) or a 30 s drill (loud). Holds the Aurora Core (heavy, 7,500) and two cases.
- **Complications**: junction box in the alley cuts power 45 s (cameras dark, shutter lifted; 150 s cooldown). CCTV switch in the office kills cameras 90 s. Three wrong keypad codes trip a tamper alarm. Lockdown seals the dock keypad unless the power is cut.
- **Scaling**: one player can do everything (drill, one bag at a time, trunk for more). Larger crews gain the dual swipe, parallel case cutting, a driver who never leaves the car, and a power cutter. No inflated health bars anywhere.
- **Variation per restock**: which 6 of 8 public cases are stocked and with what, vault contents, the dock code, keycards reset, guards reset. Patrol routes are fixed in this milestone (**ASSUMPTION**; randomising route sets is a data change).

## Failure changes the story
- Suspicious → guards investigate the last place they half-saw you; you can still leave.
- Alert → guards chase and detain (2.2 s within 6 studs), everyone inside gets police heat, the alarm is visible across the plaza.
- Lockdown → front shutter down and dock sealed: roof or power cut.
- Disabled getaway (rammed to 0 health) → trunk spills onto the road.
- Arrest → bags drop where you stood; jail with three exits: lockpick (25 s), auto-release (90 s), or a crewmate's lobby switch (the desk sergeant notices: +60 heat).
- Crew member leaves mid-job → forfeits their share; whatever they carry leaves with them; logged.
- Job close: auto when all touched loot is delivered or lost (25 s grace for another trip), when every present member is arrested, when the crew disbands, after the 15-minute window, or manually from the board. Retry: walk to the board, press start.

## Physical loot and trust
`LootLedger` (pure, tested) is the single identity: InCase → Carried → Dropped / InVehicle → Delivered (once) / Destroyed. The server renders each state; value is credited exactly once on delivery. Hands hold one bag; trunks hold 2 (Kestrel), 5 (Courier), 1 (Commuter). Anyone can raid an open trunk or a drop.

Payout: the leader sets integer-percent shares before the job (equal by default); shares freeze at start; delivered value is split by `SplitLedger` among members still in the crew; leavers forfeit; rounding goes to the last deliverer. The results screen separates agreed split, delivered value, each payout, and the event log (who took what, where).

**Decoys / split loot**: real loot can be divided between vehicles today (two trunks). Fake bags and decoy vehicles are not implemented yet (see STATUS).

## Hideouts: stash, defences, raids (milestone 3, rule revised in the reconciliation review)
**Owner decision (2026-10-04): high stakes.** A cracked safe exposes the **entire earned stash**: no protected floor, no fraction, no per-raid cap. This replaces the earlier labelled assumption (floor 1,000 / 35% / 15,000 cap), which has been removed from the code. It applies to the earned stash only: permanent Robux cosmetics, paid entitlements, XP and earned unlocks are never touched by a raid, and nothing else in the profile is deleted.

- **Where money lives.** Job payouts land in the owner's hideout **stash** (`PayoutsToStash = true`). Nameplates, the stash sign, the HUD ("AT RISK") and the Hideout tab all say the whole stash is on the table.
- **Protected progression.** Banking moves stash to the raid-proof wallet for a 10% fee with a 2-minute cooldown (`BankingEnabled`, a separate switch the owner can turn off). Rebuilding otherwise happens through jobs.
- **Six tiers** (1,500 → 18,000): lock, alarm, bay shield + breaker, laser traps, reinforced shield (pier door barred), sweeping lasers (a trip also locks the safe 20 s). Each tier changes the attacker's problem without making entry impossible. Low lasers are jumped, high ones walked under.
- **Raidable while offline.** Records live in their own DataStore so a raider on any server can act on an offline owner's record. Online crew leaders are raided at their own pier; everyone else at the Breakwater Lockup.
- **Concurrency and no duplication.** Every mutation is a pure `HideoutRecord` transform applied inside `UpdateAsync` on the stored value: exclusive raid lock (7-minute expiry, 10-minute cooldown after a raid), **one crack per lock** (retained bags cannot be re-stolen in the same raid), atomic debit of the stored stash, retention, release + report. Stolen value is minted once as ledger bundles; a bundle is delivered once. All of it is unit-tested without Roblox.
- **Raid report** on return: who (and crew size), when, how entry happened, which defences triggered, lost vs. retained, and a 20-minute recovery window kept for the later stolen-loot recovery mission.
- **Defender play.** Live alarm and raid HUD, picking bags back up, 8-second retention into the safe, police heat for raiders. No player combat yet.
- **Remaining assumptions.** Retention of *any* bag left inside; raids only target crew leaders' live units; one lockup raid at a time per server.

## Stolen-loot recovery (milestone 5 item, implemented)
Raiders leave clues; the victim gets a time-limited chance to get the **same** loot back. Nothing is minted twice and nothing can be claimed twice.

- **Clue trail.** Every bundle minted by a raid carries the origin `raid:<raidId>` and the label "Stash of <victim>". Each pickup, drop, stow, delivery or absorption of such a bundle writes a clue (landmark + time) onto the victim's report and toasts the victim if online. The report is opened provisionally when the raid starts so no clue is lost, and finalized in place when the raid ends.
- **Physical intercept.** While bundles are still physical, anyone can take them (existing pickup rules). If the victim's crew (led by the victim) delivers one, the report's `recovered` rises by that bundle's value. The bundle id is the same object that was stolen.
- **Recovery mission.** From the Hideout tab, a report with an open window (20 min) and value still owed offers "Recover". It starts a raid variant against the raider's hideout (their live pier, or the Breakwater Lockup) under the same exclusive lock, with their defences and the police as counterplay. The crack takes `min(owed, raider's stash)` and never more than this raid already took from that raider (`recoveries[raidId]` on the raider's record), so a lost or re-stolen recovery bundle cannot be re-debited. Recovered value is minted as bundles labelled with the victim's name and must be carried home; the victim is credited only on delivery.
- **No chains.** A recovery mission's own report carries no recovery window, so a raider cannot "recover" a recovery. One crack per lock still applies.
- **Assumptions.** Recovery credit requires the victim to lead the delivering crew; the window and clue cap are configurable (`RecoveryWindowSeconds`, `MaxClues`); if the raider's stash is already below what they took, the victim gets what exists.

## Getaway deception: fake bags and decoy vehicles (approved tactics, implemented)
- **Fake bags** are packed at the crew's own job board for 150 from the leader's stash, at most three out per crew. A fake mimics a chosen kind (Trinket, Relic, Jewel, Core, or a "Stash of <you>" bundle): same visual, same label on nameplates and tags, a plausible shown value. It has its own ledger id and is never real loot: worth 0 on delivery, never counted as a job's loot, cleared when the crew's job closes.
- **Reading the situation.** Fakes are always light, so someone sprinting with a "Core" is lying. Anyone outside the crew who picks a fake up learns it is fake immediately (the label flips to "Fake bag"), so a rival's interception costs them a grab and a chase. Police heat for being seen carrying still applies to the decoy carrier: misdirection has a price.
- **Decoy vehicles** need no new mechanic: roll out a second car, put a fake in its trunk, and send it the exposed way. Cruisers chase recognised vehicles and wanted drivers, so a wanted decoy driver pulls pursuit; real loot is split between trunks (bundles and bags keep their individual ids as they move between containers).
- **Assumptions.** Cost, cap and mimic list are configurable in `Config.Decoys`; a fake "Stash of" bundle carries the crafter's name, not a victim's, so it cannot forge a recovery clue (clues only follow `raid:` origins).

## Bounties (implemented)
- **Funding.** A player puts earned stash on anyone outside their crew (100 to 1,000,000). The contributor's stash is debited first; the bounty is then credited on the **target's hideout record**, so it persists across servers and while the target is offline, and contributions from several players stack (2m + 2m = 4m). If the credit fails the contributor is refunded. Never real money.
- **Who is wanted.** Nameplates show "BOUNTY n", the Wanted tab lists everyone on the server with their bounty, the target is told the amount, and a server-wide notice names them.
- **Claiming.** A hunter holds "Take down" on the target for 2 seconds within 7 studs (the one authoritative value: server check, prompt range, UI and tests) while the target is **on foot** (vehicles are safe; crews are cover). The claim is one atomic transform on the target's record: the second of two simultaneous hunters gets "no bounty". The target is down for 4 seconds and drops their bag; the hunter's stash receives the full pool once. Refused: the target themself, any contributor, crewmates of the target, and any claim within 5 minutes of the last payout on that target (farming). Disconnects change nothing: the bounty stays on the record.
- **Reputation.** A raid report offers "Put 500 on <raider>" so victims can turn a loss into pursuit. NPC police arrests do not pay bounties and do not clear them.
- **Assumptions.** Amount bounds, hold time, range, stun and cooldown live in `Config.Bounty`; collusion handling is the rule set above (no related-account review yet).

## Blackouts (implemented, review branch `claude/review-m8-blackouts`)
A crew **on an active job** can cut the harbour grid at the **Harbour Substation** in the crane yard (6-second hold, loud). For 75 s: street lamps, lit windows, neon signs and pier lamps go dark; the sky drops to moonlight (never black); battery **emergency lamps** come on along the streets, at the museum, the piers, the plaza and the station; the museum's cameras die and its lockdown shutter lifts; **every pier shield drops and lasers lose power**; guards see 55% and cruisers 60% of their normal range and cannot read new plates. The lighthouse and the police station keep their own power.

- **Cost and risk.** The saboteur takes +60 heat (wanted), everyone on the server is told the grid is down, and the crew log records who did it.
- **Counterplay.** Anyone on foot can hold **Reset the grid** (8 s) at the same cabinet; a reset also starts the cooldown.
- **Bounds.** One blackout at a time per server, duration and cooldown (300 s) are clamped by `BlackoutRules.definition`; `WorldEventRules` (pure, tested) owns start/expiry/cooldown. Restoration is idempotent and runs on expiry, reset, and (through the same handler) on any early stop.
- **Authority.** Eligibility (alive, on foot, not jailed, crew job active, cooldown) is evaluated on the server at hold start, every hold tick and at completion; the hold is timed on the server; a forged `PromptTriggered` does nothing. The client only receives `WorldEvent` state (id, label, endsAt on the server clock) and draws a banner; late joiners get it from the bootstrap.
- **Framework.** `WorldEventService` is a small registry (one instance per id, bounded duration, cooldown, handlers, replication) so armored convoys and later events plug in without new plumbing.

## Armored convoys (implemented, review branch `claude/review-m9-convoys`)
A Harbour Security convoy (escort, armored transport, escort) crosses the island on one of four road routes, chosen server-side away from players and never the same route twice running. Flow: **anticipation** (announced 40 s ahead with origin and destination) → **tracking** (banner with the nearest landmark, two planned 18-second security-check halts per route) → **interception** (block the road, ram the transport, or wait for a halt and breach the rear doors with a 10-second server-timed hold) → **escalation** (escorts that *see* a threat go alert, then engaged: strobes, faster, checkpoints skipped, police called through heat, doors sealing after an interrupted breach, the transport crippled at half health) → **extraction** (three server-valued crates, 2,000 each, minted once as ledger items at the doors; they are ordinary loot: carry, stow, steal, drop; delivering at your pier pays through the normal job path) → **escape** (anyone an escort can see gathers heat while engaged; loose crates untouched for 150 s go back to Harbour Security) → **cooldown** (one convoy per server, 420 s bound, 900 s cooldown, next one auto-scheduled with jitter).

- **Roles emerge, none forced.** A blocker in a car, an interceptor at the doors, a lookout watching the escorts' sight lines, carriers, an escape driver with a trunk.
- **Blackout interaction.** During a blackout the doors' electronic lock is dead (breach 6 s instead of 10) and escorts see 60% as far (the same police vision scale). Nothing requires a blackout and the convoy still halts and seals as usual.
- **Authority.** Route, spawn frames, driving, perception, escalation, cargo values and the one secured→minted transition all live on the server (`ConvoyRules` is pure and tested). Clients get `ConvoyState` (phase, landmark, cargo state, crate count, alert) and the shared event banner. Convoy seats are disabled; a forged `PromptTriggered` does nothing without the server's own hold timer.
- **Cleanup.** Expiry, delivery, extraction, cancel and shutdown run one idempotent teardown: vehicles destroyed, loose crates recovered, carried crates left in play, state replicated as inactive.
- **Open tuning.** Checkpoint windows, crate values and the heat numbers are provisional until Studio play.

## Presentation layer (premium polish pass, review branch `claude/review-m10-polish`)
Gameplay authority did not move. The client gained a presentation layer that reads replicated state and never writes it: `CameraController` (FOV by state, landing dip), `MovementController` (landing and sprint cues), `EnvironmentController` (weather look, blackout moonlight, lightning, rain, wet roads, graphics tiers), `Vfx` (pooled bursts), `AudioController` (groups, positional cues, beds, interior mix), and a refit `VehicleController` on shared `VehicleFeel` maths also used by the NPC drivers. The server gained `EnvironmentService` (weather state, replicated; NPC vision factor composed with the blackout's) and visible vehicle light states. Pure maths for all of it lives in `Core/` with tests. Rules: no shake, no strobe, no black frames, no permanent markers, one source for every constant (`Config.Presentation`, `Config.Vehicles.WheelRadius`).

## Corrections carried over from the prototype thread (docs/ROADMAP.md in `prototype/aurora-v0`)
- The rare car is owned by the **individual thief**, never automatically by the assisting crew; ownership survives crew changes for the rest of the weekly cycle. `RareCarCycle` already models the individual owner.
- A crew member may **leak a hideout**, enabling stash raids and a comeback. (The raid board currently lists hideouts by visible wealth; leaking as a deliberate act is a later milestone.)
- Blackouts need a server-bounded duration and cooldown; restore every affected system after host disconnect or restart. (Done: see Blackouts above; a server restart rebuilds the world with the grid up.)
- Recovery must transfer the **same** loot, never mint another copy. The bundle ids minted in a raid are the ids a recovery would move.
- NPC police must not track omnisciently; solo must always keep an achievable escape. Human police switch-over must be safe.
- Deferred, per the owner: cargo-ship heists, framing rivals, forced loot-vs-teammate choice. Canceled: the weekly rare gun.
- Open decisions still owed: weekly boundary/timezone and persistent server-world routing for the rare car; NPC difficulty selection method.

## Police (NPC fallback this milestone)
- Heat per player (0–300; levels 1–3) from the alarm (120), smashing doors, being seen carrying loot (60/10 s), being rammed (40). Decays 2.5/s only after 20 s unseen. Vehicles seen with a wanted driver are recognised for 90 s.
- 10 cruisers parked at the station. After the response delay (14 s Medium / 8 s Hard) up to 3 (Medium) / 5 (Hard) go active, drive the road graph toward the wanted, ram cars (25 damage), cuff on foot (2.5 s stopped within 9 studs; broken by moving 14 studs away). At heat level 2 two cruisers block Lantern Cross.
- **ASSUMPTION — NPC difficulty selection**: fixed `Config.Police.NpcDifficulty = "Medium"`; `"Hard"` is a table swap. The brief leaves the selection method unresolved.
- Player police faction, helicopter, balanced loadout: not in this milestone.

## Persistence
`DataService`: DataStore `GlasshouseProfiles`, keys prefixed `dev/` (separate dev data), UpdateAsync session lock (150 s stale timeout), 3 load retries, read-only mode when another server holds the lock, in-memory mode when the DataStore is unavailable. A profile that failed to load is never saved. Autosave every 120 s; save on leave and on close. Cosmetics live in the profile as a separate table (no cosmetics are sold yet; purchases stay disabled).

## Rare car persistence (open decision, logic implemented)
`RareCarCycle` (pure, tested) implements the per-server weekly rules: one car, heist once per week, 120 s break-in that cancels on interruption and never banks progress, transfers that neither duplicate the car nor reopen the heist, and a weekly reset that returns it. **Not integrated** into the world yet. Open decision for the owner: Roblox servers are not durable, so "per-server" ownership cannot survive a restart without a persisted identity. Options: (a) owner-profile flag keyed by week number (ownership follows the thief across servers: becomes one car per owner, not per server), (b) a shared week record (becomes global rarity), (c) accept that a restart returns the car to the heist site. None was chosen; the brief forbids silently converting to global rarity or permanent ownership, so this stays explicit.

## Deferred / excluded by the brief
Cargo-ship heists, framing rivals, forced loot-vs-teammate choice, the rare weekly gun (canceled), real-money bounty funding, pay-to-win of any kind, live purchases (require separate authorisation).
