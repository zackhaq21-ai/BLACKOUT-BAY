# Blackout Bay — Aurora Exchange prototype

Native Roblox heist prototype for **solo through five players**. One coastal museum,
three approaches, patrols, quiet/forced vault access, a five-seat getaway car, three
extraction locations and free retries. This is the first playable section of Blackout
Bay; the full shared-world game is not complete.

This local integration branch starts from Claude's existing repository instructions.
CLAUDE.md is preserved unchanged. STATUS.md records the reconciliation, exact imported
scope, test evidence and limitations. Internal Glasshouse module names/log prefixes
remain from the tested prototype; player-facing branding is Blackout Bay.

## Play

1. Open Roblox Studio. Sign in yourself if prompted.
2. Choose **File > Open from File** and select **dist/BlackoutBay.rbxlx**.
3. Click **Play / F5**, then **Start run** in the game briefing.

On Zack's prepared Windows PC, **Play Blackout Bay.cmd** also opens Studio and starts
solo automatically. This optional helper uses the local development runner; it is not
required to play the native place. Downloaded executables are excluded from Git.

Walk to a blue entry pad and press E once, then stay nearby. Sync the required mint
signal consoles and cut the north light grid. Open the HUD-named vault with E, or
force it with F for +65 heat. Take the core, use the gold front getaway gate, and
walk or drive to extraction. The tunnel west along the safehouse road always works.

The carrier starts extraction. Crew within 20 studs escapes together. After a result,
wait five seconds and start another run. Capture sends you to the coral recovery
pad; recovery is free and costs 15 mission seconds.

## Controls

| Action | Keyboard | Controller / touch |
|---|---|---|
| Move / drive | WASD | Standard Roblox controls |
| Main interaction | E | X / tap prompt |
| Alternate choice | F | Y / tap alternate |
| Jump / dismount | Space | Standard jump |
| Briefing | B | View / Brief button |
| Cancel interaction | Walk away / Backspace | Move away |

Release the curator to unlock the canal; capture adds one signal and heat. At 75 heat
the tram closes. At 100, at most 60 seconds remain. Cover blocks patrol sight. Three
free stasis charges are available each run. All roles can perform every objective;
no simultaneous-player requirement blocks solo.

## Evidence and limits

All eight shipped scripts compile; 29 gameplay tests, 26 experimental economy tests
and 19 experimental district tests pass. Native Studio scenarios have completed
extraction, real client car input, recovery/retry and multiplayer disconnect handling
across the supported crew sizes. The solo curator/canal branch also passes.

Automated tests position characters, invoke registered prompt handlers and freeze
patrols. They do not establish human navigation, polished rendering, pleasant steering,
controller/touch usability, internet multiplayer or production security. See
docs/VERIFICATION.md for exact baseline/build distinctions and retained output.

DataStores and commerce are disabled. Local progress resets when Studio Play stops.
Opening the file does not publish, upload to a Roblox experience, or purchase anything.

## Project files

- src/ — native Luau server/client/shared source.
- dist/BlackoutBay.rbxlx — directly importable place.
- docs/DESIGN.md and docs/ROADMAP.md — current mission and approved larger scope.
- docs/PLAYTEST.md — remaining human and device checks.
- experimental/ — tested future economy/district models, not live game systems.
- tools/build.mjs — generate the place with Node.js built-ins, no npm dependency.
- tools/verify.ps1 — compile, model tests and XML/source verification.
- tools/verify-engine.ps1 — isolated native Studio scenarios.
- tools/TOOLING.md — optional portable validator/runner provenance.
- default.project.json — optional Rojo mapping; Studio import requires no Rojo.

Run **node tools/build.mjs** after editing source, then reopen the generated place.
A running Studio document does not update automatically. No paid gameplay, live
product IDs, outside asset dependencies or copied game map/models are included.
