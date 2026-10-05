--!nonstrict
-- Builds Glasshouse Island from MapBlueprint: land, water, roads, buildings, landmarks, police station,
-- parking deck. Returns references the gameplay services need.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Builder = require(script.Parent.Builder)

local IslandBuilder = {}

local STYLE = {
	Stone = { material = Enum.Material.Limestone, color = Palette.PaleStone, window = Palette.WarmInterior }, -- pale civic stone, distinct from concrete plinths
	Warm = { material = Enum.Material.Brick, color = Palette.WarmStone, window = Palette.WarmInterior },
	Industrial = { material = Enum.Material.CorrodedMetal, color = Palette.Industrial, window = Palette.SeaGlass }, -- weathered steel, distinct from painted vehicle metal
	Glass = { material = Enum.Material.Glass, color = Palette.Glass, window = Palette.SeaGlass },
	Brick = { material = Enum.Material.Brick, color = Palette.Rust, window = Palette.WarmInterior },
	Yard = { material = Enum.Material.Concrete, color = Palette.DarkAsphalt, window = Palette.SeaGlass },
}

local function buildLand(root: Folder)
	local I = Blueprint.Island
	local C = Blueprint.Canal
	local land = Builder.folder(root, "Land")
	local depth = 20
	local props = { name = "Ground", material = Enum.Material.Slate, color = Palette.PaleStone }
	-- West of the canal
	local cx1, cx2 = C.x - C.width / 2, C.x + C.width / 2
	Builder.box(land, (I.minX + cx1) / 2, -depth, 0, cx1 - I.minX, depth, I.maxZ - I.minZ, props)
	-- East of the canal
	Builder.box(land, (cx2 + I.maxX) / 2, -depth, 0, I.maxX - cx2, depth, I.maxZ - I.minZ, props)
	-- South end cap (the canal ends at Dockside, land continues south)
	Builder.box(land, C.x, -depth, (C.toZ + I.maxZ) / 2, C.width, depth, I.maxZ - C.toZ, props)
	-- Canal bed and walls
	Builder.box(land, C.x, -depth, (C.fromZ + C.toZ) / 2, C.width, depth - 8, C.toZ - C.fromZ, { name = "CanalBed", material = Enum.Material.Slate, color = Palette.Industrial })
	-- Beach rim just under the waterline
	Builder.box(land, 0, -4, 0, (I.maxX - I.minX) + 60, 3.2, (I.maxZ - I.minZ) + 60, { name = "Shoal", material = Enum.Material.Sand, color = Palette.Sand })
	-- Sea
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(0, -24, 0), Vector3.new(3200, 43, 3200), Enum.Material.Water)
end

local function roadRect(r)
	local f, t = r.from, r.to
	local cx, cz = (f.x + t.x) / 2, (f.z + t.z) / 2
	local w = if f.x == t.x then r.width else math.abs(t.x - f.x) + r.width
	local d = if f.z == t.z then r.width else math.abs(t.z - f.z) + r.width
	return cx, cz, w, d, f.x == t.x
end

