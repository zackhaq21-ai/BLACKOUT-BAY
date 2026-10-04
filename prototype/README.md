# Preserved prototype baseline

`aurora-v0/` is the Blackout Bay "Aurora Exchange" prototype that was built and verified in Roblox Studio on
Zack's PC (StudioTestService scenarios for crews of 1–5; see its `docs/VERIFICATION.md` and `dist/`). It is
kept here unchanged as the tested baseline and as the source of the pieces that were carried into the main game:

- the profile transaction model (receipt + entitlement in one transaction, earned unlocks, equip) → `src/shared/Core/ProfileOps.luau`, `src/server/Services/DataService.luau`
- the commerce scaffold (disabled, zero ids, ProcessReceipt only after a durable write) → `src/server/Services/CommerceService.luau`
- the cosmetic catalog and suit recolouring → `src/server/Services/CosmeticsService.luau`
- relocation with a network-ownership hold and the character speed sanity check → `src/server/Services/MovementService.luau`
- result tier names (GHOST CREW / NARROW ESCAPE / SMASH & DASH / LAST LIGHT) → `src/shared/Core/MissionFlow.luau`
- the native Studio test harness pattern (hook + driver + run-in-roblox runner) → `tests/engine/`, `tools/verify-engine.ps1`

Its own place file is `aurora-v0/dist/BlackoutBay.rbxlx` and still opens on its own. `CLAUDE.prototype-copy.md`
is the copy of the repository instructions it shipped with (renamed so only the root `CLAUDE.md` is active).
Nothing in this folder is loaded by the main game.
