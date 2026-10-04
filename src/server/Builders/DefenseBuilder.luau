--!nonstrict
-- Renders a hideout's defences from its tier: safe, alarm light, bay shield + breaker box, pier back door,
-- laser beams. Returns references RaidService drives. Rebuilt whenever the tier or owner changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local StashRules = require(ReplicatedStorage.Shared.Core.StashRules)
local Builder = require(script.Parent.Builder)

local DefenseBuilder = {}

local ROOF_H = 14

function DefenseBuilder.clear(unit)
	local old = unit.model:FindFirstChild("Defences")
	if old then
		old:Destroy()
	end
end

function DefenseBuilder.build(unit, tier: number, ownerName: string)
	DefenseBuilder.clear(unit)
	local folder = Builder.folder(unit.model, "Defences")
	local b = unit.bounds
	local x1, x2 = b.minX, b.maxX
	local z1 = b.minZ
	local cx = (x1 + x2) / 2
	local z2 = b.maxZ - 32 -- unit back wall (bounds include the pier)
	local d = StashRules.defences(Config.Hideout, tier)
	local refs = { folder = folder, tier = tier, defences = d }

	-- Safe: next to the stash sign on the back wall
	local safe = Builder.box(folder, cx + 12, 1, z2 - 4, 6, 6, 5, { name = "Safe", material = Enum.Material.Metal, color = Palette.Night })
	safe.Reflectance = 0.1
	Builder.label(safe, string.format("%s\nTIER %d", ownerName, tier), Enum.NormalId.Front, Palette.Gold)
	refs.safe = safe
	local dial = Builder.part(folder, safe.CFrame * CFrame.new(0, 0.5, -2.6) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.4, 1.4, 1.4), { name = "Dial", material = Enum.Material.Metal, color = Palette.Gold, shape = Enum.PartType.Cylinder, canCollide = false })
	refs.dial = dial

	-- Alarm light over the bay (tier 2+)
	if d.Alarm then
		local light = Builder.box(folder, cx, ROOF_H - 1.5, z1 + 3, 2, 1, 2, { name = "AlarmLight", material = Enum.Material.Neon, color = Palette.Night, canCollide = false })
		refs.alarmLight = light
		refs.alarmPoint = Builder.pointLight(light, Palette.SecurityRed, 0, 40)
	end

	-- Bay shield (tier 3+): a sea-glass barrier across the garage opening; breaker box outside on the wall
	if d.Shield then
		local shield = Builder.box(folder, cx, 1, z1 + 1.5, 20, 9, 0.6, { name = "Shield", material = Enum.Material.ForceField, color = if d.Shield2 then Palette.NeonPink else Palette.SeaGlass, transparency = 0.2 })
		Builder.label(shield, if d.Shield2 then "REINFORCED SHIELD" else "SHIELD", Enum.NormalId.Front, Palette.Night)
		Builder.label(shield, "LOW LASERS: JUMP · HIGH LASERS: WALK", Enum.NormalId.Back, Palette.Night)
		refs.shield = shield
		-- the person door beside the bay is shielded too
		local side = Builder.box(folder, cx - 12.5, 1, z1 + 1.5, 5, 9, 0.6, { name = "ShieldSide", material = Enum.Material.ForceField, color = shield.Color, transparency = 0.2 })
		refs.shieldSide = side
		local breaker = Builder.box(folder, x2 + 1.2, 3, z1 + 12, 1.2, 3, 2.5, { name = "Breaker", material = Enum.Material.Metal, color = Palette.Industrial })
		Builder.label(breaker, "SHIELD\nBREAKER", Enum.NormalId.Right, Palette.SecurityAmber)
		refs.breaker = breaker
	end

	-- Pier back door (always): the alternative way in from the water side; barred at tier 5+
	local door = Builder.box(folder, cx + 18, 1, z2 - 0.5, 5, 9, 1.2, { name = "PierDoor", material = Enum.Material.Metal, color = if d.Shield2 then Palette.Rust else Palette.Industrial })
	Builder.label(door, if d.Shield2 then "BARRED" else "PIER DOOR", Enum.NormalId.Back, Palette.PaleStone)
	refs.pierDoor = door

	-- Lasers (tier 4+): beams across the living space; sweeping at tier 6
	if d.Lasers then
		refs.lasers = {}
		local count = if d.Lasers2 then 4 else 3
		for i = 1, count do
			local zz = z1 + 20 + i * 8
			local y = if i % 2 == 1 then 1.8 else 6.4 -- low: jump it; high: walk under, never jump
			local beam = Builder.box(folder, cx, y, zz, x2 - x1 - 2, 0.3, 0.3, { name = "Laser", material = Enum.Material.Neon, color = Palette.SecurityRed, canCollide = false })
			beam:SetAttribute("BaseZ", zz)
			beam:SetAttribute("BaseY", beam.Position.Y)
			local emitter = Builder.box(folder, x1 + 0.9, beam.Position.Y - 0.5, zz, 0.8, 1, 1, { name = "LaserEmitter", material = Enum.Material.Metal, color = Palette.Industrial })
			local _ = emitter
			table.insert(refs.lasers, beam)
		end
	end
	return refs
end

return DefenseBuilder
