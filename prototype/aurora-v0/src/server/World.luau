local World = {}
local C = {ink = Color3.fromRGB(22, 34, 49), stone = Color3.fromRGB(218, 220, 209), mint = Color3.fromRGB(89, 231, 195), gold = Color3.fromRGB(255, 193, 93), blue = Color3.fromRGB(121, 181, 222), coral = Color3.fromRGB(255, 112, 109)}
local function part(parent, name, size, pos, color, material)
	local p = Instance.new("Part"); p.Name = name; p.Size = size; p.CFrame = CFrame.new(pos)
	p.Anchored = true; p.Color = color or C.stone; p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth; p.Parent = parent
	return p
end
World.part = part

function World.label(p, text, color, height)
	local gui = Instance.new("BillboardGui"); gui.Name = "Label"; gui.Size = UDim2.fromOffset(250, height or 70)
	gui.StudsOffset = Vector3.new(0, p.Size.Y / 2 + 2, 0); gui.MaxDistance = 120; gui.AlwaysOnTop = false; gui.Parent = p
	local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1
	t.Text = text; t.Font = Enum.Font.GothamBold; t.TextSize = 17; t.TextColor3 = color or C.mint
	t.TextStrokeTransparency = 0.25; t.TextWrapped = true; t.Parent = gui
	return t
end

function World.prompt(p, action, title, duration, callback, key)
	local prompt = Instance.new("ProximityPrompt"); prompt.Name = action; prompt.ActionText = action
	prompt.ObjectText = title; prompt.MaxActivationDistance = 11; prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = key or Enum.KeyCode.E; prompt.GamepadKeyCode = key == Enum.KeyCode.F and Enum.KeyCode.ButtonY or Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false; prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = p; prompt.Triggered:Connect(function(player) callback(player, p, duration, prompt) end)
	return prompt
end

