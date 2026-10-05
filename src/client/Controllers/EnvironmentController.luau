--!nonstrict
-- Client presentation of the world state: weather look (blended gradually from the server's authoritative
-- state), the blackout's moonlit modifier, storm lightning that lights the environment, rain, wet roads and
-- the graphics tier (bloom, depth of field, shadows, particle rates). Lighting is written here and only here
-- on the client; the server never tweens Lighting.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local WeatherRules = require(ReplicatedStorage.Shared.Core.WeatherRules)
local Vfx = require(script.Parent.Parent.Fx.Vfx)

local EnvironmentController = {}

local PW = Config.Presentation.Weather
local PG = Config.Presentation.Graphics
local audio
local weather = { state = "Clear", previous = "Clear", changedAt = 0, blendSeconds = PW.BlendSeconds }
local blackout = 0 -- 0..1, eased
local blackoutTarget = 0
local tier = "High"
local tierOverride = nil -- nil = Auto
local lightningAt = 0
local lightningBoost = 0
local roadParts = nil
local lastWet = -1
local lastRain = -1
local atmosphere, bloom, dof, clouds
local accum = 0
local rng = Random.new()

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function autoTier(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Medium"
	end
	return "High"
end

function EnvironmentController.tier(): string
	return tierOverride or autoTier()
end

local function applyTier()
	tier = EnvironmentController.tier()
	if bloom then
		bloom.Intensity = PG.Bloom[tier] or 0.35
		bloom.Enabled = (PG.Bloom[tier] or 0) > 0
	end
	if dof then
		dof.Enabled = PG.DepthOfField[tier] == true
	end
	Lighting.GlobalShadows = PG.Shadows[tier] ~= false
	Vfx.setRateScale(PG.Particles[tier] or 1)
	lastRain = -1 -- re-apply rain rate for the new tier
end

-- Cycle Auto → Low → Medium → High → Max → Auto. Returns the label to show.
function EnvironmentController.cycleTier(): string
	local order = { "Auto", "Low", "Medium", "High", "Max" }
	local current = tierOverride or "Auto"
	local i = table.find(order, current) or 1
	local nextName = order[(i % #order) + 1]
	tierOverride = if nextName == "Auto" then nil else nextName
	applyTier()
	return EnvironmentController.tierLabel()
end

function EnvironmentController.tierLabel(): string
	return if tierOverride then tierOverride else ("Auto (" .. autoTier() .. ")")
end

local function ensureEffects()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	bloom = Lighting:FindFirstChild("GlasshouseBloom")
	clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Cover = 0.35
		clouds.Density = 0.5
		clouds.Color = Color3.fromRGB(205, 210, 220)
		clouds.Parent = workspace.Terrain
	end
	dof = Lighting:FindFirstChild("GlasshouseDoF")
	if not dof then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "GlasshouseDoF"
		dof.FarIntensity = 0.12
		dof.FocusDistance = 60
		dof.InFocusRadius = 120
		dof.NearIntensity = 0
		dof.Enabled = false
		dof.Parent = Lighting
	end
end

local function roads(): { BasePart }
	if roadParts then
		return roadParts
	end
	roadParts = {}
	local folder = workspace:FindFirstChild("Glasshouse")
	folder = folder and folder:FindFirstChild("Roads")
	if folder then
		for _, p in ipairs(folder:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "Line" then
				table.insert(roadParts, p)
			end
		end
	end
	return roadParts
end

-- Wet asphalt: a touch of reflectance and a darker tone, never a mirror world
local function applyWet(wet: number)
	local q = math.floor(wet * 10 + 0.5) / 10
	if q == lastWet then
		return
	end
	lastWet = q
	for _, p in ipairs(roads()) do
		p.Reflectance = 0.14 * q
	end
end

local function applyLook(look)
	Lighting.FogStart = look.fogStart
	Lighting.FogEnd = look.fogEnd
	Lighting.FogColor = c3(look.fogColor)
	Lighting.Ambient = c3(look.ambient)
	Lighting.OutdoorAmbient = c3(look.outdoorAmbient)
	Lighting.Brightness = look.brightness + lightningBoost * 1.6
	if lightningBoost > 0 then
		Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(Color3.fromRGB(200, 210, 240), lightningBoost * 0.6)
		Lighting.Ambient = Lighting.Ambient:Lerp(Color3.fromRGB(150, 160, 200), lightningBoost * 0.4)
	end
	if atmosphere then
		atmosphere.Density = look.atmosphereDensity
		atmosphere.Haze = look.atmosphereHaze
		atmosphere.Glare = 0.2 + lightningBoost * 1.5
	end
	if clouds then
		clouds.Cover = look.cloudCover
		clouds.Density = look.cloudDensity
		clouds.Color = Color3.fromRGB(205, 210, 220):Lerp(Color3.fromRGB(240, 240, 250), lightningBoost)
	end
	local rainQ = math.floor(look.rain * 20 + 0.5) / 20
	if rainQ ~= lastRain then
		lastRain = rainQ
		Vfx.setRain(rainQ, PG.RainRate[tier] or 200)
		if audio then
			audio.setWeather(rainQ, weather.state == "Storm")
		end
	end
	applyWet(look.wet)
end

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	local t = if weather.blendSeconds > 0 then math.clamp((now - weather.changedAt) / weather.blendSeconds, 0, 1) else 1
	-- blackout eases in fast, recovers slowly
	local rate = if blackoutTarget > blackout then 2.2 else 0.6
	blackout += (blackoutTarget - blackout) * math.min(1, rate * dt)
	-- lightning: brief environment illumination during storms, never a full-screen flash
	if weather.state == "Storm" and t > 0.5 then
		if now >= lightningAt then
			lightningAt = now + WeatherRules.lightningGap(PW, function()
				return rng:NextNumber()
			end)
			lightningBoost = 1
		end
	end
	lightningBoost = math.max(0, lightningBoost - dt * 5)
	local look = WeatherRules.blend(WeatherRules.look(weather.previous), WeatherRules.look(weather.state), t, blackout)
	applyLook(look)
	local cam = workspace.CurrentCamera
	if cam then
		Vfx.stepRain(cam.CFrame.Position)
	end
end

function EnvironmentController.init(audioController)
	audio = audioController
	ensureEffects()
	applyTier()
	Net.event("Weather").OnClientEvent:Connect(function(w)
		if type(w) ~= "table" or type(w.state) ~= "string" or not WeatherRules.isState(PW, w.state) then
			return
		end
		weather.previous = if WeatherRules.isState(PW, tostring(w.previous)) then w.previous else weather.state
		weather.state = w.state
		weather.changedAt = if type(w.changedAt) == "number" then w.changedAt else workspace:GetServerTimeNow()
		weather.blendSeconds = math.clamp(tonumber(w.blendSeconds) or PW.BlendSeconds, 0, 120)
	end)
	Net.event("WorldEvent").OnClientEvent:Connect(function(e)
		if type(e) == "table" and e.id == "blackout" then
			blackoutTarget = if e.active then 1 else 0
		end
	end)
	-- Throttled: the look changes slowly; 20 Hz is plenty and keeps RenderStepped for the camera
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum >= 0.05 then
			step(accum)
			accum = 0
		end
	end)
end

function EnvironmentController.applyBootstrap(b)
	if type(b.weather) == "table" and WeatherRules.isState(PW, tostring(b.weather.state)) then
		weather.state = b.weather.state
		weather.previous = b.weather.state
		weather.changedAt = 0
	end
	if type(b.worldEvents) == "table" and b.worldEvents.blackout and b.worldEvents.blackout.active then
		blackoutTarget = 1
		blackout = 1
	end
end

return EnvironmentController
