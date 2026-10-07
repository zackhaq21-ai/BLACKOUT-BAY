# Economy audit (static, pre-merge; no values changed)

Currency: Marks. Sources create money; transfers move it; sinks destroy it. All numbers from `src/shared/Config.luau` and the stocking code in `LootService.restockMuseum` at the freeze.

## Sources (money created)
| Source | Value | Cadence / gate | Risk attached |
|---|---|---|---|
| Museum run (Aurora Exchange) | 3 Trinkets 1,050 + 2 Relics 1,800 + 1 Jewel 1,800 in the hall, 2 vault cases (Relic or Jewel, 900–1,800 each), Core 7,500 → **8,250 to 10,950 + 7,500 Core = up to ~18,450** per full clear | restock 90 s after the vault empties, cycle 600 s | guards, cameras, alarm, lockdown, police heat, arrest drops bags |
| Armored convoy | 3 × 2,000 = **6,000** | one per server, ≥ 900 s cooldown + 480–720 s auto-schedule → about one per 25 minutes | 10 s breach only while stopped; escorts see 360° within 55 studs so the breacher is almost always seen (+80 heat); crates are ordinary loot (stealable, droppable, recovered after 150 s) |
| Starting cash | 500 (wallet, raid-proof) | once per profile | — |
| XP | 25 empty / 100 + value/100 (cap 200) + 50 ghost bonus per job | per closed job | cosmetics only |

## Transfers (zero-sum)
Raids (full stash of the victim to the raider's stash), recovery (exactly the stolen amount back), bounties (contributor stash → hunter stash), convoy crates stolen between crews, job shares.

## Sinks
Fake bag 150 each; banking fee 10% (stash → raid-proof wallet, 120 s cooldown); share rounding (≤ n−1 Marks per delivery for n members); convoy crates abandoned 150 s (recovered by Harbour Security); laser and defence tiers 1,500 / 3,000 / 5,000 / 8,000 / 12,000 / 18,000 (47,500 total, spent from stash).

## Standing (progression) sources, added in m13
Not money. Base awards: job 25 empty / 100 + value/100 (cap 200) + 50 ghost bonus; convoy crate fenced 40; raid with loot taken 80; recovery 60; bounty collected 50; blackout reset 30. Crew bonus +10% per present member. Daily full-value counts: job 6 (then ×0.5), convoy crate 6 (×0.5), raid 2 (×0.5), bounty 2 (×0.5), blackout reset 2 (×0.25), recovery unlimited. Awards dedupe by id for life, so repeating the same raid id, crate or takedown pays nothing. Farming check: the cheapest repeatable source (blackout reset, 30, two per day full) yields under 100 Standing a day; a Runner rank (200) takes two paid jobs or one good crew job plus one convoy crate.

## m14 additions
Storm convoy: one sealed crate of 5,000 (vs 3 × 2,000) carried Heavy (11 studs/s, no jump/climb), roughly half the time per convoy at a quarter of the trips; the escort sight reduction comes from the existing weather factor, police heat unchanged. Accomplishments: 60–150 Standing each, exactly once per profile, no money. Contacts sell nothing.

## Findings for later tuning (no change made)
1. **Convoy effort vs. reward (medium).** A solo breach at a checkpoint takes 10 s (6 s during a blackout) and yields 6,000 if the three crates reach a pier: about a third of a full museum clear for far less time inside a guarded building. The costs are +80 heat, three separate 2,000 trips (one bag at a time, trunks hold more) and police dispatch. Watch in Studio whether a Kestrel with two crates in the trunk makes this the dominant income; candidate levers: `CargoValues`, `CheckpointSeconds` (18 s is longer than the 10 s breach), `AttackHeat`, `AbandonSeconds`.
2. **Blocking is cheaper than ramming (low).** Standing in front of the lead car halts the convoy at once; alert comes after 6 s and "engaged" after 20 s, so a block-and-breach needs no car damage. The breacher is still seen by the escorts (heat). Lever: `BlockPatienceSeconds`.
3. **Bounty as a stash transfer (low, by design).** A contributor cannot claim and crewmates cannot claim, but a contributor's friend in another crew can: money moves from the contributor's raidable stash to the hunter's raidable stash. No money is created, and the target must actually be downed on foot. It is a laundering path only in the sense that it moves stash between accounts; it never leaves the raid-exposed pool. Acceptable; log already records both sides.
4. **Museum restock loop (expected).** Up to ~18,450 every 600 s cycle for a 5-crew that clears everything with the Core; per player that is ~3,700 per cycle at the top end, consistent with tier costs taking several sessions. Not a bug; the main income by design.
5. **Share rounding** destroys at most n−1 Marks per delivery (`SplitLedger.distribute`), tested; negligible sink.
6. **No infinite loops found.** Every creation path is gated by server cooldowns or the museum stock; every transfer is atomic in the ledger or a `HideoutRecord` transform; test grants exist only in the engine-test place.
7. **Risk-free income: none.** Starting cash is the only unearned money and is raid-proof by design.
8. **Values vs. progression.** Convoy crate 2,000 ≈ a Jewel (1,800); Core 7,500 remains the single biggest prize. Tier 6 defences (18,000) ≈ one full museum clear or three convoys. Nothing is dramatically outside the existing scale.