function World.build()
	local previous = workspace:FindFirstChild("GlasshouseWorld"); if previous then previous:Destroy() end
	local model = Instance.new("Model"); model.Name = "GlasshouseWorld"; model.Parent = workspace
	local w = {model = model, entrances = {}, nodes = {}, vaults = {}, exits = {}, guards = {}, loot = {}, cars = {}}
	local geometry = Instance.new("Folder"); geometry.Name = "Architecture"; geometry.Parent = model; w.geometry = geometry
	part(geometry, "Midnight sea", Vector3.new(800, 4, 800), Vector3.new(0, -7, -20), Color3.fromRGB(32, 83, 105))
	part(geometry, "Island", Vector3.new(370, 8, 430), Vector3.new(0, -4, -25), Color3.fromRGB(152, 171, 133), Enum.Material.Grass)
	part(geometry, "Quayside road", Vector3.new(34, 0.3, 380), Vector3.new(98, 0.2, -25), C.ink, Enum.Material.Asphalt)
	part(geometry, "Coast road", Vector3.new(260, 0.3, 30), Vector3.new(0, 0.2, -160), C.ink, Enum.Material.Asphalt)
	part(geometry, "Safehouse lane", Vector3.new(250, 0.3, 28), Vector3.new(0, 0.2, 88), C.ink, Enum.Material.Asphalt)
	for z = -185, 140, 25 do part(geometry, "Lane mark", Vector3.new(0.8, 0.1, 10), Vector3.new(98, 0.42, z), C.gold) end
	for x = -120, 120, 25 do part(geometry, "Lane mark", Vector3.new(10, 0.1, 0.8), Vector3.new(x, 0.42, -160), C.gold) end
	-- Roofless gallery for a readable third-person camera. Covers and dividers block drone rays.
	part(geometry, "Gallery plinth", Vector3.new(120, 1, 120), Vector3.new(0, 0, -8), C.stone, Enum.Material.Marble)
	part(geometry, "West wall", Vector3.new(2, 13, 120), Vector3.new(-60, 7, -8), C.ink)
	part(geometry, "East wall", Vector3.new(2, 13, 120), Vector3.new(60, 7, -8), C.ink)
	part(geometry, "North wall", Vector3.new(120, 13, 2), Vector3.new(0, 7, -68), C.ink)
	for _, x in ipairs({-41, 41}) do part(geometry, "Front wall", Vector3.new(38, 13, 2), Vector3.new(x, 7, 52), C.ink) end
	part(geometry, "Front lintel", Vector3.new(44, 3, 2), Vector3.new(0, 12, 52), C.ink)
	local fascia = part(geometry, "Aurora fascia", Vector3.new(65, 2, 2), Vector3.new(0, 16, 53), C.mint, Enum.Material.Neon)
	World.label(fascia, "A U R O R A   E X C H A N G E", C.stone, 40)
	for _, x in ipairs({-38, 38}) do
		for _, z in ipairs({-43, 13}) do
			part(geometry, "Gallery divider", Vector3.new(22, 8, 2), Vector3.new(x, 4.5, z), C.stone)
		end
	end
	for _, x in ipairs({-23, 23}) do
		part(geometry, "Vault wing divider", Vector3.new(2, 8, 30), Vector3.new(x, 4.5, -34), C.stone)
	end
	for _, v in ipairs({Vector3.new(-15, 2, 18), Vector3.new(15, 2, 18), Vector3.new(-14, 2, -10), Vector3.new(15, 2, -10)}) do
		part(geometry, "Exhibit cover", Vector3.new(8, 4, 8), v, C.ink)
		local sculpture = part(geometry, "Light sculpture", Vector3.new(2, 5, 2), v + Vector3.new(0, 4, 0), C.mint, Enum.Material.Neon)
		sculpture.CFrame *= CFrame.Angles(0, math.pi / 4, math.pi / 7)
	end
	for _, x in ipairs({-54, 54}) do
		for z = -55, 40, 19 do
			part(geometry, "Gallery light", Vector3.new(0.5, 0.2, 10), Vector3.new(x, 0.61, z), C.mint, Enum.Material.Neon)
		end
	end
	local entranceSpecs = {
		Exhibit = {Vector3.new(0, 1, 62), Vector3.new(0, 4, 36)},
		Service = {Vector3.new(-42, 1, 62), Vector3.new(-48, 4, -22)},
		Skybridge = {Vector3.new(42, 1, 62), Vector3.new(44, 4, -53)},
	}
	for name, spec in pairs(entranceSpecs) do
		local p = part(model, name .. " entrance", Vector3.new(12, 1, 9), spec[1], C.blue)
		World.label(p, name:upper() .. " ENTRY", C.blue)
		w.entrances[name] = {part = p, destination = spec[2]}
	end
	local positions = {Vector3.new(-48, 2, 30), Vector3.new(48, 2, 30), Vector3.new(-46, 2, -32), Vector3.new(40, 2, -35)}
	for i, pos in ipairs(positions) do
		local p = part(model, "Signal " .. i, Vector3.new(4, 3, 3), pos, C.mint, Enum.Material.Neon)
		World.label(p, "SIGNAL " .. i); w.nodes[i] = p
	end
	w.power = part(model, "Power console", Vector3.new(6, 4, 3), Vector3.new(0, 2.5, -59), C.blue)
	World.label(w.power, "LIGHT GRID", C.blue)
	for name, pos in pairs({West = Vector3.new(-45, 3, -55), North = Vector3.new(0, 3, -36), East = Vector3.new(43, 3, -55)}) do
		local p = part(model, name .. " vault", Vector3.new(10, 5, 7), pos, C.ink, Enum.Material.Metal)
		World.label(p, name:upper() .. " VAULT", C.gold); w.vaults[name] = p
	end
	w.curator = part(model, "Curator", Vector3.new(2, 4, 2), Vector3.new(-36, 3, -6), C.gold)
	part(geometry, "Curator head", Vector3.new(2, 2, 2), Vector3.new(-36, 6, -6), C.stone).Shape = Enum.PartType.Ball
	World.label(w.curator, "CURATOR\nRelease: canal route / Capture: signal + heat", C.gold, 90)
	for i, pos in ipairs({Vector3.new(-45, 2, 2), Vector3.new(42, 2, -10), Vector3.new(8, 2, -52)}) do
		local p = part(model, "Prism cache " .. i, Vector3.new(2, 2, 2), pos, C.gold, Enum.Material.Neon)
		World.label(p, "BONUS PRISM", C.gold); w.loot[i] = p
	end
	local exitSpecs = {Tram = Vector3.new(115, 1, -161), Canal = Vector3.new(-145, 1, -163), Tunnel = Vector3.new(-108, 1, 90)}
	for name, pos in pairs(exitSpecs) do
		local p = part(model, name .. " extraction", Vector3.new(18, 1, 18), pos, C.mint)
		World.label(p, name:upper() .. " EXTRACTION", C.mint); w.exits[name] = p
		part(geometry, name .. " beacon", Vector3.new(1, 20, 1), pos + Vector3.new(9, 10, 0), C.mint, Enum.Material.Neon)
	end
	-- Return gate is physically reachable by every entrance; heist doesn't depend on vehicle physics.
	w.returnGate = part(model, "Getaway gate", Vector3.new(14, 1, 7), Vector3.new(0, 1, 43), C.gold)
	World.label(w.returnGate, "TO GETAWAY CAR / COAST ROAD", C.gold)
	w.spawn = Vector3.new(0, 4, 124); w.recovery = Vector3.new(-36, 4, 124)
	part(geometry, "Crew safehouse", Vector3.new(85, 1, 32), Vector3.new(-10, 0.5, 127), C.ink)
	w.board = part(model, "Contract board", Vector3.new(12, 7, 1), Vector3.new(0, 5, 140), C.ink)
	World.label(w.board, "BLACKOUT BAY\n1-5 PLAYERS · ALL TOOLS INCLUDED", C.mint, 85)
	w.recoveryPad = part(model, "Recovery", Vector3.new(10, 1, 10), Vector3.new(-36, 1, 124), C.coral)
	World.label(w.recoveryPad, "RECOVERY / FREE RE-ENTRY", C.coral)
	w.decorPads = {}
	for i = 1, 5 do
		local p = part(model, "Crew display " .. i, Vector3.new(5, 1, 5), Vector3.new(-40 + i * 14, 1, 138), C.blue)
		w.decorPads[i] = p
	end
	for _, spec in ipairs({{-120, -90, 28}, {-110, 0, 35}, {140, -90, 32}, {145, 30, 25}, {-70, 160, 18}}) do
		part(geometry, "Coastal building", Vector3.new(25, spec[3], 24), Vector3.new(spec[1], spec[3]/2, spec[2]), C.ink)
		part(geometry, "Warm windows", Vector3.new(25.2, 2, 24.2), Vector3.new(spec[1], spec[3]-6, spec[2]), C.gold, Enum.Material.Neon)
	end
	for _, spec in ipairs({{-150, 130}, {135, 140}, {-140, -200}, {150, -205}, {-90, -95}}) do
		part(geometry, "Palm trunk", Vector3.new(2, 16, 2), Vector3.new(spec[1], 8, spec[2]), C.gold)
		for a = 0, 3 do
			local leaf = part(geometry, "Palm leaf", Vector3.new(17, 1, 4), Vector3.new(spec[1], 16, spec[2]), Color3.fromRGB(66, 123, 113))
			leaf.CFrame *= CFrame.Angles(0, a * math.pi / 4, 0.1)
		end
	end
	local spawn = Instance.new("SpawnLocation"); spawn.Name = "CrewSpawn"; spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 1, 124); spawn.Anchored = true; spawn.Transparency = 1; spawn.CanCollide = false
	spawn.Neutral = true; spawn.Duration = 0; spawn.Parent = model
	w.spawnLocation = spawn
	return w
