--!nonstrict
-- Lightweight pooled VFX: a handful of one-shot emitters reused for every burst, tier-scaled rates, and one
-- rain emitter that rides above the camera. Effects communicate gameplay first; nothing here is permanent.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)

local Vfx = {}

local POOL_SIZE = 10
local pool = {} -- { attachment, emitter, busyUntil }
local rateScale = 1
local rainRate = 0
local rain -- { part, emitter }

local PRESETS = {
	Dust = { color = Palette.PaleStone, size = NumberSequence.new(1.2, 3), life = NumberRange.new(0.5, 0.9), speed = NumberRange.new(3, 6), spread = Vector2.new(60, 60), count = 10, transparency = NumberSequence.new(0.5, 1), light = 0 },
	Sparks = { color = Palette.SecurityAmber, size = NumberSequence.new(0.35, 0.05), life = NumberRange.new(0.25, 0.6), speed = NumberRange.new(12, 24), spread = Vector2.new(90, 90), count = 24, transparency = NumberSequence.new(0, 1), light = 0.6 },
	Glint = { color = Palette.Gold, size = NumberSequence.new(0.6, 0), life = NumberRange.new(0.4, 0.7), speed = NumberRange.new(2, 5), spread = Vector2.new(180, 180), count = 12, transparency = NumberSequence.new(0.1, 1), light = 0.3 },
	Smoke = { color = Palette.Industrial, size = NumberSequence.new(2, 6), life = NumberRange.new(1, 1.8), speed = NumberRange.new(2, 4), spread = Vector2.new(30, 30), count = 8, transparency = NumberSequence.new(0.4, 1), light = 0 },
	Electric = { color = Palette.NeonCyan, size = NumberSequence.new(0.5, 0.1), life = NumberRange.new(0.2, 0.5), speed = NumberRange.new(8, 18), spread = Vector2.new(180, 180), count = 30, transparency = NumberSequence.new(0, 1), light = 1 },
	Glass = { color = Palette.Glass, size = NumberSequence.new(0.4, 0.1), life = NumberRange.new(0.4, 0.9), speed = NumberRange.new(6, 14), spread = Vector2.new(70, 70), count = 20, transparency = NumberSequence.new(0.2, 1), light = 0 },
	Splash = { color = Palette.Glass, size = NumberSequence.new(0.8, 0.2), life = NumberRange.new(0.3, 0.6), speed = NumberRange.new(4, 9), spread = Vector2.new(80, 80), count = 10, transparency = NumberSequence.new(0.4, 1), light = 0 },
}

local function slot()
	local best, bestT = nil, math.huge
	local now = os.clock()
	for _, s in ipairs(pool) do
		if s.busyUntil <= now then
			return s
		end
		if s.busyUntil < bestT then
			best, bestT = s, s.busyUntil
		end
	end
	return best
end

function Vfx.init()
	for _ = 1, POOL_SIZE do
		local a = Instance.new("Attachment")
		a.Name = "VfxSlot"
		a.Parent = Workspace.Terrain
		local e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.Rate = 0
		e.Parent = a
		local l = Instance.new("PointLight")
		l.Brightness = 0
		l.Range = 10
		l.Enabled = false
		l.Parent = a
		table.insert(pool, { attachment = a, emitter = e, light = l, busyUntil = 0 })
	end
end

function Vfx.setRateScale(scale: number)
	rateScale = math.clamp(scale, 0, 2)
	if rain then
		rain.emitter.Rate = rainRate * rateScale
	end
end

-- One-shot burst at a world position. Returns quickly; the slot frees itself after the particles die.
function Vfx.burst(kind: string, position: Vector3, scale: number?)
	local p = PRESETS[kind]
	local s = slot()
	if not p or not s or rateScale <= 0 then
		return
	end
	local k = (scale or 1) * rateScale
	s.attachment.WorldPosition = position
	local e = s.emitter
	e.Color = ColorSequence.new(p.color)
	e.Size = p.size
	e.Lifetime = p.life
	e.Speed = p.speed
	e.SpreadAngle = p.spread
	e.Transparency = p.transparency
	e.LightEmission = p.light
	e.Acceleration = if kind == "Smoke" then Vector3.new(0, 3, 0) else Vector3.new(0, -14, 0)
	e.Drag = 2
	e:Emit(math.max(1, math.floor(p.count * k)))
	if p.light > 0 then
		s.light.Color = p.color
		s.light.Brightness = 1.5 * k
		s.light.Enabled = true
		task.delay(0.15, function()
			s.light.Enabled = false
		end)
	end
	s.busyUntil = os.clock() + p.life.Max
end

-- Rain follows the camera; intensity 0..1 scaled by the graphics tier rate.
function Vfx.setRain(intensity: number, tierRate: number)
	rainRate = math.clamp(intensity, 0, 1) * tierRate
	if rainRate <= 0 then
		if rain then
			rain.emitter.Enabled = false
		end
		return
	end
	if not rain then
		local part = Instance.new("Part")
		part.Name = "RainVolume"
		part.Size = Vector3.new(90, 1, 90)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.CastShadow = false
		part.Parent = Workspace.Terrain
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Color3.fromRGB(190, 210, 225))
		e.Size = NumberSequence.new(0.08)
		e.Transparency = NumberSequence.new(0.35, 0.7)
		e.Lifetime = NumberRange.new(0.9, 1.1)
		e.Speed = NumberRange.new(70, 85)
		e.Rate = 0
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Acceleration = Vector3.new(0, -40, 0)
		e.Drag = 0
		e.LightInfluence = 0.3
		e.Parent = part
		rain = { part = part, emitter = e }
	end
	rain.emitter.Rate = rainRate * rateScale
	rain.emitter.Enabled = true
end

function Vfx.stepRain(cameraPosition: Vector3)
	if rain and rain.emitter.Enabled then
		rain.part.CFrame = CFrame.new(cameraPosition + Vector3.new(0, 55, 0))
	end
end

return Vfx
