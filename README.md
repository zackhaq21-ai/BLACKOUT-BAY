# GLASSHOUSE (working title)

An original Roblox open-world heist game: build a fortune in a city where everyone can see what you have, and someone you trust may help them take it.

- **Play**: open `build/Glasshouse.rbxl` in Roblox Studio and press Play. See `docs/LAUNCH.md`.
- **Source**: `src/shared` (config, palette, map data, pure game logic), `src/server` (world builders, services, NPC brains), `src/client` (HUD and controllers). Built with Rojo (`default.project.json`).
- **Checks**: `tools/check.sh` (type check, lint, logic tests). `tools/build.sh` builds the place.
- **Docs**: `docs/DESIGN.md` (decisions), `docs/ART_DIRECTION.md`, `docs/STATUS.md` (handoff), `docs/TEST_RESULTS.md`.

Current milestone: the complete first heist loop (Aurora Exchange) for solo and crews of up to five, with physical loot, hideout delivery, museum security, NPC police and jail. Implemented and statically verified; not yet playtested in Studio. Purchases are disabled; nothing is published.
