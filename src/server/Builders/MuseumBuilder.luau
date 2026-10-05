--!nonstrict
-- The Aurora Exchange: the first heist location. Three ways in (front doors, loading dock, roof skylight),
-- a vault with two readers and a drill point, a security office with the dock code and the camera switch,
-- a junction box in the alley, guards, cameras, shutters and alarm lights. All coordinates are local to
-- the museum centre (+lz is the front/south). Returns references for SecurityService/MissionService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Builder = require(script.Parent.Builder)

local MuseumBuilder = {}

local M = Blueprint.Museum
local HALF_W, HALF_D, H = M.w / 2, M.d / 2, M.h
local WALL = 1.5

local function W(lx: number, lz: number): (number, number)
	return M.x + lx, M.z + lz
end

local function wcf(lx: number, y: number, lz: number, yaw: number?): CFrame
	local x, z = W(lx, lz)
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- Wall segment along X at local lz from lx1..lx2 (bottom y0, height h)
local function wallX(parent, lx1, lx2, lz, y0, h, props)
	local x, z = W((lx1 + lx2) / 2, lz)
	return Builder.box(parent, x, y0, z, math.abs(lx2 - lx1), h, WALL, props)
end
-- Wall segment along Z at local lx from lz1..lz2
local function wallZ(parent, lx, lz1, lz2, y0, h, props)
	local x, z = W(lx, (lz1 + lz2) / 2)
	return Builder.box(parent, x, y0, z, WALL, h, math.abs(lz2 - lz1), props)
end

local function displayCase(parent, id, lx, lz)
	local m = Builder.model(parent, "Case_" .. id)
	local x, z = W(lx, lz)
	local plinth = Builder.box(m, x, 1, z, 4.5, 3, 4.5, { name = "Plinth", material = Enum.Material.Marble, color = Palette.WarmStone })
	local glass = Builder.box(m, x, 4, z, 4.5, 4, 4.5, { name = "Glass", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.55 })
	glass.Reflectance = 0.2
	local spot = Builder.box(m, x, 9.5, z, 1.5, 0.5, 1.5, { name = "CaseLamp", material = Enum.Material.Neon, color = Palette.WarmInterior, canCollide = false })
	Builder.spotLight(spot, Palette.WarmInterior, 2, 14, 60, Enum.NormalId.Bottom)
	m:SetAttribute("CaseId", id)
	return { id = id, model = m, plinth = plinth, glass = glass, cframe = CFrame.new(x, 5.2, z) }
end

