# STATUS — handoff record

Keep this short. Current task, decisions, changed files, verification, blockers, next step.

## Current state: review branch `claude/review-m10-polish` (stacked on m9 ← m8 ← m7 ← m6 ← dev; none merged)
Premium polish pass, batch 1: feel, camera, vehicles, environment, VFX, audio architecture, UI motion. No new gameplay.

### Done on this branch
- Pure, tested feel maths: `CameraFeel` (FOV by state, landing dip, stable smoothing), `VehicleFeel` (drive modes, torque curve, steering lock and hand speed by speed and class, brake lights), `WeatherRules` (bounded state machine, looks, readable blends, blackout modifier, lightning gaps). All constants in `Config.Presentation`; wheel radius consolidated into `Config.Vehicles.WheelRadius`.
- Client: `CameraController`, `MovementController`, `EnvironmentController` (weather, blackout moonlight now client-side, lightning, rain, wet roads, Low/Medium/High/Max tiers with a Looks-tab control), `Fx/Vfx` pool, rewritten `AudioController` (nine SoundGroups, positional cues, beds, interior mix, visual twins), `VehicleController` on `VehicleFeel` with engine bed hooks; UI motion (press feedback, toast slide, money/stash pulse, banner fade).
- Server: `EnvironmentService` (authoritative weather, replicated, NPC vision factor), `Security`/`Police` vision factors composed from blackout and weather, `Comms.cueAt` positional cues (smash, breaker, pier door, laser trip, substation, convoy breach), vehicle headlight/brake-light states for everyone, `BlackoutService` no longer tweens Lighting (client owns the look), convoy drivers share the steering maths.
- Materials: Limestone for civic stone, CorrodedMetal for harbour steel. Art direction, Studio debt and test docs updated.
- Batch 2 (NPC, reactivity, mobile, consistency): guards hear a sprinting player inside the museum (sneak and walk stay silent) through the existing noise path; cruisers steer with the shared `VehicleFeel` maths; the baseline look comes from `WeatherRules.look("Clear")` with `default.project.json` trimmed to static Lighting properties (one source instead of three); touch layout keeps the vehicle, hint and carry panels off the thumbstick and action buttons; thin `setGuardVisionScale` wrapper removed; `config_consistency.spec` guards cross-table invariants. StreamingEnabled deliberately left off (runtime-built world, teleport-driven engine scenario); documented as a Studio decision.

### Verification
`tools/check.sh`: type check 0 errors, lint 0 warnings, 90/90 logic tests, both places build. Nothing Studio-verified; feel, handling, lighting and weather are visual debt in `docs/STUDIO_VERIFICATION_PENDING.md`.

### Earlier decisions still in force
Full stash exposure on raids; banking enabled; 7-stud takedowns; m8 at `9e259d6`, m9 at `2f0ab3b`; keep m6–m10 pushed, separate, unmerged, in dependency order; no new major gameplay until the polish pass is complete.

### Not implemented (from the full vision)
Player police faction, aircraft, vehicle earning; rare car in-world and its persistence decision; weapons/combat beyond takedowns; live purchases; sound assets; custom art; performance profiling.

### Next task
1. On the prepared PC: `tools\verify-engine.ps1 -Players 1,3,5`; fix what it reports; play by hand per `docs/LAUNCH.md`.
2. Merge m6 → m7 → m8 → m9 if accepted (fast-forward in that order).
3. Owner visual review in Studio of the polish branch (one consolidated session per `docs/STUDIO_VERIFICATION_PENDING.md`), then tuning from observed feel. Remaining polish candidates needing Studio first: wet-road traction, custom animation set, StreamingEnabled trial, light budget by tier.
