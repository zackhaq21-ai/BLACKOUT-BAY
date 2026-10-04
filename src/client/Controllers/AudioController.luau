--!nonstrict
-- Sound cues. Asset ids live in Config.Audio.Cues and are blank until licensed sounds are added; every cue
-- still has a visual equivalent (toast / flash) so nothing depends on audio alone.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)

local AudioController = {}

local sounds = {}
local hud

local VOLUME = { Alarm = 0.6, Siren = 0.6, Lockdown = 0.7, Smash = 0.8, Payout = 0.7 }

local function ensure(name: string): Sound?
	local id = Config.Audio.Cues[name]
	if not id or id == "" then
		return nil
	end
	local s = sounds[name]
	if not s then
		s = Instance.new("Sound")
		s.Name = "Cue_" .. name
		s.SoundId = id
		s.Volume = VOLUME[name] or 0.5
		s.Parent = SoundService
		sounds[name] = s
	end
	return s
end

local FLASH = {
	Alarm = Theme.Alarm,
	Lockdown = Theme.Alarm,
	Siren = Theme.Police,
	Arrest = Theme.Alarm,
	PowerCut = Theme.Accent,
	Payout = Theme.Gold,
	Smash = Theme.Warn,
}

function AudioController.play(name: string)
	local s = ensure(name)
	if s then
		s:Play()
	end
	local color = FLASH[name]
	if color and hud then
		hud.flash(color)
	end
end

function AudioController.init(hudController)
	hud = hudController
	Net.event("Cue").OnClientEvent:Connect(function(d)
		AudioController.play(d.name)
	end)
end

return AudioController