function MuseumBuilder.build(root: Folder)
	local museum = Builder.model(root, "AuroraExchange")
	local shell = { name = "Wall", material = Enum.Material.Concrete, color = Palette.PaleStone }
	local inner = { name = "Partition", material = Enum.Material.Concrete, color = Palette.WarmStone }
	local refs = { cases = {}, cameras = {}, alarmLights = {}, guardRoutes = {}, exits = {} }

	-- Floor and roof (roof has a central skylight opening and a NE hatch for the mezzanine ladder)
	do
		local x, z = W(0, 0)
		Builder.box(museum, x, 0, z, M.w, 1, M.d, { name = "Floor", material = Enum.Material.Marble, color = Palette.PaleStone })
		local roof = { name = "Roof", material = Enum.Material.Concrete, color = Palette.Industrial }
		local roofY = H
		-- North strip in three pieces around the hatch (lx 60..70, lz -52..-44)
		Builder.box(museum, x, roofY, M.z - 76, M.w, 1.5, 48, roof) -- lz -100..-52
		Builder.box(museum, M.x - 30, roofY, M.z - 48, 180, 1.5, 8, roof) -- lx -120..60, lz -52..-44
		Builder.box(museum, M.x + 95, roofY, M.z - 48, 50, 1.5, 8, roof) -- lx 70..120
		Builder.box(museum, x, roofY, M.z - 30, M.w, 1.5, 28, roof) -- lz -44..-16
		Builder.box(museum, x, roofY, M.z + 58, M.w, 1.5, 84, roof) -- lz 16..100
		Builder.box(museum, M.x - 68, roofY, z, 104, 1.5, 32, roof) -- lx -120..-16, lz -16..16
		Builder.box(museum, M.x + 68, roofY, z, 104, 1.5, 32, roof) -- lx 16..120
		-- Skylight frame (open: the glass has been propped up for maintenance)
		local frame = { name = "SkylightFrame", material = Enum.Material.Metal, color = Palette.Industrial }
		Builder.box(museum, x, roofY + 1.5, M.z - 16.5, 34, 2, 1, frame)
		Builder.box(museum, x, roofY + 1.5, M.z + 16.5, 34, 2, 1, frame)
		Builder.box(museum, M.x - 16.5, roofY + 1.5, z, 1, 2, 32, frame)
		Builder.box(museum, M.x + 16.5, roofY + 1.5, z, 1, 2, 32, frame)
		local pane = Builder.part(museum, CFrame.new(x, roofY + 6, M.z - 8) * CFrame.Angles(math.rad(-60), 0, 0), Vector3.new(30, 0.4, 30), { name = "SkylightPane", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.5, canCollide = false })
		pane.Reflectance = 0.2
		refs.skylight = CFrame.new(x, roofY + 2, z)
		-- Roof parapet
		local par = { name = "RoofParapet", material = Enum.Material.Concrete, color = Palette.Industrial }
		Builder.box(museum, x, roofY + 1.5, M.z - HALF_D + 0.5, M.w, 2, 1, par)
		Builder.box(museum, x, roofY + 1.5, M.z + HALF_D - 0.5, M.w, 2, 1, par)
		Builder.box(museum, M.x - HALF_W + 0.5, roofY + 1.5, z, 1, 2, M.d, par)
		Builder.box(museum, M.x + HALF_W - 0.5, roofY + 1.5, z, 1, 2, M.d, par)
		refs.roofY = roofY + 1.5
	end

	-- Outer walls
	wallZ(museum, -HALF_W + WALL / 2, -HALF_D, HALF_D, 0, H, shell) -- west
	wallZ(museum, HALF_W - WALL / 2, -HALF_D, HALF_D, 0, H, shell) -- east
	-- north wall with the dock door gap (lx -100..-90)
	wallX(museum, -HALF_W, -100, -HALF_D + WALL / 2, 0, H, shell)
	wallX(museum, -90, HALF_W, -HALF_D + WALL / 2, 0, H, shell)
	wallX(museum, -100, -90, -HALF_D + WALL / 2, 10, H - 10, shell)
	-- south (front) wall with the door gap (lx -10..10) and glass panels either side
	wallX(museum, -HALF_W, -60, HALF_D - WALL / 2, 0, H, shell)
	wallX(museum, 60, HALF_W, HALF_D - WALL / 2, 0, H, shell)
	wallX(museum, -10, 10, HALF_D - WALL / 2, 12, H - 12, shell)
	local glassProps = { name = "FacadeGlass", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.35 }
	wallX(museum, -60, -10, HALF_D - WALL / 2, 0, H, glassProps).Reflectance = 0.25
	wallX(museum, 10, 60, HALF_D - WALL / 2, 0, H, glassProps).Reflectance = 0.25
	-- Front columns, sign and steps
	for i = -3, 3 do
		if i ~= 0 then
			local x, z = W(i * 22, HALF_D + 5)
			Builder.box(museum, x, 1, z, 3, H + 2, 3, { name = "Column", material = Enum.Material.Marble, color = Palette.PaleStone })
		end
	end
	do
		local x, z = W(0, HALF_D + 5)
		Builder.box(museum, x, H + 2, z, 150, 3, 4, { name = "Entablature", material = Enum.Material.Marble, color = Palette.PaleStone })
		Builder.neonSign(museum, CFrame.new(x, H + 8, z + 1) * CFrame.Angles(0, math.rad(180), 0), Vector3.new(90, 8, 1), "AURORA EXCHANGE", Palette.SeaGlass).Name = "MuseumSign"
		refs.sign = museum:FindFirstChild("MuseumSign")
	end

	-- Front doors (locked glass) and the lockdown shutter
	do
		local x, z = W(0, HALF_D - 0.75)
		local doorL = Builder.box(museum, x - 5, 1, z, 9.6, 11, 0.6, { name = "FrontDoorL", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.3 })
		local doorR = Builder.box(museum, x + 5, 1, z, 9.6, 11, 0.6, { name = "FrontDoorR", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.3 })
		local shutter = Builder.box(museum, x, 1, z + 2.5, 22, 11.5, 1, { name = "FrontShutter", material = Enum.Material.DiamondPlate, color = Palette.Industrial, transparency = 1, canCollide = false })
		Builder.label(shutter, "LOCKDOWN", Enum.NormalId.Front, Palette.SecurityRed)
		Builder.label(shutter, "LOCKDOWN", Enum.NormalId.Back, Palette.SecurityRed)
		refs.frontDoors = { doorL, doorR }
		refs.frontShutter = shutter
		refs.exits.front = CFrame.new(x, 3, z + 12)
	end

	-- Loading dock door (keypad outside, release button inside)
	do
		local x, z = W(-95, -HALF_D + 0.75)
		local door = Builder.box(museum, x, 1, z, 9.6, 9.6, 1, { name = "DockDoor", material = Enum.Material.Metal, color = Palette.Rust })
		Builder.label(door, "AURORA EXCHANGE — DELIVERIES", Enum.NormalId.Front, Palette.PaleStone)
		local keypad = Builder.box(museum, x + 7, 4, z - 1.2, 1.5, 2, 0.6, { name = "DockKeypad", material = Enum.Material.SmoothPlastic, color = Palette.Night })
		Builder.label(keypad, "KEYPAD", Enum.NormalId.Front, Palette.SeaGlass)
		local release = Builder.box(museum, x + 7, 4, z + 1.2, 1.5, 2, 0.6, { name = "DockRelease", material = Enum.Material.SmoothPlastic, color = Palette.SecurityAmber })
		Builder.label(release, "DOOR RELEASE", Enum.NormalId.Back, Palette.Night)
		refs.dockDoor = door
		refs.dockKeypad = keypad
		refs.dockRelease = release
		refs.exits.dock = CFrame.new(x, 3, z - 12)
		-- Dock interior: a roller platform and crates for cover
		local dx, dz = W(-95, -80)
		Builder.box(museum, dx, 1, dz, 30, 2, 10, { name = "DockPlatform", material = Enum.Material.Concrete, color = Palette.Industrial })
		Builder.box(museum, dx - 8, 3, dz, 5, 5, 5, { name = "Crate", material = Enum.Material.WoodPlanks, color = Palette.WarmWood })
		Builder.box(museum, dx + 6, 3, dz + 1, 6, 4, 4, { name = "Crate", material = Enum.Material.WoodPlanks, color = Palette.WarmWood })
	end

	-- Alley behind the museum: asphalt, bins, junction box, a lamp
	do
		local x, z = W(0, -HALF_D - 27)
		Builder.box(museum, x, 0, z, M.w + 40, 1, 52, { name = "AlleyFloor", material = Enum.Material.Asphalt, color = Palette.DarkAsphalt })
		for _, lx in ipairs({ -70, -30, 30 }) do
			local bx, bz = W(lx, -HALF_D - 5)
			Builder.box(museum, bx, 1, bz, 7, 5, 4, { name = "Bin", material = Enum.Material.Metal, color = Palette.SeaGlassDeep })
		end
		local jx, jz = W(-50, -HALF_D - 1.5)
		local junction = Builder.box(museum, jx, 3, jz, 3, 4, 1.5, { name = "JunctionBox", material = Enum.Material.Metal, color = Palette.Industrial })
		Builder.label(junction, "DANGER\nHIGH VOLTAGE", Enum.NormalId.Front, Palette.SecurityAmber)
		refs.junctionBox = junction
		local lx2, lz2 = W(-95, -HALF_D - 12)
		local pole = Builder.box(museum, lx2, 1, lz2, 0.8, 12, 0.8, { name = "AlleyLampPole", material = Enum.Material.Metal, color = Palette.Industrial })
		pole.CastShadow = false
		local head = Builder.box(museum, lx2, 13, lz2, 2, 0.8, 2, { name = "AlleyLampHead", material = Enum.Material.Neon, color = Palette.SecurityAmber, canCollide = false })
		Builder.pointLight(head, Palette.SecurityAmber, 1, 26)
	end

	-- Interior partitions
	-- Lobby/hall arch at lz = 60 (gap lx -30..30); wing doors at lx ±95 (gap 12)
	wallX(museum, -70, -30, 60, 0, H, inner)
	wallX(museum, 30, 70, 60, 0, H, inner)
	wallX(museum, -30, 30, 60, 14, H - 14, inner)
	wallX(museum, -HALF_W, -101, 60, 0, H, inner)
	wallX(museum, -89, -70, 60, 0, H, inner)
	wallX(museum, 70, 89, 60, 0, H, inner)
	wallX(museum, 101, HALF_W, 60, 0, H, inner)
	-- Hall/wing walls at lx = ±70 from lz -60..60 with two doorways each (lz -10..4 and 36..50)
	for _, s in ipairs({ -1, 1 }) do
		wallZ(museum, s * 70, -60, -10, 0, H, inner)
		wallZ(museum, s * 70, 4, 36, 0, H, inner)
		wallZ(museum, s * 70, 50, 60, 0, H, inner)
		wallZ(museum, s * 70, -10, 4, 12, H - 12, inner)
		wallZ(museum, s * 70, 36, 50, 12, H - 12, inner)
	end
	-- Vault block lx -40..40, lz -100..-50; door gap lx -8..8 at lz -50
	wallZ(museum, -40, -100, -50, 0, H, inner)
	wallZ(museum, 40, -100, -50, 0, H, inner)
	wallX(museum, -40, -8, -50, 0, H, inner)
	wallX(museum, 8, 40, -50, 0, H, inner)
	wallX(museum, -8, 8, -50, 11, H - 11, inner)
	-- Security office lx 70..120, lz -100..-60 (door gap lx 85..95 on lz -60)
	wallZ(museum, 70, -100, -60, 0, H, inner)
	wallX(museum, 70, 85, -60, 0, H, inner)
	wallX(museum, 95, 120, -60, 0, H, inner)
	wallX(museum, 85, 95, -60, 10, H - 10, inner)
	-- Loading dock lx -120..-70, lz -100..-60 (door gap lx -95..-85 on lz -60)
	wallZ(museum, -70, -100, -60, 0, H, inner)
	wallX(museum, -120, -95, -60, 0, H, inner)
	wallX(museum, -85, -70, -60, 0, H, inner)
	wallX(museum, -95, -85, -60, 10, H - 10, inner)
	-- Wing north walls at lz -60 from lx ±70..±120 are the office/dock south walls (already built)

	-- Mezzanine: a ring at y = 12 around the hall with a stair down the west side and a ladder up to the roof hatch
	do
		local mz = { name = "Mezzanine", material = Enum.Material.Concrete, color = Palette.WarmStone }
		local rail = { name = "Rail", material = Enum.Material.Metal, color = Palette.SeaGlassDeep, canCollide = false }
		local x, z
		x, z = W(0, -45); Builder.box(museum, x, 12, z, 140, 1, 10, mz); Builder.box(museum, x, 13, z + 5, 140, 3, 0.4, rail)
		x, z = W(-65, 5); Builder.box(museum, x, 12, z, 10, 1, 110, mz); Builder.box(museum, x + 5, 13, z, 0.4, 3, 110, rail)
		x, z = W(65, 5); Builder.box(museum, x, 12, z, 10, 1, 110, mz); Builder.box(museum, x - 5, 13, z, 0.4, 3, 110, rail)
		-- Stairs: wedge from the west walkway (lz 60) down to the floor at lz 20, 10 wide, rising toward -Z
		x, z = W(-55, 40)
		Builder.wedge(museum, CFrame.new(x, 6.5, z) * CFrame.Angles(0, math.rad(180), 0), Vector3.new(10, 11, 40), { name = "Stairs", material = Enum.Material.Concrete, color = Palette.WarmStone })
		-- Ladder from the north walkway up through the roof hatch
		x, z = W(65, -48)
		Builder.truss(museum, CFrame.new(x, 13 + (H + 1.5 - 13) / 2, z), H + 1.5 - 13 + 2, "HatchLadder")
		refs.exits.roof = CFrame.new(x, H + 3, z)
	end

	-- Vault door, readers and drill point
	do
		local x, z = W(0, -50)
		local door = Builder.box(museum, x, 1, z, 15.5, 10, 2.2, { name = "VaultDoor", material = Enum.Material.Metal, color = Palette.Industrial })
		door.Reflectance = 0.15
		Builder.label(door, "AURORA VAULT", Enum.NormalId.Front, Palette.SeaGlass)
		local readerA = Builder.box(museum, x - 11, 4.5, z + 1.2, 1.2, 1.8, 0.5, { name = "ReaderA", material = Enum.Material.SmoothPlastic, color = Palette.Night })
		local readerB = Builder.box(museum, x + 11, 4.5, z + 1.2, 1.2, 1.8, 0.5, { name = "ReaderB", material = Enum.Material.SmoothPlastic, color = Palette.Night })
		Builder.label(readerA, "A", Enum.NormalId.Front, Palette.SecurityRed)
		Builder.label(readerB, "B", Enum.NormalId.Front, Palette.SecurityRed)
		local drill = Builder.box(museum, x + 6, 3.5, z + 1.4, 1.5, 1.5, 0.6, { name = "DrillPoint", material = Enum.Material.Metal, color = Palette.SecurityAmber })
		refs.vaultDoor = door
		refs.readers = { readerA, readerB }
		refs.drillPoint = drill
		-- Inside the vault: the Core pedestal and two cases; sea-glass accent light
		local px, pz = W(0, -80)
		local pedestal = Builder.box(museum, px, 1, pz, 6, 3, 6, { name = "CorePedestal", material = Enum.Material.Marble, color = Palette.Night })
		pedestal.Reflectance = 0.1
		refs.corePedestal = { model = pedestal, cframe = CFrame.new(px, 5.6, pz) }
		local glow = Builder.box(museum, px, H - 2, pz, 10, 0.5, 10, { name = "VaultLight", material = Enum.Material.Neon, color = Palette.SeaGlass, canCollide = false })
		Builder.pointLight(glow, Palette.SeaGlass, 2, 40)
	end

	-- Display cases: hall (4), wings (4), vault (2)
	local caseSpecs = {
		{ "hall1", -35, -25, "Hall" }, { "hall2", 35, -25, "Hall" }, { "hall3", -35, 25, "Hall" }, { "hall4", 35, 25, "Hall" },
		{ "east1", 95, -30, "Wing" }, { "east2", 95, 20, "Wing" }, { "west1", -95, -30, "Wing" }, { "west2", -95, 20, "Wing" },
		{ "vault1", -25, -70, "Vault" }, { "vault2", 25, -70, "Vault" },
	}
	for _, c in ipairs(caseSpecs) do
		local case = displayCase(museum, c[1], c[2], c[3])
		case.zone = c[4]
		table.insert(refs.cases, case)
	end

	-- Security office: desk, code board, camera switch, keycard spot
	do
		local x, z = W(95, -82)
		local desk = Builder.box(museum, x, 1, z, 12, 3.5, 5, { name = "OfficeDesk", material = Enum.Material.Wood, color = Palette.WarmWood })
		refs.officeCardSpot = CFrame.new(x - 3, 5, z)
		local bx, bz = W(118.6, -80)
		local board = Builder.box(museum, bx, 5, bz, 0.6, 7, 14, { name = "CodeBoard", material = Enum.Material.SmoothPlastic, color = Palette.PaleStone })
		refs.codeBoard = board
		local sx, sz = W(118.6, -66)
		local switch = Builder.box(museum, sx, 5, sz, 0.6, 2.5, 2.5, { name = "CameraSwitch", material = Enum.Material.Metal, color = Palette.SecurityRed })
		Builder.label(switch, "CCTV MAIN", Enum.NormalId.Left, Palette.PaleStone)
		refs.cameraSwitch = switch
		local monitors = Builder.box(museum, x, 4.5, z - 1.5, 10, 2.5, 0.5, { name = "Monitors", material = Enum.Material.Neon, color = Palette.PoliceLight, canCollide = false })
		Builder.pointLight(monitors, Palette.PoliceLight, 0.8, 12)
		local _ = desk
	end

	-- Cameras (box + lens light). Yaw 0 looks north (-Z); LookVector = (-sin yaw, 0, -cos yaw).
	local camSpecs = {
		{ "Lobby", 0, 97, 0 }, -- on the front wall looking north into the lobby
		{ "Hall", -66, -46, -135 }, -- NW corner of the hall looking south-east
		{ "EastWing", 117, 0, 90 }, -- east wall looking west
		{ "VaultCorridor", 0, -98, 180 }, -- north wall looking south at the vault door
	}
	for _, c in ipairs(camSpecs) do
		local cf = wcf(c[2], 20, c[3], c[4])
		local body = Builder.part(museum, cf, Vector3.new(1.4, 1.4, 3), { name = "Camera_" .. c[1], material = Enum.Material.Metal, color = Palette.Industrial, canCollide = false })
		local lens = Builder.part(museum, cf * CFrame.new(0, 0, -1.6), Vector3.new(0.6, 0.6, 0.3), { name = "Lens", material = Enum.Material.Neon, color = Palette.SecurityRed, canCollide = false })
		lens.Parent = body
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = lens
		weld.Parent = body
		table.insert(refs.cameras, { id = c[1], label = c[1] .. " camera", part = body, lens = lens, baseCFrame = cf })
	end

	-- Alarm lights
	for _, spec in ipairs({ { -60, 95 }, { 60, 95 }, { -60, -45 }, { 60, -45 }, { 110, 55 }, { -110, 55 } }) do
		local x, z = W(spec[1], spec[2])
		local l = Builder.box(museum, x, 21, z, 2, 1, 2, { name = "AlarmLight", material = Enum.Material.Neon, color = Palette.Night, canCollide = false })
		local pl = Builder.pointLight(l, Palette.SecurityRed, 0, 40)
		table.insert(refs.alarmLights, { part = l, light = pl })
	end

	-- Interior lighting: warm ceiling lights across public spaces
	for _, spec in ipairs({ { 0, 80 }, { -40, 10 }, { 40, 10 }, { 0, -30 }, { 95, -5 }, { -95, -5 }, { 55, -78 }, { -55, -78 } }) do
		local x, z = W(spec[1], spec[2])
		local l = Builder.box(museum, x, H - 2, z, 8, 0.5, 8, { name = "CeilingLight", material = Enum.Material.Neon, color = Palette.WarmInterior, canCollide = false })
		Builder.pointLight(l, Palette.WarmInterior, 1.1, 48)
	end
	-- Battery exit lamps for blackouts (amber, only on while the grid is down)
	for _, spec in ipairs({ { 0, 60 }, { 0, -20 }, { 80, 20 }, { -80, 20 } }) do
		local x, z = W(spec[1], spec[2])
		Builder.emergencyLight(museum, x, H - 3, z)
	end
	do
		local x, z = W(0, 80)
		local desk = Builder.box(museum, x, 1, z, 20, 3.5, 4, { name = "Reception", material = Enum.Material.Wood, color = Palette.WarmWood })
		Builder.label(desk, "WELCOME TO THE AURORA EXCHANGE", Enum.NormalId.Front, Palette.PaleStone)
	end

	-- Guard routes in world space. Each waypoint: { cf, pause }. The office guard loops out of the office.
	local function route(points)
		local out = {}
		for _, p in ipairs(points) do
			table.insert(out, { position = Vector3.new(M.x + p[1], 3, M.z + p[2]), pause = p[3] or 0 })
		end
		return out
	end
	-- Routes only cross walls at doorways: hall arch lx -30..30 @ lz 60; wing doors lz -10..4 and 36..50 @ lx ±70;
	-- office door lx 85..95 @ lz -60; dock door lx -95..-85 @ lz -60; vault pockets open to the hall at lz -50.
	refs.guardRoutes = {
		{ id = "Lobby", label = "Lobby Guard", points = route({ { -40, 82, 3 }, { 40, 82, 3 }, { 20, 66, 0 }, { 40, 30, 2 }, { -40, 30, 2 }, { -20, 66, 0 } }) },
		{ id = "East", label = "Gallery Guard", points = route({ { 95, 40, 3 }, { 95, -40, 2 }, { 90, -62, 0 }, { 95, -80, 14 }, { 90, -62, 0 }, { 95, -40, 1 } }) },
		{ id = "West", label = "West Wing Guard", points = route({ { -95, 40, 2 }, { -95, -40, 2 }, { -90, -62, 0 }, { -95, -80, 6 }, { -90, -62, 0 }, { -95, -40, 1 }, { -95, 40, 1 }, { -75, 43, 0 }, { -58, 43, 1 }, { -58, -3, 2 }, { -75, -3, 0 } }) },
		{ id = "Captain", label = "Security Captain", points = route({ { -55, -60, 1 }, { -55, -95, 3 }, { -55, -60, 0 }, { -55, -44, 0 }, { -20, -38, 0 }, { 0, -38, 6 }, { 20, -38, 0 }, { 55, -44, 0 }, { 55, -60, 0 }, { 55, -95, 3 }, { 55, -60, 0 }, { 55, -44, 0 }, { 0, -38, 2 } }), carriesCard = "CaptainCard" },
	}

	-- Bounds for "inside the museum" tests (world space)
	refs.bounds = { minX = M.x - HALF_W, maxX = M.x + HALF_W, minZ = M.z - HALF_D, maxZ = M.z + HALF_D, maxY = H }
	refs.model = museum
	return refs
end

return MuseumBuilder
