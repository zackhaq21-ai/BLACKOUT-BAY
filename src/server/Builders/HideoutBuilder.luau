--!nonstrict
-- Harbour pier units: each crew's hideout. Garage bay at the front (north, on Dockside), living space
-- behind with the prep board, delivery table, stash sign and spawn; a wooden pier over the water at the back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Builder = require(script.Parent.Builder)

local HideoutBuilder = {}

local ROOF_H = 14

local function buildUnit(parent: Folder, h, index: number)
	local m = Builder.model(parent, "Hideout_" .. h.id)
	local x1, x2 = h.x - h.w / 2, h.x + h.w / 2
	local z1, z2 = h.z - h.d / 2, h.z + h.d / 2
	local accent = Palette.CrewColors[((index - 1) % #Palette.CrewColors) + 1]
	local wall = { name = "Wall", material = Enum.Material.Metal, color = Palette.Industrial }
	Builder.box(m, h.x, 0, h.z, h.w, 1, h.d, { name = "Floor", material = Enum.Material.Concrete, color = Palette.DarkAsphalt })
	Builder.box(m, h.x, ROOF_H, h.z, h.w, 1, h.d, { name = "Roof", material = Enum.Material.CorrodedMetal, color = Palette.Rust })
	Builder.box(m, x1 + 0.5, 0, h.z, 1, ROOF_H, h.d, wall)
	Builder.box(m, x2 - 0.5, 0, h.z, 1, ROOF_H, h.d, wall)
	Builder.box(m, h.x, 0, z2 - 0.5, h.w, ROOF_H, 1, wall)
	-- Front wall with the garage opening (20 wide, 10 high) and a person door (gap 5)
	local gw = 20
	Builder.box(m, (x1 + h.x - gw / 2) / 2 - 2.5, 0, z1 + 0.5, (h.x - gw / 2) - x1 - 5, ROOF_H, 1, wall)
	Builder.box(m, (x2 + h.x + gw / 2) / 2, 0, z1 + 0.5, x2 - (h.x + gw / 2), ROOF_H, 1, wall)
	Builder.box(m, h.x, 10, z1 + 0.5, gw, ROOF_H - 10, 1, wall)
	Builder.box(m, h.x - gw / 2 - 2.5, 9, z1 + 0.5, 5, ROOF_H - 9, 1, wall)
	-- Unit sign (the arrival shot) and accent strip
	local sign = Builder.neonSign(m, CFrame.new(h.x, ROOF_H + 3, z1) * CFrame.Angles(0, 0, 0), Vector3.new(26, 5, 0.8), h.label, accent)
	sign.Name = "UnitSign"
	Builder.box(m, h.x, ROOF_H - 0.6, z1 - 0.2, h.w, 0.8, 0.4, { name = "AccentStrip", material = Enum.Material.Neon, color = accent, canCollide = false })
	-- Partition between the bay and the living space with a wide opening
	local pz = h.z - 2
	Builder.box(m, x1 + 7, 0, pz, 14, ROOF_H, 1, { name = "Partition", material = Enum.Material.WoodPlanks, color = Palette.WarmWood })
	Builder.box(m, x2 - 7, 0, pz, 14, ROOF_H, 1, { name = "Partition", material = Enum.Material.WoodPlanks, color = Palette.WarmWood })
	-- Living space: prep board on the back wall, delivery table centre, stash sign, bunk, warm light
	local board = Builder.box(m, h.x - 10, 3, z2 - 1.6, 14, 8, 1, { name = "PrepBoard", material = Enum.Material.SmoothPlastic, color = Palette.Night })
	Builder.label(board, "BLACKOUT BAY\nJOB BOARD · Aurora Exchange", Enum.NormalId.Front, Palette.SeaGlass)
	local table_ = Builder.box(m, h.x, 1, h.z + 16, 10, 3, 5, { name = "DeliveryTable", material = Enum.Material.Wood, color = Palette.WarmWood })
	Builder.label(table_, "DROP THE HAUL HERE", Enum.NormalId.Top, Palette.PaleStone)
	local stash = Builder.box(m, h.x + 12, 3, z2 - 1.6, 12, 6, 1, { name = "StashSign", material = Enum.Material.SmoothPlastic, color = Palette.Night })
	Builder.label(stash, "STASH\n0", Enum.NormalId.Front, Palette.Gold)
	Builder.box(m, x2 - 6, 1, h.z + 28, 8, 2.5, 12, { name = "Bunk", material = Enum.Material.Fabric, color = Palette.SeaGlassDeep })
	-- Crew ledger wall: the crew's story, painted on the west wall of the living space
	local ledger = Builder.box(m, x1 + 1.3, 2.5, h.z + 14, 0.6, 9, 18, { name = "LedgerWall", material = Enum.Material.SmoothPlastic, color = Palette.Night })
	Builder.label(ledger, "CREW LEDGER", Enum.NormalId.Right, Palette.PaleStone, 22)
	local lamp = Builder.box(m, h.x, ROOF_H - 1.5, h.z + 16, 6, 0.5, 6, { name = "Lamp", material = Enum.Material.Neon, color = Palette.WarmInterior, canCollide = false })
	Builder.pointLight(lamp, Palette.WarmInterior, 1.3, 40)
	local bayLamp = Builder.box(m, h.x, ROOF_H - 1.5, z1 + 12, 6, 0.5, 6, { name = "BayLamp", material = Enum.Material.Neon, color = Palette.Glass, canCollide = false })
	Builder.pointLight(bayLamp, Palette.Glass, 1, 36)
	Builder.emergencyLight(m, h.x + 8, ROOF_H - 2.5, z1 + 12)
	-- Garage floor markings
	Builder.box(m, h.x, 1, z1 + 16, 12, 0.1, 24, { name = "BayLines", material = Enum.Material.SmoothPlastic, color = accent, canCollide = false, castShadow = false })
	-- Pier behind the unit
	Builder.box(m, h.x, -1, z2 + 16, h.w - 8, 1.2, 32, { name = "Pier", material = Enum.Material.WoodPlanks, color = Palette.WarmWood })
	for i = -1, 1, 2 do
		Builder.box(m, h.x + i * (h.w / 2 - 6), -6, z2 + 30, 2, 8, 2, { name = "Pile", material = Enum.Material.Wood, color = Palette.WarmWood })
	end
	-- Back door to the pier
	Builder.box(m, h.x + 18, 0, z2 - 0.5, 1, 1, 1, { name = "DoorMarker", material = Enum.Material.SmoothPlastic, color = Palette.Night, transparency = 1, canCollide = false })
	return {
		id = h.id,
		label = h.label,
		index = index,
		accent = accent,
		model = m,
		spawn = CFrame.new(h.x - 10, 4, h.z + 8) * CFrame.Angles(0, math.rad(180), 0),
		vehicleSpawn = CFrame.new(h.x, 3, z1 + 16) * CFrame.Angles(0, 0, 0),
		board = board,
		deliveryTable = table_,
		stashSign = stash,
		ledgerWall = ledger,
		bounds = { minX = x1, maxX = x2, minZ = z1, maxZ = z2 + 32 },
	}
end

function HideoutBuilder.build(root: Folder)
	local folder = Builder.folder(root, "Hideouts")
	local units = {}
	for i, h in ipairs(Blueprint.Hideouts) do
		table.insert(units, buildUnit(folder, h, i))
	end
	local lockup = buildUnit(folder, Blueprint.Lockup, 7)
	lockup.isLockup = true
	local boardGui = lockup.board:FindFirstChild("Label")
	local tl = boardGui and boardGui:FindFirstChildWhichIsA("TextLabel", true)
	if tl then
		tl.Text = "BREAKWATER LOCKUP\nraided hideouts appear here"
	end
	-- Harbour promenade between the units and Dockside Street, plus water-side lamps
	local first, last = Blueprint.Hideouts[1], Blueprint.Hideouts[#Blueprint.Hideouts]
	local cx = (first.x + last.x) / 2
	Builder.box(folder, cx, 0, 322, (last.x - first.x) + first.w + 20, 1.2, 14, { name = "Promenade", material = Enum.Material.Cobblestone, color = Palette.Pavement })
	return units, lockup
end

return HideoutBuilder
