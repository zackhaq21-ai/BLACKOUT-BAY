--!nonstrict
-- Authoritative weather: picks bounded states with WeatherRules, replicates them, and feeds the NPC vision
-- factor into Security/Police alongside the blackout. Presentation (Lighting, rain, sound) is client-side.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local WeatherRules = require(ReplicatedStorage.Shared.Core.WeatherRules)

local EnvironmentService = {}
EnvironmentService.ctx = nil :: any

local PW = Config.Presentation.Weather
local rng = Random.new()
local state = "Clear"
local previous = "Clear"
local changedAt = 0
local nextChangeAt = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function payload()
	return { state = state, previous = previous, changedAt = changedAt, blendSeconds = PW.BlendSeconds }
end

function EnvironmentService.state(): string
	return state
end

function EnvironmentService.snapshot()
	return payload()
end

function EnvironmentService.visionFactor(): number
	return WeatherRules.visionFactor(PW, state)
end

local function roll(): number
	return rng:NextNumber()
end

function EnvironmentService.setState(next: string)
	if not WeatherRules.isState(PW, next) or next == state then
		return
	end
	previous = state
	state = next
	changedAt = now()
	nextChangeAt = changedAt + WeatherRules.duration(PW, roll)
	local S = EnvironmentService.ctx.services
	S.Security.setVisionFactor("weather", EnvironmentService.visionFactor())
	S.Police.setVisionFactor("weather", EnvironmentService.visionFactor())
	Net.event("Weather"):FireAllClients(payload())
end

function EnvironmentService.init(ctx)
	EnvironmentService.ctx = ctx
end

function EnvironmentService.start()
	changedAt = now()
	nextChangeAt = changedAt + WeatherRules.duration(PW, roll)
	Players.PlayerAdded:Connect(function(player)
		Net.event("Weather"):FireClient(player, payload())
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			if now() >= nextChangeAt then
				EnvironmentService.setState(WeatherRules.next(PW, state, roll))
			end
		end
	end)
end

return EnvironmentService
