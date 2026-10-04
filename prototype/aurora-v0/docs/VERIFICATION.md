# Verification record

Native place: dist/BlackoutBay.rbxlx, eight editable source files under src.
All work is isolated in the Glasshouse project. No Velzico checkout or processes were
modified. No Roblox publishing, experience upload, products or purchases were performed.

## Reproducible local checks

- Official Luau 0.741 compiler: all eight game scripts pass.
- Shipped gameplay/progression model: 29 tests pass, including sequential solo routes,
  1-5 scaling, carrier disconnect, role reassignment, duplicate interactions, timeout,
  rewards, receipt deduplication, entitlement protection and disabled commerce.
- Experimental WorldEconomy: 26 tests pass. DistrictRules: 19 tests pass. Both models
  pass standalone static analysis with no diagnostics. These models are not imported
  by the playable place.
- Generated XML parses and all eight embedded UTF-8 sources match the editable files.
- Exact artifact hash and complete logic output: dist/verification.txt.

Run tools/verify.ps1 for these checks. It does not start Studio.

## Actual native Studio tests

Baseline distinction for this repository import:

| Crew | Completed native evidence | Source baseline |
|---|---|---|
| 1 | Quiet/driving/recovery/retry and curator capture/release/canal | 792AF562 source build |
| 2 | Full quiet/driving/recovery/disconnect plus late join | Earlier 2C597835 build; latest rerun quiet/recovery passed but Studio exited during disconnect |
| 3 | Full quiet/driving/recovery/disconnect | Earlier 2C597835 build |
| 4 | Full quiet/driving/recovery/disconnect | 792AF562 source build |
| 5 | Full quiet/driving/recovery/disconnect | 792AF562 source build |

Full SHA-256 values for those baseline places:
792AF562093B42026F74FFF0F91AF34189325D81191D6290C63C9E56CF10E06E and
2C597835FFA48B5BF7C0E9E2A31C3EA54F715AF3C3395BDB6B4060C1B4E2EBCB.
The Blackout Bay import changes player-facing branding and output filenames only
relative to the later gameplay baseline; its own hash is in dist/verification.txt.
A complete clean five-count matrix on the renamed import is not claimed.

The final solo extraction regression was a test-input problem: dismount now originates
on the client and the driver waits for landing. Incidental human keyboard input is
disabled only in automated test clients. The normal game controls are unchanged.

The official signed Roblox Studio installation was authorized by Zack. Native tests
use StudioTestService through the reviewed local run-in-roblox development helper.
Each crew size runs in its own Studio process. The test copy is separate from the
shipped document; no EngineControl remote or test hooks ship in BlackoutBay.rbxlx.

Current results and exact car displacement are recorded in
dist/engine-multiplayer-results.txt. A passing scenario checks:

1. Real server and local clients spawn and load profiles.
2. Required signal count scales to the starting crew, all players enter, one player
   can finish the quiet route in sequence, and the core carrier extracts the crew.
3. Actual client VehicleSeat throttle moves the server-simulated car more than 20
   studs in two seconds. Tests do not move the car to manufacture this result.
4. Rewards are credited; normal five-second retry rebuilds a clean run.
5. Forced vault, capture, core drop, free recovery, re-entry, core retrieval and
   tunnel extraction complete. Capture is invoked through a test hook in this case.
6. Multiplayer carrier disconnect drops the core; remaining roles match the current
   crew and a partner can retrieve the core and finish.
7. The two-player scenario adds a real third local client during the first run and
   verifies that it cannot join that active crew. Subsequent retries include it.
8. The solo scenario additionally captures/releases the curator and extracts at the
   newly unlocked canal, checking interaction sight lines and that branch.

The first observed human-started solo session on 2026-10-03 also ran for 480 seconds,
captured once through the ordinary game loop, then timed out and produced the failure
result. That earlier session did not complete a heist.

## What the automated tests do and do not establish

The test driver deliberately positions characters, freezes patrols and invokes the
registered native prompt handler. Production distance, sight, server timing,
prerequisites, physics, rewards and replication checks still execute. This verifies
real engine integration; it does not measure human navigation, stealth difficulty,
camera behavior, controller/touch input or visual polish. Car displacement proves
input and motion, not pleasant steering or five occupied seats under network lag.

No callable desktop screenshot/control runtime was exposed to this delegate. Visual
QA remains a parent/user handoff. No screenshots or manual clicks are claimed.
Live DataStore/Marketplace operations, internet multiplayer, real-device performance,
security under adversarial clients, and a long retry soak remain unverified.

## Fixed issues found through review/testing

- Recovery-pad sight rays hit the safehouse floor. Flat-pad rays now aim above the
  pad surface; upright props still use their center so the curator head cannot block
  capture/release interactions.
- A client physics update could undo a server relocation on retry. Relocations now
  briefly take server ownership, detach this character's seat weld and restore normal
  ownership afterward. A player seating during that window waits until dismount.
- Dropped core could be buried in scenery. It now returns to a known clear pedestal.
- Shutdown now waits for in-flight profile flushes; receipt retries can persist during
  pending-save status; no-op equip requests do not spam persistence.

The native helper also exposed test-harness limits: back-to-back multi-client tests
inside one Studio process could stop the next run, and an aborted run left local test
children/plugin behind. Those exact test processes were cleaned up; original user
Studio documents were preserved. The reproducible runner now uses separate processes.

Use docs/PLAYTEST.md for the remaining observed-human and device checklist.
