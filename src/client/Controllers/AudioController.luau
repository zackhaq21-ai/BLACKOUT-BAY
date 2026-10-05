--!nonstrict
-- Audio architecture: SoundGroups per bus (Ambience, Weather, City, Vehicles, Police, UI, Interaction, Events,
-- Interiors), positional cues from the server (pooled emitters at a world position), local feel cues, weather
-- ambience beds, and an interior/exterior mix. Asset ids live in Config.Audio and are blank until licensed;
-- every cue keeps a visual equivalent (flash / VFX) so nothing depends on audio alone.
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Theme = require(script.Parent.Parent.UI.Theme)
local Vfx = require(script.Parent.Parent.Fx.Vfx)

local AudioController = {}

local GROUPS = { "Ambience", "Weather", "City", "Vehicles", "Police", "UI", "Interaction", "Events", "Interiors" }
local groups: { [string]: SoundGroup } = {}
local cueSounds = {}
local beds = {} -- name -> Sound (ambience loops)
local posPool = {} -- { part, sound, busyUntil }
local hud
local interior = false

local VOLUME = { Alarm = 0.6, Siren = 0.6, Lockdown = 0.7, Smash = 0.8, Payout = 0.7 }

local FLASH = {
	Alarm = Theme.Alarm, Lockdown = Theme.Alarm, Siren = Theme.Police, Arrest = Theme.Alarm, PowerCut = Theme.Accent,
	Payout = Theme.Gold, Smash = Theme.Warn, ConvoyAlert = Theme.Alarm, ConvoyBreach = Theme.Gold, ConvoyAnnounce = Theme.Warn,
}

-- Visual twin of a positional cue (the VFX pool); cues without a position use the local character
local VFX = {
	Smash = { "Glass", 1 }, PowerCut = { "Electric", 1.2 }, Pickup = { "Glint", 0.6 }, Deliver = { "Glint", 1 }, Payout = { "Glint", 1.4 },
	Unlock = { "Sparks", 0.6 }, Drill = { "Sparks", 0.8 }, LaserTrip = { "Sparks", 1 }, ConvoyBreach = { "Sparks", 1.2 }, Arrest = { "Dust", 0.6 }, Drop = { "Dust", 0.4 },
}

local function group(name: string): SoundGroup
	return groups[name] or groups.Interaction
end

local function ensureCue(name: string): Sound?
	local id = Config.Audio.Cues[name]
	if not id or id == "" then
		return nil
	end
	local s = cueSounds[name]
	if not s then
		s = Instance.new("Sound")
		s.Name = "Cue_" .. name
		s.SoundId = id
		s.Volume = VOLUME[name] or 0.5
		s.SoundGroup = group(Config.Audio.Groups[name] or "Interaction")
		s.Parent = SoundService
		cueSounds[name] = s
	end
	return s
end

local function positionalSlot()
	local now = os.clock()
	for _, p in ipairs(posPool) do
		if p.busyUntil <= now then
			return p
		end
	end
	return posPool[1]
end

local function playAt(name: string, position: Vector3)
	local id = Config.Audio.Cues[name]
	if not id or id == "" then
		return
	end
	local slot = positionalSlot()
	if not slot then
		return
	end
	slot.part.Position = position
	slot.sound.SoundId = id
	slot.sound.Volume = VOLUME[name] or 0.5
	slot.sound.SoundGroup = group(Config.Audio.Groups[name] or "Interaction")
	slot.sound:Play()
	slot.busyUntil = os.clock() + 3
end

function AudioController.play(name: string, position: Vector3?)
	if position then
		playAt(name, position)
	else
		local s = ensureCue(name)
		if s then
			s:Play()
		end
	end
	local color = FLASH[name]
	if color and hud then
		hud.flash(color)
	end
	local fx = VFX[name]
	if fx then
		local at = position
		if not at then
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			at = root and root.Position
		end
		if at then
			Vfx.burst(fx[1], at, fx[2])
		end
	end
end

