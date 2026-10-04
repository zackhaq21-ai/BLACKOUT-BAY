# Experimental world economy model

`WorldEconomy.luau` is an executable, pure Luau state model for approved future
features. It is **not imported by the playable heist**, not a live Roblox economy,
and does not call accounts, DataStores, MarketplaceService, or network services.
Its standalone tests run with the existing official portable Luau executable.

From the `glasshouse` folder:

```powershell
.\tools\luau\luau.exe .\experimental\WorldEconomy.spec.luau
.\tools\luau\luau-analyze.exe .\experimental\WorldEconomy.luau .\experimental\WorldEconomy.spec.luau
```

## Implemented model behavior

- Earned-only balances and stacking bounty contributions. Contributions debit the
  donor into escrow. A server-adjudicated defeat freezes the current bounty; late
  contributions reject without debit until the claim settles. Exactly the credited
  individual receives that escrow once. Duplicate defeat evidence is rejected even
  if submitted under a different operation ID. Going offline does not erase funds,
  pending claims, existing ownership, or hideout vulnerability.
- Unique physical loot IDs with one current location: carry, stash, ordinary vehicle,
  or world. Splitting retires a parent ID and creates exact-value child IDs with
  provenance. Taking, giving, intercepting, or recovering moves existing IDs. Every
  accepted operation checks total live loot value and total earned currency.
- Raids reserve the owner's stash revision and snapshot the shield/laser tiers and
  physical inventory, including when the owner is offline. Reconnection does not
  release that reservation. A supplied outcome moves only its explicit loot IDs.
  Defeated intruders can leave specified carried earned loot in the defender's stash.
  Return logs retain the latest 64 results, attacker, time, snapshot, and values.
- Six earned upgrades for each modeled defense type, shield and laser. Upgrade costs
  must be supplied by the integrating server; test prices are fixtures, not proposed
  accepted balance. Spent upgrade currency remains in an accounted sink.
- Exactly one rare-car record per logical world. It is marked fastest car and has
  two seats; this is ledger metadata, not implemented vehicle handling. The original
  heist awards it once per cycle to one individual. Stored-car theft requires 120
  seconds of uninterrupted, server-validated proximity checks. Repeated theft changes
  the same car's personal owner without reopening the original heist.
- Weekly reset revokes that owner, returns the same car ID to its original heist,
  invalidates active thefts, and reopens the heist. Downtime skips elapsed cycles
  without accumulating cars. `cycleEnd` supplies a visible countdown to a future UI.
- Paid cosmetics are immutable during all modeled operations. They are not loot,
  balances, upgrade tender, raid losses, or part of the car's expiring ownership.

The model deliberately does not choose a full-wipe/protected-stash policy. A raid
may take one, several, or every explicitly supplied physical stash item. The wallet
is a separate accounting representation; its existence is **not a decision that
earned bank balances or progression will be protected in the final game**. That
product decision remains open in `docs/ROADMAP.md`.

## Integration contract

```lua
local nextState, receipt, rejection, replayed = Economy.apply(state, {
    id = "stable-server-operation-id",
    worldId = state.worldId,
    expectedRevision = state.revision,
    now = serverUnixSeconds,
    kind = "ContributeBounty",
    actor = "donor-user-id",
    target = "target-user-id",
    amount = 2000000,
    bountyRevision = 1,
})
if nextState then
    -- Commit/replace this complete state exactly once through the authority layer.
    state = nextState
end
```

Successful operations return a fresh state without changing the input. Failed
operations return `nil, nil, reason, false` without partial effects. Exact replay of
an already committed operation returns the current state and original receipt,
without reapplying it. Reusing an operation ID with changed payload rejects. Replay
of an old successful operation does not restore old ownership after later changes.

All commands are **trusted server domain events**, not a public RemoteEvent API.
`actor`, world ID, timestamps, loot lists, defeat attribution, and outcome decisions
must be constructed by the server. Fields such as `eligibilityDecision`,
`transferDecision`, `accessDecision`, `outcomeDecision`, and `proximityDecision`
are audit references to that adjudication, **not authentication tokens**. A client
must never be allowed to choose these fields to make an arbitrary transfer valid.

The game adapter must validate positions, interaction duration, defeat/capture,
combat counterplay, access/betrayal permissions, crew split agreements, and physical
item presence. Bounty eligibility, self/crew exclusions, assist attribution, repeated
pair controls, and disconnect-as-defeat rules remain external, unresolved policy;
the model does not silently impose the proposals from the roadmap.

For car theft, issue `BeginCarTheft`, then `ValidateCarTheft` only after each live
server check, followed by `CompleteCarTheft`. The supplied operational gap is at most
10 seconds (tests use 2). A check gap rejects continued completion. Explicit player
disconnect interrupts their current attempts, even if they immediately reconnect;
the rightful owner remains unchanged. Moving the car, another successful theft, or
a weekly reset invalidates the old attempt by revision. The server must also cancel
on movement out of range, combat interruption, death, or other approved conditions.

## Persistence and remaining limits

This model assumes one serialized authority and one atomic complete-state commit.
It tests compare-and-swap revisions; it does **not** implement cross-server leases,
DataStore retry/reconciliation, durable write-ahead intents, or crash recovery across
multiple keys. Roblox documents `UpdateAsync` as an update to one key with a
non-yielding callback; unrelated profile writes are not combined by this module.
See [official DataStore guidance](https://create.roblox.com/docs/cloud-services/data-stores).

Before live integration, design durable world routing/leases, record partitioning,
escrow reservations, recovery, and idempotency retention together. The full state,
operation receipts, retired loot lineage, defeat records, and raid records grow with
activity. Only player-facing raid logs are bounded here. The deep-copy implementation
is suitable for these tests, not a scalable storage implementation; do not write this
whole growing structure on every 2-second theft check in a real DataStore.

The constructor requires an explicit cycle start and persistent logical `worldId`.
It implements fixed 604800-second cycles from that supplied epoch. It does not pick
Zack's weekly calendar boundary/timezone or decide how ephemeral Roblox servers
route players back to persistent worlds. Those remain product/architecture choices.

Profiles, earned assets and ordinary vehicle containers are seeded for testing.
There is no player/profile lifecycle service, wallet-to-bag conversion, minting,
commerce adapter, physics, defense combat/counters, raid lease expiry/recovery,
recovery-clue mission, UI, asset ownership service, or production security validation.
An abandoned raid can be resolved as `Aborted` with empty outcome lists by the
future trusted recovery service; this module does not invent a raid timeout.

## Evidence

On 2026-10-03, portable Luau completed **26 tests, 0 failures**, including invalid
partial transfers, duplicate receipts, simultaneous thieves, thief disconnect,
offline raids, full supplied stash loss, stolen-loot recovery, bounded return logs,
car reset/downtime, and 100 repeated transfer/replay cycles. Static analysis exited
0 with no diagnostics. These are model tests, not Roblox multiplayer or persistent
economy integration tests. See `WORLD_ECONOMY_TEST_RESULTS.txt`.