end

function World.makeCore(w, position)
	if w.core then w.core:Destroy() end
	w.core = part(w.model, "Aurora core", Vector3.new(2.5, 3, 2.5), position, C.mint, Enum.Material.Neon)
	w.core.CanCollide = false; World.label(w.core, "AURORA CORE", C.mint)
	return w.core
end

function World.makeGuards(w, count, offset)
	local paths = {
		{Vector3.new(-28, 4, 26), Vector3.new(27, 4, 26), Vector3.new(27, 4, 0), Vector3.new(-28, 4, 0)},
		{Vector3.new(-50, 4, -16), Vector3.new(-30, 4, -16), Vector3.new(-30, 4, -36), Vector3.new(-50, 4, -36)},
		{Vector3.new(30, 4, -18), Vector3.new(50, 4, -18), Vector3.new(50, 4, -39), Vector3.new(30, 4, -39)},
		{Vector3.new(-16, 4, -28), Vector3.new(16, 4, -28), Vector3.new(16, 4, -56), Vector3.new(-16, 4, -56)},
	}
	for i = 1, count do
		local path = paths[i]; local start = ((offset + i) % 4) + 1
		local p = part(w.model, "Security drone " .. i, Vector3.new(3, 2, 3), path[start], C.coral, Enum.Material.Metal)
		p.CanCollide = false; World.label(p, "PATROL / STASIS", C.coral, 40)
		local light = Instance.new("SpotLight"); light.Face = Enum.NormalId.Front; light.Color = C.coral
		light.Range = 28; light.Angle = 80; light.Brightness = 3; light.Parent = p
		local beam = part(w.model, "Patrol direction " .. i, Vector3.new(0.22, 0.12, 18), path[start], C.coral, Enum.Material.Neon)
		beam.CanCollide = false; beam.CanQuery = false; beam.Transparency = 0.25
		table.insert(w.guards, {part = p, beam = beam, path = path, target = start % 4 + 1, frozenUntil = 0})
	end
