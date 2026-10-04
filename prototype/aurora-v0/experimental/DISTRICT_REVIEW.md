# District model review and regression fixes

Verified 2026-10-03 with the existing portable Windows Luau tools:

```powershell
.\tools\luau\luau.exe .\experimental\district_tests.luau
.\tools\luau\luau-analyze.exe .\experimental\DistrictRules.luau .\experimental\district_tests.luau
```

Results: **19 tests passed**; static analysis exited **0**, no diagnostics.
These checks execute the pure state model, not integrated Roblox police gameplay.

## Fixed defects

1. Leaving, changing crews, or becoming a cop could leave a stale crew leader.
   Leadership now stays with the current eligible online member or passes to the
   first online member in deterministic ID order. It is nil when everyone is
   offline. Returning original leaders do not displace a current online leader.
2. Operation ID reuse with a different payload previously returned a silent no-op.
   Only exact payload replay is accepted; conflicting reuse rejects. Stored
   payloads are copied, so later caller mutation cannot rewrite the receipt.
3. Escape steps accepted no detention identity or expected revision. Delayed steps
   from previous arrests could affect a new detention; completed steps could also
   be applied again under new IDs. Each arrest now uses its operation ID as the
   detention ID. Escape steps validate that ID, current revision, sequence, and
   whether the step was already completed.
4. Disconnect/rejoin had no session generation. Delayed lifecycle and physical
   actions could be applied after a player rejoined. Sessions now increment upon
   offline-to-online transitions, and relevant actions validate them.
5. Several evidence checks accepted truthy strings or numbers. Escape, blackout,
   and convoy evidence flags now require literal booleans. NPC arrest origin is
   checked as a boolean, and initial human-cop population is explicitly zero.

## Updated experimental command contract

- Each actor has a `session` counter starting at 1. `Join` preserves custody,
  faction, heat, recognition and crew membership. A real rejoin increments the
  counter; an extra Join while already online does not.
- `Leave`, `Faction`, `Crew`, `Blackout`, `Decoy`, `ConvoyIntercept`, and
  `ConvoyClaim` require `op.session` matching the actor's current generation.
- Human `Arrest` requires the cop's `op.session`. Both human and NPC arrests
  require the target's `op.targetSession`.
- `EscapeStep` requires the helper's `op.session`, prisoner's
  `op.targetSession`, `op.jailId`, and `op.revision` matching the current jail.
- The server adapter captures these fields when constructing an adjudicated
  event. Do not replace stale metadata with current values when retrying an event.
  The test helper supplies current metadata only for newly created test events;
  regression cases explicitly retain old metadata to prove rejection.
- `District.apply` retains its existing success return (`newState, changed`) and
  throws on invalid input. The caller must catch rejection and keep the old state.
  Exact replay returns the unchanged current state and `false`.

## Precise remaining limits

The model is trusted server-domain logic, not a RemoteEvent validation boundary.
Sessions prevent old events crossing reconnects; they do not prove position, elapsed
channel time, hits, stun, or fresh evidence. Those inputs must come from the server.

Existing disconnected crew membership remains reserved and counts toward five;
only acting leadership changes on disconnect. Removing offline crew members,
invitation/consent rules, explicit crew departure and captain permissions are not
implemented here. No new game-facing membership policy was inferred.

The model does not supply a store lease, world revision/CAS commit, durable recovery,
or cross-module atomic transaction. A convoy Claim changes district state only.
Integration must commit that claim and the existing physical loot ID transfer in
one authoritative transaction with WorldEconomy; two independent successful writes
must not be treated as atomic. The model never mints convoy loot itself.

Applied-operation payloads, actors, convoys, and decoys remain unbounded. Events alone
are capped at 100. There is no convoy cleanup/route completion, persistence migration
for earlier experimental `applied[id] = true` data, detention timer/physical map,
police AI/loadouts, input/UI, or difficulty selection. Blackout restoration and
recognition expiry depend on the authority calling `District.tick` with advancing
server time, including after restoring persisted state.

The 90-second blackout, 240-second cooldown, and two/three escape-step counts remain
prototype tuning values from the original model, not user-confirmed final balance.
Ten fallback NPCs are modeled only as a count; medium/hard combat is not implemented.
