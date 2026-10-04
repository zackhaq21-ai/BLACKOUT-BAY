# Server and save design

## Implemented protections

- Clients send only allowlisted command strings and a bounded cosmetic ID/mode.
  No client-specified currency, objective completion, damage or reward totals.
- Native proximity prompts request a server-owned timed interaction. Server checks
  membership, life state, target, enabled state, distance, line of sight and mission
  prerequisites at start and continuously until completion. Client hold timing is unused.
- Anchored objective targets; moving guards are anchored and positioned by the server.
- Rate-limited commands and prompt starts, one pending action per player, no-op equips
  suppressed and equip persistence limited to one action per five seconds.
- Signals/core/extraction and reward eligibility are server-owned and idempotent.
- Cosmetic changes affect visual color/decor only. No paid stat/tool/loadout code.
- Save operations use UpdateAsync against current persisted state, not stale profile
  replacement. Entitlement plus receipt ledger are written in one profile transaction.
- A failed initial load becomes an unsaved session and cannot overwrite existing data.
  The HUD exposes session-only/unavailable/pending status.
- Pending run/equip writes retry periodically and on departure. Shutdown waits for
  in-flight transactions and pending queues, bounded by a 25-second deadline.
- Unknown save versions throw instead of being replaced by defaults.

## Disabled commerce

Config.CommerceEnabled = false; Config.DataStoreEnabled = false. Every PassId and
ProductId is zero. Studio always uses memory, even if a developer accidentally changes
the data-store flag. No purchase, product creation, pass setup, account upload or publish
was performed.

Use one-time Roblox passes for permanent catalog cosmetics. On join/purchase completion,
the server checks UserOwnsGamePassAsync before persisting ownership. The client obtains
the current Roblox price for configured passes; Roblox's final confirmation governs
the charge. No fabricated/hardcoded Robux price is shown for inactive items.

A separate disabled developer-product receipt handler is included for review. It defers
unknown/unavailable receipts, commits entitlement and PurchaseId together, acknowledges
only after the transaction succeeds, and tolerates repeat callbacks. Failed saves remain
eligible for receipt retry. Repeatable products should not be used to resell an already
owned permanent cosmetic. No product-prompt route exists in this build.

## Remaining security/persistence limits

This is private prototype code, not hardened public PvP/economy infrastructure.

- Roblox characters remain client-simulated. The displacement check is a basic sanity
  check, not production anti-cheat; it does not comprehensively prevent flight, clipping,
  lag exploits or controlled high-speed movement. Hostile-client tests and movement/path
  validation are required before competitive loot transfers.
- Data-store operations and actual Roblox receipt callbacks have not been integration
  tested here. Pure tests cover transformations/deduplication, not Roblox service delivery.
- Run and receipt ledgers currently grow with use. Add a reviewed bounded archival/
  retention strategy and data-size monitoring before long-lived accounts; never casually
  prune a receipt deduplication ledger.
- Pending operations are in server memory until committed; a hard crash or exhausted
  shutdown deadline can lose an uncommitted run reward. No money is sold in this build.
- Profiles are retained in memory for the local server lifetime, including departed users,
  to preserve retries. Add idle-cache cleanup after successful flush for public servers.
- No cross-profile escrow/atomic transfer system exists yet. Never connect the proposed
  bounty, raid or rare-car economy directly to the simple XP profile.
- The car uses server-owned arcade physics; engine, mobile, latency and collision checks
  are outstanding. No production vehicle-security claim is made.

## Official references reviewed 2026-10-03

- [Client/server security](https://create.roblox.com/docs/scripting/security/client-server-boundary)
  — validate remote inputs and prompt context; do not trust client timing or location alone.
- [Data stores](https://create.roblox.com/docs/cloud-services/data-stores)
  — server-side persistence, error handling and UpdateAsync.
- [Developer products](https://create.roblox.com/docs/production/monetization/developer-products)
  and [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService)
  — durable receipt handling, retries and server grant authority.
- [Passes](https://create.roblox.com/docs/production/monetization/passes)
  — one-time ownership and current product information.
- [Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items)
  — no paid randomized items are included.
- [Proximity prompts](https://create.roblox.com/docs/ui/proximity-prompts)
  — built-in keyboard, gamepad and touch interactions.
- [Studio tests](https://create.roblox.com/docs/studio/testing-modes)
  and [Studio setup](https://create.roblox.com/docs/studio/setup)
  — local client/server testing and installation.