end

function World.makeCar(w)
	local model = Instance.new("Model"); model.Name = "Crew getaway car"; model.Parent = w.model
	local origin = CFrame.new(70, 3, 87) * CFrame.Angles(0, math.pi/2, 0)
	local chassis = part(model, "Chassis", Vector3.new(7, 1.5, 12), Vector3.zero, C.gold, Enum.Material.Metal)
	chassis.CFrame = origin; chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0.1, 0, 1, 1)
	local function weld(p, localFrame)
		p.Anchored = false; p.Massless = true; p.CFrame = origin * localFrame
		local joint = Instance.new("WeldConstraint"); joint.Part0 = chassis; joint.Part1 = p; joint.Parent = p
	end
	local driver
	for i = 1, 5 do
		local seat = Instance.new(i == 1 and "VehicleSeat" or "Seat"); seat.Name = i == 1 and "Driver" or "Passenger " .. i
		seat.Size = Vector3.new(2, 1, 2); seat.Color = C.ink; seat.Parent = model
		local x = i == 1 and -1.7 or (i % 2 == 0 and 1.7 or -1.7)
		local z = i == 1 and -3 or (i <= 3 and 0 or 3)
		weld(seat, CFrame.new(x, 1.1, z)); if i == 1 then driver = seat; seat.HeadsUpDisplay = true end
	end
	for _, x in ipairs({-3.6, 3.6}) do
		for _, z in ipairs({-3.8, 3.8}) do
			local wheel = part(model, "Wheel", Vector3.new(1, 2.8, 2.8), Vector3.zero, C.ink)
			wheel.Shape = Enum.PartType.Cylinder; wheel.CanCollide = false
			weld(wheel, CFrame.new(x, -0.2, z))
		end
	end
	local nose = part(model, "Nose", Vector3.new(7, 1, 2), Vector3.zero, C.gold); weld(nose, CFrame.new(0, 1, -5))
	World.label(nose, "CREW GETAWAY\n5 seats · drive or walk to extraction", C.gold, 75)
	model.PrimaryPart = chassis; chassis.Anchored = false; chassis:SetNetworkOwner(nil)
	local attach = Instance.new("Attachment"); attach.Parent = chassis
	local upright = Instance.new("AlignOrientation"); upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = attach; upright.MaxTorque = 1000000; upright.Responsiveness = 12; upright.Parent = chassis
	local car = {model = model, chassis = chassis, seat = driver, upright = upright, yaw = math.pi/2, origin = origin}
	table.insert(w.cars, car)
	return car
end

World.colors = C
return World
