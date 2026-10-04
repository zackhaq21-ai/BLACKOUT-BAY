# Approved world vision and implementation boundary

This records Zack's latest corrections from the parent thread. It is not a claim that
these systems are implemented. The single-heist prototype is milestone one. The full
goal remains an original freely roaming island/coastal crime-and-police game with
concurrent crews, driveable links between different repeatable heists, betrayal and recovery.

## Confirmed requirements

- Crews support **1–5**. A whole shared server may eventually contain multiple crews and
  cops; the current five-player cap belongs only to the first prototype.
- Original geography, branding and assets. The referenced prison/heist game is inspiration,
  not permission to copy its map or models.
- Concurrent crews may wait outside another crew's heist and ambush the getaway for
  earned physical loot. Multiple exits and counterplay should prevent unavoidable camping;
  extraction is not guaranteed safe in the final shared world.
- Pre-agreed crew loot splits coexist with physical loot theft and betrayal.
- Player bounties use earned fictional currency only. Contributions from several players
  stack on the same target (2m + 2m = 4m), persist and grow until an eligible defeat/claim.
  Funds are debited into escrow, with exactly one authoritative claim.
- A defeated target's carried earned loot can be taken.
- A crew member may leak a hideout, enabling stash raids and a comeback/restart.
- **Offline hideouts remain raidable.** Do not substitute online-only protection.
  Earned shields/laser traps can defeat raiders and retain dropped earned loot.
  Returning owners see attacker/result logs. Plan **six defense levels** with counters
  to the strongest defenses. Paid strength is explicitly rejected.
- Accepted deception: decoy getaway cars, fake bags, splitting real loot across vehicles.
- Accepted blackout: crew-triggered district/city outage alters skyline, cameras,
  doors and objectives. Server-bounded duration/cooldown prevents permanent denial.
- Accepted recovery: raiders leave clues supporting a time-limited stolen-loot tracking/
  intercept mission. Recovery must transfer the same loot, never mint another copy.
- Accepted heat: escalating NPC pressure and vehicle recognition.
- Accepted moving armored-convoy heists.
- Exactly **one helicopter type, one plane type and one flying-bike type**. This is a
  type/model limit, not an agreed one-global-spawn restriction. No other aircraft types.
  Gameplay vehicles are earned; paid skins change appearance only.
- Rare car: fastest **car**, exactly **two seats**. Weekly **per-server car heist** awards
  this car instead of cash. Original heist completes once per week per server.
  The individual successful thief owns it, never automatically the assisting crew.
  Personal ownership survives crew changes for the rest of the current weekly cycle.
  Hideout theft takes **120 seconds** and transfers the same car to the individual thief.
  It can be repeatedly stolen/re-stolen during that week. Such theft does not reopen
  the original heist. At the weekly reset, revoke the holder, return/teleport the car
  to its original heist location, and reopen the heist. No accumulated permanent rare cars.
  Show the reset timer. No paid access or performance variant.
- Human police faction is primary: bounded loadout, patrol cars, existing helicopter type.
  Arrest leads to jail and teammate prison break. When there are **zero human cops**,
  approximately **ten NPC police** provide medium/hard fallback. NPC capture produces
  a harder escape mission than player arrest. Switch safely when human police joins.
  No omniscient NPC tracking. Solo must retain an achievable escape route.
- Robux cosmetics only: character, base, cars, guns, shields/lasers, hideout appearances.
  Equal gameplay stats/hitboxes and no hidden visibility advantage. Paid ownership
  stays permanent and raid-proof; free retries and earned essential tools.

## Explicit exclusions / corrections

- Rare weekly gun: canceled. Do not implement.
- Moving cargo-ship heist, planted evidence to frame rivals, new loot-versus-teammate
  extraction proposal: explicitly deferred. Do not add in this work.
- Tony Montana: request was for the user's separate dot avatar, **not this game**.
- No public release, live Robux products, paid integration, payment, or account upload.

## Milestones, with truthful status