local function buildRoads(root: Folder)
	local roads = Builder.folder(root, "Roads")
	local lamps = Builder.folder(root, "Lamps")
	local rng = Builder.rng(7)
	for _, r in ipairs(Blueprint.Roads) do
		local cx, cz, w, d, ns = roadRect(r)
		if r.elevated then
			-- Seawall Overpass: ramps at both ends, flat deck between, pillars below.
			local y = 12
			local rampLen = 48
			local x1, x2 = r.from.x, r.to.x
			Builder.box(roads, (x1 + rampLen + x2 - rampLen) / 2, y, cz, (x2 - x1) - 2 * rampLen, 1.5, r.width, { name = "OverpassDeck", material = Enum.Material.Asphalt, color = Palette.DarkAsphalt })
			Builder.wedge(roads, CFrame.new(x1 + rampLen / 2, y / 2 + 0.75, cz) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(r.width, y + 1.5, rampLen), { name = "RampWest", material = Enum.Material.Asphalt, color = Palette.DarkAsphalt })
			Builder.wedge(roads, CFrame.new(x2 - rampLen / 2, y / 2 + 0.75, cz) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(r.width, y + 1.5, rampLen), { name = "RampEast", material = Enum.Material.Asphalt, color = Palette.DarkAsphalt })
			-- Parapets so cars read the edge
			for _, side in ipairs({ -1, 1 }) do
				Builder.box(roads, (x1 + x2) / 2, y + 1.5, cz + side * (r.width / 2 - 0.5), (x2 - x1) - 2 * rampLen, 2.5, 1, { name = "Parapet", material = Enum.Material.Concrete, color = Palette.Industrial })
			end
			for px = x1 + rampLen + 20, x2 - rampLen - 20, 40 do
				Builder.box(roads, px, 0, cz, 4, y, 4, { name = "Pillar", material = Enum.Material.Concrete, color = Palette.Industrial })
			end
		else
			local mat = if r.pedestrian then Enum.Material.Cobblestone else Enum.Material.Asphalt
			local col = if r.pedestrian then Palette.Pavement else Palette.DarkAsphalt
			Builder.box(roads, cx, 0, cz, w, 1, d, { name = r.name, material = mat, color = col })
			if not r.pedestrian then
				-- Centre line dashes
				local len = if ns then d else w
				local dashes = math.floor(len / 16)
				for i = 0, dashes - 1 do
					local off = -len / 2 + 8 + i * 16
					local dx, dz = if ns then 0 else off, if ns then off else 0
					Builder.box(roads, cx + dx, 1, cz + dz, if ns then 0.8 else 8, 0.1, if ns then 8 else 0.8, { name = "Line", material = Enum.Material.SmoothPlastic, color = Palette.RoadLine, canCollide = false, castShadow = false })
				end
				-- Street lamps on alternating sides
				local step = 70
				for i = 0, math.floor(len / step) do
					local off = -len / 2 + 20 + i * step
					local side = if i % 2 == 0 then 1 else -1
					local lx = if ns then cx + side * (r.width / 2 + 2) else cx + off
					local lz = if ns then cz + off else cz + side * (r.width / 2 + 2)
					local pole = Builder.box(lamps, lx, 1, lz, 0.8, 14, 0.8, { name = "LampPole", material = Enum.Material.Metal, color = Palette.Industrial })
					local head = Builder.box(lamps, lx, 15, lz, 2.5, 0.8, 2.5, { name = "LampHead", material = Enum.Material.Neon, color = Palette.WarmInterior, canCollide = false })
					Builder.pointLight(head, Palette.WarmInterior, 1.2, 36)
					pole.CastShadow = false
					if i % 3 == 0 then
						Builder.emergencyLight(lamps, lx, 8, lz)
					end
				end
			end
		end
		-- Pavements along vehicle roads
		if not r.pedestrian and not r.elevated then
			for _, side in ipairs({ -1, 1 }) do
				local px = if ns then cx + side * (r.width / 2 + 3) else cx
				local pz = if ns then cz else cz + side * (r.width / 2 + 3)
				Builder.box(roads, px, 0, pz, if ns then 6 else w, 1, if ns then d else 6, { name = "Kerb", material = Enum.Material.Concrete, color = Palette.Pavement })
			end
		end
		local _ = rng
	end
	-- Bollards (vehicles blocked, people pass)
	for _, b in ipairs(Blueprint.Bollards) do
		for i = -2, 2 do
			local ox = if b.rot == 0 then 0 else i * 3.2
			local oz = if b.rot == 0 then i * 3.2 else 0
			local post = Builder.box(roads, b.x + ox, 1, b.z + oz, 1, 3.5, 1, { name = "Bollard", material = Enum.Material.Metal, color = Palette.SecurityAmber })
			post.Shape = Enum.PartType.Cylinder
			post.CFrame = CFrame.new(b.x + ox, 2.75, b.z + oz) * CFrame.Angles(0, 0, math.rad(90))
			post.Size = Vector3.new(3.5, 1, 1)
		end
	end
end

