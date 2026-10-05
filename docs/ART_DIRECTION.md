# GLASSHOUSE — Art Direction

A stylized coastal city at dusk. Pale stone, dark asphalt, sea-glass accents, warm interiors, an industrial waterfront, and restrained security lighting. Everything is readable at a glance: wealth glows gold, danger glows red, police glow blue.

## Rules
- **Palette** lives in `src/shared/Palette.luau`. No new colours without adding them there.
  - Pale stone / warm stone for civic buildings; dark asphalt roads with pale dashes; sea-glass for the museum, water, and "value"; warm amber for interiors and lamps; rust and grey for the harbour; security red only for alarms and lockdown; police blue only for police.
- **Materials**: Limestone for pale civic stone, Concrete for plinths, parapets and pads, Marble inside the museum; Asphalt for roads (Cobblestone for pedestrian lanes), with a touch of reflectance only while wet; Brick for the warm blocks; CorrodedMetal for weathered harbour steel, painted Metal for vehicles, DiamondPlate for armour and gantries; Glass with slight reflectance for the museum façade and towers; Metal / DiamondPlate for the harbour and gantries; Neon only for signs, lamps, alarm lights and lit windows.
- **Silhouettes**: every building has a plinth and a parapet line; heights vary per block so the skyline reads from the overpass. The museum is the only sea-glass building: you can find it from anywhere.
- **Lighting**: ClockTime 19.6, dense blue-grey atmosphere, warm point lights inside, cool floods on the plaza, amber on the harbour and the parking deck route. Lighting is mood, never a gameplay fog: fog never closes in past 260 studs and ambient never goes black. The client owns the look (`EnvironmentController`); the server only owns *state* (weather, blackout).
- **Weather** (server-picked, client-blended over 25 s): Clear, Overcast, Rain, Storm, Fog. Rain darkens the sky, wets the asphalt and adds a rain bed; storms light the clouds and the environment for a quarter second (never a white screen); fog shortens the view but never below readable range. Weather also trims NPC sight (85/70/60%), composed with the blackout.
- **Blackout look**: moonlit blue, not black. Street and window light dies, amber battery lamps mark routes, the lighthouse keeps sweeping, the station stays lit, cruiser and convoy strobes become the brightest things on the street.
- **Camera**: field of view breathes with sprint (70 → 76), narrows when sneaking (66) or downed (62), widens with vehicle speed (up to 82 at top speed, none at town speeds). A hard landing dips the camera up to 1.6 studs and recovers in about half a second. No shake, no roll, no bob.
- **Graphics tiers**: Low / Medium / High / Max (Auto picks Medium on touch, High elsewhere; cycle it in the Looks tab). Tiers change bloom, depth of field, shadows and particle rates only. Never gameplay information.
- **Effects**: no screen shake, no strobe. Alarm lights blink at 1 Hz; the HUD flash for an important sound is a single 0.7 s fade. Particles come from one pooled set of ten emitters (`client/Fx/Vfx`): dust on hard landings, glass on the smash, sparks on breakers, lasers and breaches, electric arcs at the substation, gold glints on pickup and payout, smoke on wrecks, plus one rain volume above the camera. Every effect marks a gameplay moment.
- **Signs instead of textures**: all signage is SurfaceGui text (no asset ids), so every label is editable and localisable.
- **Interface**: dark glass panels, sea-glass accents, gold for money, red for alarm. Minimum touch target 44 px; UI scales between 0.78× and 1.2× with the viewport. Nothing persistent on screen that is not about the current moment. Motion is restrained and uniform: buttons dip 4% on press, toasts slide in from above, money and stash pulse once on change (green up, red down), the event banner fades out when nothing is happening.
- **Audio architecture**: nine SoundGroups (Ambience, Weather, City, Vehicles, Police, UI, Interaction, Events, Interiors); server cues can carry a position and play from a pooled emitter with inverse-tapered falloff; weather beds cross-fade; interiors switch the reverb and duck the exterior. Every id is blank until licensed.

## Hero views (polish these first)
1. **Hideout arrival**: neon unit letter over the open bay, accent strip in the crew colour, warm lamp inside, the delivery table in the middle.
2. **Job board**: dark board on the back wall; the UI opens from it.
3. **Museum exterior**: columns, glass façade, "AURORA EXCHANGE" in sea-glass over the entablature; red when the alarm is up.
4. **Main hall and vault**: cases lit from above; the vault glows sea-glass from inside; the Core is a lit cube on a black pedestal.
5. **Lantern Cross**: pink/cyan neon tower and hanging gold lanterns: the getaway intersection and the barricade point.
6. **Rare-car reveal**: not built yet (rare car not integrated).
7. **Results screen**: headline in gold or red, delivered value, payouts, and the story log.

## Not yet
Character and vehicle cosmetics, skyboxes, sound assets (ids blank in `Config.Audio`), custom meshes. All art is built from primitives on purpose so the look can be iterated from code.