| Milestone | Deliverable | Status |
|---|---|---|
| 1 | Native 1-5 museum heist, branching routes/heat, car, retry, cosmetic preview | Native place built; successful Studio extraction/driving; crew matrix in verification |
| 2 | Shared island server, multiple crews, earned physical loot ledger, splits/ambushes | Isolated loot/crew models tested; no live multiplayer-world adapter |
| 3 | Player cops, jail/solo escape/prison breaks, zero-cop NPC fallback, escalating heat | Isolated district model implemented; no physical police/prison gameplay |
| 4 | Persistent offline hideouts, six earned-defense tiers, raid logs, betrayals/recovery | Isolated raid/defense/loot model tested; no persistence or physical raid integration |
| 5 | Stacking escrow bounties, blackout/decoys, convoy heist | Isolated authority models tested; not connected to the playable map |
| 6 | One helicopter, one plane, one flying-bike; weekly rare-car cycle | Weekly ownership/theft model tested; aircraft and physical rare-car heist not built |
| 7 | Original production art/skin catalog, engine/device/security testing, private friends test | Not implemented; needs private-upload authorization separately |

The experimental folder contains executable model code, not just planning documents.
WorldEconomy covers atomic local transformations, escrow, loot conservation, offline
raid snapshots, cosmetics isolation and the weekly car. DistrictRules covers crew/police,
sequential prison escape, heat, outage/decoy timers and unique convoy claims. They are
deliberately separate from src: adding models is not equivalent to integrating gameplay.

## Persistence architecture before PvP

Use immutable loot IDs and transaction IDs. A loot item is in exactly one place: world,
player carry, vehicle container, stash, escrow, or consumed/settled. Clients request
actions; server owns state, eligibility, time, distance, hit/arrest validation and transfers.

Roblox DataStores do not provide a transaction spanning arbitrary profile keys. Do not
pretend two independent UpdateAsync calls are atomic. Design escrow/transfer state
machines with durable intent, reservations, idempotent operations, reconciliation and
one authority/lease per raid/claim. Debit/reserve first, commit a unique transfer, then
materialize receiver state; a crash must resume or compensate once. Never credit first.

Offline hideouts need persisted snapshots and defense configurations. Run a raid in an
authoritative live server against a leased snapshot; the offline owner's client does not
simulate it. Resolve existing raids at reconnect without overlapping stash writers.
Record bounded audit logs: actor, transaction, result, earned value and timestamp.
Receipts/paid entitlements live outside raid-loss decisions and cannot be consumed.

Bounty contributions reserve actual balance. A target defeat creates one qualifying
claim event against a frozen escrow revision; late contributions must target the next
valid revision or be rejected/refunded once. Define attribution, disconnect and assist
rules before coding. Anti-collusion proposals: related-account review, repeated pair
limits, contribution/claim cooling periods and self/crew exclusions. These are proposals,
not confirmed player-facing rules.

For blackout, server publishes district state with expiry and cooldown. Restore every
affected system even after host disconnect or restart. Decoys never own real loot IDs;
splitting bags transfers individual IDs between containers.

## Rare car and ephemeral Roblox servers

The user's per-server weekly rarity cannot simply use JobId and a local variable:
servers shut down, JobIds change, players reconnect elsewhere. A one-week ownership
promise requires a durable logical server/world identity and routing policy.

Proposed architecture: persistent worldId + cycleId ledger with one carId, ownerId,
heistCompleted, transferRevision, lease and cycleEnd. Gameplay servers lease that world;
replacement servers resume the same car state. All 120-second thefts validate the
current owner/revision continuously, then atomically transfer that ledger once.
Cycle reset increments revision, revokes old ownership/vehicle instances, teleports
the authoritative car to the heist, and reopens exactly once. Retries are idempotent.
Paid skin entitlements survive the car reset.

This proposal preserves the confirmed single circulating weekly car. How a player
chooses/returns to a persistent server-world, and what happens when worlds are merged,
remains a required decision before shipping. Do not silently make it global or permanent.

## Open decisions for the parent, after the first on-screen play

1. Raid loss: full earned-stash wipe or some protected earned progression/bank?
   Paid cosmetics remain protected either way. No answer was confirmed.
2. Exact weekly boundary/timezone and persistent server-world routing.
3. NPC difficulty: selectable medium/hard or heat-driven?
4. Exact eligibility and attribution for bounty claims and disconnects.

An opt-in high-risk mode, protected stash fraction, raid windows, permission/audit controls
and raid-loss limits were suggested but not confirmed. **Do not treat them as accepted
limits or contradict the explicit offline-raid requirement.** Stop adding brainstorm
features; build, verify and let Zack play each concrete milestone.
