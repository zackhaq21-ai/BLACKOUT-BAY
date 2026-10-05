# Asset inventory: blank hooks (nothing invented, nothing from the Toolbox)

Every id is blank and the game runs safely without it: sounds stay silent, animations fall back to the default R15 set, surfaces stay primitive materials and SurfaceGui text. Fill only with owned or licensed assets, then set the id in `src/shared/Config.luau` (audio) or the builder/controller noted.

## AUDIO (37 hooks, all optional)
| Hook | Location | Purpose | Fallback |
|---|---|---|---|
| Cues (23): Pickup, Drop, Deliver, Alarm, Suspicious, Lockdown, Smash, Drill, Keypad, Unlock, Siren, Payout, Arrest, PowerCut, ConvoyAnnounce, ConvoyAlert, ConvoyBreach, ConvoyLost, ConvoyDelivered, ConvoyRadio, LaserTrip | `Config.Audio.Cues` → `AudioController` (groups, positional pool) | one-shot feedback for interactions and events | HUD flash and/or pooled VFX twin for each cue |
| Engines (6): Kestrel, Courier, Commuter, Cruiser, Armored, Escort | `Config.Audio.Engines` → `Sound "Engine"` on every chassis; pitch from speed in `VehicleController` / `ConvoyDriver` | engine bed per class | silent; the Sound instance exists and stays stopped |
| Ambience (6): City, Harbour, Interior, Rain, Storm, Wind | `Config.Audio.Ambience` → `AudioController` beds | weather and place ambience, interior duck | silent |
| Feel (3): Land, SprintStart, Footstep | `Config.Audio.Feel` → `MovementController` | movement feedback | silent; VFX dust still plays on hard landings |
Required for final quality: Alarm, Siren, Smash, PowerCut, Payout, ConvoyAnnounce, engines, Rain. Optional: the rest.

## ANIMATION (0 custom; default R15 set in use)
| Need | Location | Required? | Fallback today |
|---|---|---|---|
| carry (light bag) idle/walk/run | `Animate` override, not implemented; would hook `MovementController` | optional | default locomotion |
| heavy carry (Core) walk | same | optional | default walk at 11 studs/s |
| downed / stunned pose (takedown, laser trip) | `PlatformStand` currently | optional | ragdoll-less platform stand |
| breach / sabotage / drill / crack hold loops | prompt holds | optional | no pose change |
| vehicle enter/exit | seats | optional | engine default sit |
Decision: hold until Studio shows where snapping or sliding is visible (checklist §3). Any custom set must be owned; none is to be taken from other experiences.

## TEXTURE / DECAL (0 used; primitives and SurfaceGui text by design)
| Candidate | Location | Required? | Fallback today |
|---|---|---|---|
| road markings / manholes / curb decals | `IslandBuilder` roads | optional | pale dash parts |
| signage artwork (Aurora Exchange, Lantern Cross, Harbour Security) | `Builder.neonSign`, `VehicleBuilder.decal` | optional | text SurfaceGuis (editable, localisable) |
| MaterialVariants (wet asphalt, weathered steel, limestone) | per-material | optional | built-in materials + Reflectance while wet |
| vehicle liveries | `VehicleBuilder` | optional | solid colours + text decals |

## OTHER
| Candidate | Location | Required? | Fallback today |
|---|---|---|---|
| skybox | `Lighting` (none set) | optional | default sky with Clouds instance |
| character cosmetics (suits) | `Config.Commerce.Catalog` colours only | optional | colour-only looks; purchasing disabled |
| vehicle meshes | `VehicleBuilder` primitives | optional | part-built cars |
| NPC rigs | `Players:CreateHumanoidModelFromDescription` with block fallback | required for look, works today | block rig |

Rule unchanged: never insert Toolbox scripts or assets, never use copyrighted material without rights, never invent ids. The config consistency test asserts every cue id is blank in this build.