local function buildBuilding(parent: Folder, b, rng: Random)
	local style = STYLE[b.style] or STYLE.Stone
	local m = Builder.model(parent, b.name)
	if b.style == "Yard" then
		-- Crane yard: low fence, stacked containers, a gantry crane
		Builder.box(m, b.x, 0, b.z, b.w, 1, b.d, { name = "YardFloor", material = Enum.Material.Concrete, color = Palette.DarkAsphalt })
		local cols = { Palette.Rust, Palette.SeaGlassDeep, Palette.Industrial, Palette.SecurityAmber }
		for _ = 1, 6 do
			local cx = b.x + rng:NextNumber(-b.w / 2 + 8, b.w / 2 - 8)
			local cz = b.z + rng:NextNumber(-b.d / 2 + 32, b.d / 2 - 10) -- the substation pad takes the near end
			local stack = rng:NextInteger(1, 2)
			for s = 0, stack - 1 do
				Builder.box(m, cx, 1 + s * 8, cz, 12, 8, 20, { name = "Container", material = Enum.Material.Metal, color = cols[rng:NextInteger(1, #cols)] })
			end
		end
		for _, side in ipairs({ -1, 1 }) do
			Builder.box(m, b.x + side * (b.w / 2 - 2), 0, b.z, 2, 40, 2, { name = "CraneLeg", material = Enum.Material.Metal, color = Palette.SecurityAmber })
		end
		Builder.box(m, b.x, 40, b.z, b.w, 2, 3, { name = "CraneBeam", material = Enum.Material.Metal, color = Palette.SecurityAmber })
		return
	end
	local shell = Builder.box(m, b.x, 0, b.z, b.w, b.h, b.d, { name = "Shell", material = style.material, color = style.color })
	if b.style == "Glass" then
		shell.Reflectance = 0.15
		shell.Transparency = 0
	end
	-- Plinth and parapet give silhouettes a base and a top line
	Builder.box(m, b.x, 0, b.z, b.w + 1.5, 2.5, b.d + 1.5, { name = "Plinth", material = Enum.Material.Concrete, color = Palette.Industrial })
	Builder.box(m, b.x, b.h, b.z, b.w + 1, 1.2, b.d + 1, { name = "Parapet", material = Enum.Material.Concrete, color = Palette.Industrial })
	-- Window strips per floor on all four facades, some lit
	local floors = math.max(1, math.floor((b.h - 4) / 8))
	for f = 0, floors - 1 do
		local y = 4 + f * 8
		local lit = rng:NextNumber() < 0.55
		local wcol = if lit then style.window else Palette.Night
		local wmat = if lit then Enum.Material.Neon else Enum.Material.Glass
		local inset = 0.3
		Builder.box(m, b.x, y, b.z + b.d / 2 - inset, b.w * 0.8, 3, 0.6, { name = "Windows", material = wmat, color = wcol, canCollide = false, castShadow = false })
		Builder.box(m, b.x, y, b.z - b.d / 2 + inset, b.w * 0.8, 3, 0.6, { name = "Windows", material = wmat, color = wcol, canCollide = false, castShadow = false })
		Builder.box(m, b.x + b.w / 2 - inset, y, b.z, 0.6, 3, b.d * 0.8, { name = "Windows", material = wmat, color = wcol, canCollide = false, castShadow = false })
		Builder.box(m, b.x - b.w / 2 + inset, y, b.z, 0.6, 3, b.d * 0.8, { name = "Windows", material = wmat, color = wcol, canCollide = false, castShadow = false })
	end
	-- Rooftop clutter
	if b.style == "Industrial" or b.style == "Stone" then
		Builder.box(m, b.x + b.w / 4, b.h, b.z - b.d / 4, 6, 4, 6, { name = "RoofUnit", material = Enum.Material.Metal, color = Palette.Industrial })
	end
	-- Ground-floor awning / shop glow for warm buildings
	if b.style == "Warm" then
		local awning = Builder.box(m, b.x, 9, b.z + b.d / 2 + 1.5, b.w * 0.6, 0.5, 3, { name = "Awning", material = Enum.Material.Fabric, color = Palette.SeaGlassDeep, canCollide = false })
		Builder.pointLight(awning, Palette.WarmInterior, 1, 18)
	end
	Builder.label(shell, b.name, Enum.NormalId.Front, Palette.Night, 28)
end

local function buildPlaza(root: Folder)
	local P = Blueprint.Plaza
	local m = Builder.model(root, "AuroraPlaza")
	Builder.box(m, P.x, 0, P.z, P.w, 1.2, P.d, { name = "Paving", material = Enum.Material.Marble, color = Palette.PaleStone })
	-- Fountain centre piece
	local basin = Builder.box(m, P.x, 1.2, P.z, 22, 2, 22, { name = "FountainBasin", material = Enum.Material.Marble, color = Palette.WarmStone })
	basin.Shape = Enum.PartType.Cylinder
	basin.CFrame = CFrame.new(P.x, 2.2, P.z) * CFrame.Angles(0, 0, math.rad(90))
	basin.Size = Vector3.new(2, 22, 22)
	local water = Builder.part(m, CFrame.new(P.x, 3.2, P.z) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.4, 19, 19), { name = "FountainWater", material = Enum.Material.Glass, color = Palette.SeaGlass, transparency = 0.3, canCollide = false, shape = Enum.PartType.Cylinder })
	Builder.pointLight(water, Palette.SeaGlass, 1.5, 24)
	local spire = Builder.box(m, P.x, 3, P.z, 3, 10, 3, { name = "FountainSpire", material = Enum.Material.Glass, color = Palette.SeaGlass, transparency = 0.2 })
	spire.Reflectance = 0.3
	-- Planters with small trees, benches
	local rng = Builder.rng(3)
	for i = -2, 2 do
		for _, side in ipairs({ -1, 1 }) do
			if i ~= 0 then
				local px, pz = P.x + i * 55, P.z + side * 34
				Builder.box(m, px, 1.2, pz, 10, 2.5, 10, { name = "Planter", material = Enum.Material.Concrete, color = Palette.Industrial })
				Builder.box(m, px, 3.7, pz, 8, 0.6, 8, { name = "Soil", material = Enum.Material.Grass, color = Palette.Grass, canCollide = false })
				local trunk = Builder.box(m, px, 4, pz, 1.2, 9, 1.2, { name = "Trunk", material = Enum.Material.Wood, color = Palette.WarmWood })
				local canopy = Builder.part(m, CFrame.new(px, 15, pz), Vector3.new(11 + rng:NextNumber(-2, 2), 9, 11 + rng:NextNumber(-2, 2)), { name = "Canopy", material = Enum.Material.Grass, color = Palette.Grass, shape = Enum.PartType.Ball, canCollide = false })
				canopy.CastShadow = true
				trunk.CastShadow = false
			end
		end
	end
	for i = -1, 1, 2 do
		Builder.box(m, P.x + i * 24, 1.2, P.z + 36, 10, 1.6, 2.5, { name = "Bench", material = Enum.Material.Wood, color = Palette.WarmWood })
	end
	-- Plaza flood lamps (restrained security lighting)
	for i = -1, 1, 2 do
		local pole = Builder.box(m, P.x + i * 120, 1.2, P.z - 40, 1, 22, 1, { name = "FloodPole", material = Enum.Material.Metal, color = Palette.Industrial })
		pole.CastShadow = false
		local head = Builder.box(m, P.x + i * 120, 23, P.z - 40, 4, 1, 2, { name = "FloodHead", material = Enum.Material.Neon, color = Palette.Glass, canCollide = false })
		Builder.spotLight(head, Palette.Glass, 1.6, 90, 70, Enum.NormalId.Bottom)
		Builder.emergencyLight(m, P.x + i * 60, 6, P.z - 20)
	end
end

-- Harbour Substation: the grid cabinet a crew on a job can sabotage (blackout) and anyone can reset.
local function buildSubstation(root: Folder)
	local S = Blueprint.Substation
	local m = Builder.model(root, "Substation")
	Builder.box(m, S.x, 0, S.z, S.w, 1.2, S.d, { name = "Pad", material = Enum.Material.Concrete, color = Palette.Industrial })
	-- Chain-link fence (thin translucent walls) with a gap on the road side (south)
	local fence = { material = Enum.Material.DiamondPlate, color = Palette.Industrial, canCollide = true, castShadow = false }
	local north = Builder.box(m, S.x, 1, S.z + S.d / 2, S.w, 7, 0.4, fence)
	north.Transparency = 0.45
	for _, side in ipairs({ -1, 1 }) do
		local w = Builder.box(m, S.x + side * S.w / 2, 1, S.z, 0.4, 7, S.d, fence)
		w.Transparency = 0.45
		local s = Builder.box(m, S.x + side * (S.w / 2 - 5), 1, S.z - S.d / 2, 10, 7, 0.4, fence)
		s.Transparency = 0.45
	end
	-- Transformers: humming coils that glow until the grid drops
	for i = -1, 1 do
		local tx = S.x + i * 10
		Builder.box(m, tx, 1.2, S.z + 3, 6, 6, 5, { name = "Transformer", material = Enum.Material.Metal, color = Palette.DarkAsphalt })
		local coil = Builder.box(m, tx, 7.2, S.z + 3, 1.2, 3, 1.2, { name = "CoilGlow", material = Enum.Material.Neon, color = Palette.SeaGlass, canCollide = false })
		Builder.pointLight(coil, Palette.SeaGlass, 0.8, 18)
	end
	Builder.box(m, S.x, 7.2, S.z + 3, 24, 0.3, 0.3, { name = "Busbar", material = Enum.Material.Metal, color = Palette.Rust, canCollide = false })
	-- Grid cabinet (sabotage side faces the gate) and the reset panel on its back
	local cabinet = Builder.box(m, S.x, 1.2, S.z - 3, 5, 6, 1.6, { name = "GridCabinet", material = Enum.Material.Metal, color = Palette.SecurityAmber })
	Builder.label(cabinet, "HARBOUR GRID\nAUTHORISED PERSONNEL ONLY", Enum.NormalId.Front, Palette.Night)
	local resetPanel = Builder.box(m, S.x, 2.2, S.z - 1.9, 3, 3, 0.6, { name = "ResetPanel", material = Enum.Material.Metal, color = Palette.Industrial })
	Builder.label(resetPanel, "GRID RESET", Enum.NormalId.Back, Palette.SeaGlass)
	local warningLight = Builder.box(m, S.x, 7.2, S.z - 3, 1, 1, 1, { name = "WarningLight", material = Enum.Material.Neon, color = Palette.SecurityAmber, canCollide = false })
	Builder.pointLight(warningLight, Palette.SecurityAmber, 1.2, 22)
	Builder.label(Builder.box(m, S.x, 8.2, S.z + S.d / 2, 20, 3, 0.4, { name = "Sign", material = Enum.Material.SmoothPlastic, color = Palette.Night, canCollide = false }), "HARBOUR SUBSTATION", Enum.NormalId.Front, Palette.SecurityAmber)
	Builder.emergencyLight(m, S.x - 12, 6, S.z - 6)
	Builder.emergencyLight(m, S.x + 12, 6, S.z - 6)
	return { model = m, cabinet = cabinet, resetPanel = resetPanel, warningLight = warningLight }
end

local function buildLanternCross(root: Folder)
	local L = Blueprint.LanternCross
	local m = Builder.model(root, "LanternCross")
	Builder.box(m, L.signX, 1, L.signZ, 3, 36, 3, { name = "SignTower", material = Enum.Material.Metal, color = Palette.Industrial })
	local sign = Builder.neonSign(m, CFrame.new(L.signX, 30, L.signZ + 4) * CFrame.Angles(0, math.rad(180), 0), Vector3.new(26, 10, 1), "LANTERN", Palette.NeonPink)
	sign.Name = "LanternSign"
	Builder.emergencyLight(m, L.x, 9, L.z)
	Builder.neonSign(m, CFrame.new(L.signX + 4, 20, L.signZ) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(18, 6, 1), "CROSS", Palette.NeonCyan)
	-- Hanging lanterns across the intersection corners
	for _, dx in ipairs({ -20, 20 }) do
		for _, dz in ipairs({ -20, 20 }) do
			local lantern = Builder.box(m, L.x + dx, 12, L.z + dz, 1.6, 2.4, 1.6, { name = "Lantern", material = Enum.Material.Neon, color = Palette.Gold, canCollide = false })
			Builder.pointLight(lantern, Palette.Gold, 1.4, 26)
		end
	end
end

local function buildLighthouse(root: Folder)
	local L = Blueprint.Lighthouse
	local m = Builder.model(root, "Lighthouse")
	local tower = Builder.box(m, L.x, 0, L.z, 14, 60, 14, { name = "Tower", material = Enum.Material.Concrete, color = Palette.PaleStone })
	tower.Shape = Enum.PartType.Cylinder
	tower.CFrame = CFrame.new(L.x, 30, L.z) * CFrame.Angles(0, 0, math.rad(90))
	tower.Size = Vector3.new(60, 14, 14)
	for i = 0, 2 do
		Builder.box(m, L.x, 8 + i * 18, L.z, 15.2, 4, 15.2, { name = "Band", material = Enum.Material.Concrete, color = Palette.SecurityRed, canCollide = false })
	end
	local lamp = Builder.box(m, L.x, 60, L.z, 8, 6, 8, { name = "Lamp", material = Enum.Material.Neon, color = Palette.Glass })
	Builder.pointLight(lamp, Palette.Glass, 3, 160)
	Builder.box(m, L.x, 66, L.z, 10, 1, 10, { name = "Cap", material = Enum.Material.Metal, color = Palette.Industrial })
end

local function buildParkingDeck(root: Folder)
	local D = Blueprint.ParkingDeck
	local M = Blueprint.Museum
	local m = Builder.model(root, "ParkingDeck")
	local x1, x2 = D.x - D.w / 2, D.x + D.w / 2
	local z1, z2 = D.z - D.d / 2, D.z + D.d / 2
	Builder.box(m, D.x, 0, D.z, D.w, 1, D.d, { name = "GroundSlab", material = Enum.Material.Concrete, color = Palette.DarkAsphalt })
	-- Roof slab, leaving the east strip for the ramp
	Builder.box(m, D.x - 10, D.h, D.z, D.w - 20, 1.5, D.d, { name = "RoofSlab", material = Enum.Material.Concrete, color = Palette.Industrial })
	-- Pillars
	for px = x1 + 12, x2 - 12, 25 do
		for pz = z1 + 12, z2 - 12, 34 do
			Builder.box(m, px, 1, pz, 3, D.h - 1, 3, { name = "Pillar", material = Enum.Material.Concrete, color = Palette.Industrial })
		end
	end
	-- Ramp up the east side (rises toward +Z), then a flat landing joining the roof
	local rampLen = 90
	Builder.wedge(m, CFrame.new(x2 - 10, D.h / 2 + 0.5, z1 + rampLen / 2) * CFrame.Angles(0, 0, 0), Vector3.new(20, D.h, rampLen), { name = "Ramp", material = Enum.Material.Concrete, color = Palette.DarkAsphalt })
	Builder.box(m, x2 - 10, D.h, (z1 + rampLen + z2) / 2, 20, 1.5, z2 - (z1 + rampLen), { name = "RampLanding", material = Enum.Material.Concrete, color = Palette.Industrial })
	-- Parapets on the roof edges (gap on the west edge for the gantry)
	Builder.box(m, D.x, D.h + 1.5, z1 + 0.5, D.w, 2, 1, { name = "Parapet", material = Enum.Material.Concrete, color = Palette.Industrial })
	Builder.box(m, D.x, D.h + 1.5, z2 - 0.5, D.w, 2, 1, { name = "Parapet", material = Enum.Material.Concrete, color = Palette.Industrial })
	Builder.box(m, x2 - 0.5, D.h + 1.5, D.z, 1, 2, D.d, { name = "Parapet", material = Enum.Material.Concrete, color = Palette.Industrial })
	-- Gantry: catwalk from the roof's west edge to the museum east wall, then a ladder up to the museum roof
	local gz = M.z - 20
	local museumEast = M.x + M.w / 2
	Builder.box(m, (x1 + museumEast) / 2, D.h, gz, x1 - museumEast, 1, 5, { name = "Gantry", material = Enum.Material.DiamondPlate, color = Palette.Industrial })
	for _, side in ipairs({ -1, 1 }) do
		Builder.box(m, (x1 + museumEast) / 2, D.h + 1, gz + side * 2.6, x1 - museumEast, 3, 0.4, { name = "GantryRail", material = Enum.Material.Metal, color = Palette.SecurityAmber, canCollide = false })
	end
	Builder.truss(m, CFrame.new(museumEast + 1.2, D.h + 1 + (M.h - D.h) / 2, gz), M.h - D.h + 2, "GantryLadder")
	-- Light on the roof so the route reads at night
	local lamp = Builder.box(m, x1 + 6, D.h + 1.5, gz, 1, 10, 1, { name = "DeckLampPole", material = Enum.Material.Metal, color = Palette.Industrial })
	lamp.CastShadow = false
	local head = Builder.box(m, x1 + 6, D.h + 11.5, gz, 2, 0.8, 2, { name = "DeckLampHead", material = Enum.Material.Neon, color = Palette.SecurityAmber, canCollide = false })
	Builder.pointLight(head, Palette.SecurityAmber, 1.2, 30)
	Builder.emergencyLight(m, x1 + 6, D.h + 3, gz + 6)
	Builder.label(Builder.box(m, D.x, D.h + 1.5, z2 - 2, 30, 6, 0.5, { name = "DeckSign", material = Enum.Material.SmoothPlastic, color = Palette.Night, canCollide = false }), "PARKING DECK — ROOF", Enum.NormalId.Front, Palette.SecurityAmber)
	return { roofY = D.h + 1.5, gantryZ = gz }
end

-- Police station with a lobby, a release switch and a cell block. Returns references for PoliceService.
local function buildPoliceStation(root: Folder)
	local S = Blueprint.PoliceStation
	local m = Builder.model(root, "PoliceStation")
	local x1, x2 = S.x - S.w / 2, S.x + S.w / 2
	local z1, z2 = S.z - S.d / 2, S.z + S.d / 2
	local wall = { name = "Wall", material = Enum.Material.Concrete, color = Palette.PaleStone }
	Builder.box(m, S.x, 0, S.z, S.w, 1, S.d, { name = "Floor", material = Enum.Material.Concrete, color = Palette.Pavement })
	Builder.box(m, S.x, S.h, S.z, S.w, 1, S.d, { name = "Roof", material = Enum.Material.Concrete, color = Palette.Industrial })
	-- Outer walls: north, east, west full; south with an entrance gap at the centre
	Builder.box(m, S.x, 0, z1 + 0.5, S.w, S.h, 1, wall)
	Builder.box(m, x1 + 0.5, 0, S.z, 1, S.h, S.d, wall)
	Builder.box(m, x2 - 0.5, 0, S.z, 1, S.h, S.d, wall)
	local gap = 12
	Builder.box(m, (x1 + S.x - gap / 2) / 2, 0, z2 - 0.5, (S.x - gap / 2) - x1, S.h, 1, wall)
	Builder.box(m, (x2 + S.x + gap / 2) / 2, 0, z2 - 0.5, x2 - (S.x + gap / 2), S.h, 1, wall)
	Builder.box(m, S.x, 10, z2 - 0.5, gap, S.h - 10, 1, wall)
	-- Lobby lighting and desk
	local desk = Builder.box(m, S.x, 1, z2 - 18, 24, 3.5, 4, { name = "Desk", material = Enum.Material.Wood, color = Palette.WarmWood })
	Builder.label(desk, "GLASSHOUSE POLICE", Enum.NormalId.Front, Palette.PaleStone)
	for i = -1, 1 do
		local light = Builder.box(m, S.x + i * 30, S.h - 1.5, S.z, 6, 0.5, 2, { name = "Ceiling", material = Enum.Material.Neon, color = Palette.Glass, canCollide = false })
		Builder.pointLight(light, Palette.Glass, 1.2, 40)
	end
	-- Cell block partition at z = z1 + 45 with a barred door gap at centre
	local pz = z1 + 45
	local bars = { name = "Bars", material = Enum.Material.Metal, color = Palette.Industrial }
	Builder.box(m, (x1 + S.x - 4) / 2, 0, pz, (S.x - 4) - x1, S.h, 1, bars)
	Builder.box(m, (x2 + S.x + 4) / 2, 0, pz, x2 - (S.x + 4), S.h, 1, bars)
	Builder.box(m, S.x, 9, pz, 8, S.h - 9, 1, bars)
	local door = Builder.box(m, S.x, 1, pz, 8, 8, 1, { name = "CellDoor", material = Enum.Material.Metal, color = Palette.SecurityRed })
	Builder.label(door, "CELL BLOCK", Enum.NormalId.Front, Palette.PaleStone)
	Builder.label(door, "LOCKED", Enum.NormalId.Back, Palette.PaleStone)
	-- Cells: three bunks along the north wall
	local cellSpawns = {}
	for i = -1, 1 do
		local cx = S.x + i * 30
		Builder.box(m, cx, 1, z1 + 8, 8, 2, 14, { name = "Bunk", material = Enum.Material.Fabric, color = Palette.Industrial })
		table.insert(cellSpawns, CFrame.new(cx, 4, z1 + 24))
	end
	-- Release switch on the lobby wall (teammates can free prisoners from here)
	local switch = Builder.box(m, x1 + 2.5, 4, pz + 10, 1, 3, 3, { name = "ReleaseSwitch", material = Enum.Material.Metal, color = Palette.SecurityAmber })
	Builder.label(switch, "CELL RELEASE", Enum.NormalId.Right, Palette.Night)
	-- Cruiser pads in the lot north of Station Road
	local pads = {}
	local L = Blueprint.PoliceLot
	Builder.box(m, L.x, 0, L.z, L.w, 1, L.d, { name = "Lot", material = Enum.Material.Asphalt, color = Palette.DarkAsphalt })
	for i = 0, 9 do
		local px = L.x - L.w / 2 + 10 + (i % 5) * 24
		local pzz = L.z - 14 + math.floor(i / 5) * 28
		table.insert(pads, CFrame.new(px, 2.5, pzz) * CFrame.Angles(0, math.rad(180), 0)) -- nose toward Station Road
		Builder.box(m, px, 1, pzz, 10, 0.2, 20, { name = "PadLine", material = Enum.Material.SmoothPlastic, color = Palette.PoliceLight, canCollide = false, castShadow = false })
	end
	Builder.neonSign(m, CFrame.new(S.x, S.h + 4, z2) * CFrame.Angles(0, math.rad(180), 0), Vector3.new(50, 7, 1), "POLICE", Palette.PoliceLight)
	return {
		cellSpawns = cellSpawns,
		cellDoor = door,
		releaseSwitch = switch,
		cruiserPads = pads,
		lobbyPost = CFrame.new(S.x + 20, 3, z2 - 30),
		entrance = CFrame.new(S.x, 3, z2 + 10),
	}
end

function IslandBuilder.build(root: Folder)
	buildLand(root)
	buildRoads(root)
	local buildings = Builder.folder(root, "Buildings")
	local rng = Builder.rng(11)
	for _, b in ipairs(Blueprint.Buildings) do
		buildBuilding(buildings, b, rng)
	end
	buildPlaza(root)
	buildLanternCross(root)
	buildLighthouse(root)
	local deck = buildParkingDeck(root)
	local station = buildPoliceStation(root)
	local substation = buildSubstation(root)
	return { deck = deck, station = station, substation = substation }
end

return IslandBuilder
