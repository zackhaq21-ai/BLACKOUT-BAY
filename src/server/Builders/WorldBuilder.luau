--!nonstrict
-- Builds the whole world once (if Workspace.Glasshouse does not already exist, so a baked place keeps its map),
-- applies the lighting look, and returns the reference table services use.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Builder = require(script.Parent.Builder)
local IslandBuilder = require(script.Parent.IslandBuilder)
local MuseumBuilder = require(script.Parent.MuseumBuilder)
local HideoutBuilder = require(script.Parent.HideoutBuilder)

local WorldBuilder = {}

local function applyLighting()
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.32
		atm.Offset = 0.2
		atm.Color = Color3.fromRGB(190, 205, 220)
		atm.Decay = Color3.fromRGB(80, 100, 130)
		atm.Glare = 0.2
		atm.Haze = 1.4
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChild("GlasshouseBloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "GlasshouseBloom"
		bloom.Intensity = 0.35
		bloom.Size = 24
		bloom.Threshold = 1.5
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChild("GlasshouseGrade") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "GlasshouseGrade"
		cc.Contrast = 0.08
		cc.Saturation = 0.08
		cc.TintColor = Color3.fromRGB(245, 240, 255)
		cc.Parent = Lighting
	end
	Lighting.ClockTime = 19.6
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(78, 86, 108)
	Lighting.Ambient = Color3.fromRGB(56, 60, 76)
	Lighting.FogColor = Color3.fromRGB(92, 115, 140)
	Lighting.FogStart = 400
	Lighting.FogEnd = 1700
end

function WorldBuilder.build()
	applyLighting()
	local existing = workspace:FindFirstChild("Glasshouse")
	if existing then
		existing:Destroy() -- generated content; rebuilt deterministically each start
	end
	local root = Builder.folder(workspace, "Glasshouse")
	local island = IslandBuilder.build(root)
	local museum = MuseumBuilder.build(root)
	local hideouts, lockup = HideoutBuilder.build(root)
	Builder.folder(root, "Vehicles")
	Builder.folder(root, "Loot")
	Builder.folder(root, "NPCs")
	-- Default spawn (used only before a hideout is assigned)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArrivalSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(-390, 1.8, 322)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	return {
		root = root,
		island = island,
		museum = museum,
		hideouts = hideouts,
		lockup = lockup,
		vehiclesFolder = root.Vehicles,
		lootFolder = root.Loot,
		npcFolder = root.NPCs,
		blueprint = Blueprint,
		palette = Palette,
	}
end

return WorldBuilder
