--!strict
-- Pure weather state machine and presentation targets. The server picks states; clients blend the look.
-- Readability invariants: fog never closes in past 260 studs, ambient never goes black, vision factor ≥ 0.5.

export type Cfg = {
	States: { string },
	MinSeconds: number,
	MaxSeconds: number,
	BlendSeconds: number,
	Weights: { [string]: number },
	Vision: { [string]: number },
	LightningMinGap: number,
	LightningMaxGap: number,
}
export type Look = {
	fogStart: number,
	fogEnd: number,
	fogColor: { number },
	ambient: { number },
	outdoorAmbient: { number },
	brightness: number,
	atmosphereDensity: number,
	atmosphereHaze: number,
	cloudCover: number,
	cloudDensity: number,
	rain: number, -- 0..1
	wet: number, -- 0..1 surface wetness
}

local WeatherRules = {}

local LOOKS: { [string]: Look } = {
	Clear = { fogStart = 400, fogEnd = 1700, fogColor = { 92, 115, 140 }, ambient = { 56, 60, 76 }, outdoorAmbient = { 78, 86, 108 }, brightness = 2, atmosphereDensity = 0.32, atmosphereHaze = 1.4, cloudCover = 0.35, cloudDensity = 0.5, rain = 0, wet = 0 },
	Overcast = { fogStart = 300, fogEnd = 1400, fogColor = { 84, 96, 112 }, ambient = { 52, 56, 68 }, outdoorAmbient = { 72, 78, 92 }, brightness = 1.6, atmosphereDensity = 0.38, atmosphereHaze = 1.8, cloudCover = 0.8, cloudDensity = 0.7, rain = 0, wet = 0.15 },
	Rain = { fogStart = 220, fogEnd = 1100, fogColor = { 70, 80, 96 }, ambient = { 48, 52, 64 }, outdoorAmbient = { 66, 72, 88 }, brightness = 1.4, atmosphereDensity = 0.42, atmosphereHaze = 2.2, cloudCover = 0.9, cloudDensity = 0.85, rain = 0.7, wet = 0.8 },
	Storm = { fogStart = 160, fogEnd = 900, fogColor = { 56, 62, 78 }, ambient = { 42, 46, 60 }, outdoorAmbient = { 58, 64, 82 }, brightness = 1.2, atmosphereDensity = 0.48, atmosphereHaze = 2.6, cloudCover = 1, cloudDensity = 1, rain = 1, wet = 1 },
	Fog = { fogStart = 60, fogEnd = 420, fogColor = { 110, 122, 136 }, ambient = { 60, 64, 76 }, outdoorAmbient = { 86, 92, 108 }, brightness = 1.3, atmosphereDensity = 0.6, atmosphereHaze = 3, cloudCover = 0.7, cloudDensity = 0.6, rain = 0, wet = 0.3 },
}

-- Blackout at night: a moonlit modifier applied on top of the weather look (never black).
local BLACKOUT = { ambient = { 26, 30, 46 }, outdoorAmbient = { 38, 46, 72 }, brightness = 0.9, fogColor = { 40, 52, 74 } }

function WeatherRules.look(state: string): Look
	return LOOKS[state] or LOOKS.Clear
end

function WeatherRules.isState(cfg: Cfg, state: string): boolean
	return table.find(cfg.States, state) ~= nil
end

-- Weighted pick of a different state. `roll` returns a number in [0, 1).
function WeatherRules.next(cfg: Cfg, current: string, roll: () -> number): string
	local total = 0
	for _, s in ipairs(cfg.States) do
		if s ~= current then
			total += math.max(0, cfg.Weights[s] or 1)
		end
	end
	if total <= 0 then
		return current
	end
	local r = math.clamp(roll(), 0, 0.999999) * total
	for _, s in ipairs(cfg.States) do
		if s ~= current then
			r -= math.max(0, cfg.Weights[s] or 1)
			if r < 0 then
				return s
			end
		end
	end
	return current
end

function WeatherRules.duration(cfg: Cfg, roll: () -> number): number
	local lo = math.clamp(tonumber(cfg.MinSeconds) or 240, 60, 1800)
	local hi = math.clamp(tonumber(cfg.MaxSeconds) or 540, lo, 3600)
	return lo + (hi - lo) * math.clamp(roll(), 0, 1)
end

function WeatherRules.visionFactor(cfg: Cfg, state: string): number
	local v = cfg.Vision[state]
	if type(v) ~= "number" or v ~= v then
		return 1
	end
	return math.clamp(v, 0.5, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerp3(a: { number }, b: { number }, t: number): { number }
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

-- Blend two looks (t in [0,1]) and apply the blackout modifier (0..1). Enforces readability bounds.
function WeatherRules.blend(from: Look, to: Look, t: number, blackout: number): Look
	t = math.clamp(if t ~= t then 1 else t, 0, 1)
	blackout = math.clamp(if blackout ~= blackout then 0 else blackout, 0, 1)
	local out: Look = {
		fogStart = lerp(from.fogStart, to.fogStart, t),
		fogEnd = math.max(260, lerp(from.fogEnd, to.fogEnd, t)),
		fogColor = lerp3(lerp3(from.fogColor, to.fogColor, t), BLACKOUT.fogColor, blackout),
		ambient = lerp3(lerp3(from.ambient, to.ambient, t), BLACKOUT.ambient, blackout),
		outdoorAmbient = lerp3(lerp3(from.outdoorAmbient, to.outdoorAmbient, t), BLACKOUT.outdoorAmbient, blackout),
		brightness = lerp(lerp(from.brightness, to.brightness, t), BLACKOUT.brightness, blackout),
		atmosphereDensity = lerp(from.atmosphereDensity, to.atmosphereDensity, t),
		atmosphereHaze = lerp(from.atmosphereHaze, to.atmosphereHaze, t),
		cloudCover = lerp(from.cloudCover, to.cloudCover, t),
		cloudDensity = lerp(from.cloudDensity, to.cloudDensity, t),
		rain = lerp(from.rain, to.rain, t),
		wet = lerp(from.wet, to.wet, t),
	}
	for i = 1, 3 do
		out.ambient[i] = math.max(out.ambient[i], 20)
		out.outdoorAmbient[i] = math.max(out.outdoorAmbient[i], 28)
	end
	out.fogStart = math.min(out.fogStart, out.fogEnd - 120)
	return out
end

-- Seconds until the next lightning strike during a storm.
function WeatherRules.lightningGap(cfg: Cfg, roll: () -> number): number
	local lo = math.clamp(tonumber(cfg.LightningMinGap) or 6, 2, 60)
	local hi = math.clamp(tonumber(cfg.LightningMaxGap) or 18, lo, 120)
	return lo + (hi - lo) * math.clamp(roll(), 0, 1)
end

return WeatherRules
