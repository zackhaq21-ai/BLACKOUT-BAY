# GLASSHOUSE — Art Direction

A stylized coastal city at dusk. Pale stone, dark asphalt, sea-glass accents, warm interiors, an industrial waterfront, and restrained security lighting. Everything is readable at a glance: wealth glows gold, danger glows red, police glow blue.

## Rules
- **Palette** lives in `src/shared/Palette.luau`. No new colours without adding them there.
  - Pale stone / warm stone for civic buildings; dark asphalt roads with pale dashes; sea-glass for the museum, water, and "value"; warm amber for interiors and lamps; rust and grey for the harbour; security red only for alarms and lockdown; police blue only for police.
- **Materials**: Concrete and Marble for stone; Asphalt for roads; Glass with slight reflectance for the museum façade and towers; Metal / DiamondPlate for the harbour and gantries; Neon only for signs, lamps, alarm lights and lit windows.
- **Silhouettes**: every building has a plinth and a parapet line; heights vary per block so the skyline reads from the overpass. The museum is the only sea-glass building: you can find it from anywhere.
- **Lighting**: ClockTime 19.6, dense blue-grey atmosphere, warm point lights inside, cool floods on the plaza, amber on the harbour and the parking deck route. Lighting is mood, never a gameplay fog: fog starts at 400 studs.
- **Effects**: no screen shake, no strobe. Alarm lights blink at 1 Hz; the HUD flash for an important sound is a single 0.7 s fade. Smoke on wrecked cars is the only particle effect.
- **Signs instead of textures**: all signage is SurfaceGui text (no asset ids), so every label is editable and localisable.
- **Interface**: dark glass panels, sea-glass accents, gold for money, red for alarm. Minimum touch target 44 px; UI scales between 0.78× and 1.2× with the viewport. Nothing persistent on screen that is not about the current moment.

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