-- Local feel cues (landing, sprint start). Never replicated; silent while ids are blank.
function AudioController.feel(name: string, volume: number)
	local id = Config.Audio.Feel[name]
	if not id or id == "" then
		return
	end
	local s = cueSounds["Feel_" .. name]
	if not s then
		s = Instance.new("Sound")
		s.Name = "Feel_" .. name
		s.SoundId = id
		s.SoundGroup = groups.Interaction
		s.Parent = SoundService
		cueSounds["Feel_" .. name] = s
	end
	s.Volume = math.clamp(volume, 0, 1)
	s:Play()
end

-- Ambience beds: one loop per bed, cross-faded by target volume
local function bed(name: string): Sound?
	local id = Config.Audio.Ambience[name]
	if not id or id == "" then
		return nil
	end
	local s = beds[name]
	if not s then
		s = Instance.new("Sound")
		s.Name = "Bed_" .. name
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = if name == "Rain" or name == "Storm" or name == "Wind" then groups.Weather elseif name == "Interior" then groups.Interiors else groups.Ambience
		s.Parent = SoundService
		s:Play()
		beds[name] = s
	end
	return s
end

local function setBed(name: string, volume: number)
	local s = bed(name)
	if s then
		game:GetService("TweenService"):Create(s, TweenInfo.new(2.5), { Volume = math.clamp(volume, 0, 1) }):Play()
	end
end

-- Weather look drives the beds (called by EnvironmentController)
function AudioController.setWeather(rain: number, storm: boolean)
	setBed("Rain", if interior then rain * 0.35 else rain)
	setBed("Storm", if storm then (if interior then 0.3 else 0.7) else 0)
	setBed("Wind", if interior then 0 else 0.25 + rain * 0.3)
end

-- Interior / exterior mix: reverb and a duller exterior when inside the museum or a hideout
local function insideBuilding(pos: Vector3): boolean
	local M = Blueprint.Museum
	if math.abs(pos.X - M.x) <= M.w / 2 and math.abs(pos.Z - M.z) <= M.d / 2 then
		return true
	end
	for _, h in ipairs(Blueprint.Hideouts) do
		if math.abs(pos.X - h.x) <= h.w / 2 and math.abs(pos.Z - h.z) <= h.d / 2 then
			return true
		end
	end
	return false
end

local function applyInterior(on: boolean)
	if on == interior then
		return
	end
	interior = on
	SoundService.AmbientReverb = if on then Enum.ReverbType.Hallway else Enum.ReverbType.City
	local TweenService = game:GetService("TweenService")
	for _, name in ipairs({ "Ambience", "Weather", "City" }) do
		TweenService:Create(groups[name], TweenInfo.new(1.2), { Volume = if on then 0.45 else 1 }):Play()
	end
	setBed("City", if on then 0.3 else 0.8)
	setBed("Harbour", if on then 0.1 else 0.5)
	setBed("Interior", if on then 0.6 else 0)
end

function AudioController.init(hudController)
	hud = hudController
	for _, name in ipairs(GROUPS) do
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
		groups[name] = g
	end
	SoundService.DistanceFactor = 3.33
	SoundService.AmbientReverb = Enum.ReverbType.City
	for _ = 1, 6 do
		local part = Instance.new("Part")
		part.Name = "AudioEmitter"
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Parent = Workspace.Terrain
		local s = Instance.new("Sound")
		s.RollOffMaxDistance = 160
		s.RollOffMinDistance = 10
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = part
		table.insert(posPool, { part = part, sound = s, busyUntil = 0 })
	end
	setBed("City", 0.8)
	setBed("Harbour", 0.5)
	Net.event("Cue").OnClientEvent:Connect(function(d)
		if type(d) ~= "table" or type(d.name) ~= "string" then
			return
		end
		local pos = if type(d.x) == "number" and type(d.y) == "number" and type(d.z) == "number" then Vector3.new(d.x, d.y, d.z) else nil
		AudioController.play(d.name, pos)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				applyInterior(insideBuilding(root.Position))
			end
		end
	end)
end

return AudioController
