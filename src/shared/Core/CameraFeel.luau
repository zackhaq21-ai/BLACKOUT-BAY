--!strict
-- Pure camera-feel maths: target field of view from the player's state, landing dip from fall speed, and
-- frame-rate independent smoothing. Bounded so no state can produce a sickening camera.

export type Cfg = {
	BaseFov: number, SprintFov: number, SneakFov: number, DownedFov: number, VehicleFovMax: number,
	LandingDipMax: number, LandingDipMinFall: number, LandingDipMaxFall: number,
	FovSmoothing: number, DipRecover: number, SpeedFovStart: number,
}
export type State = { speed: number, topSpeed: number, sprinting: boolean, sneaking: boolean, seated: boolean, vehicleSpeed: number, vehicleTopSpeed: number, downed: boolean }

local CameraFeel = {}

local FOV_MIN, FOV_MAX = 55, 85

local function num(v: any, fallback: number): number
	return if type(v) == "number" and v == v then v else fallback
end

function CameraFeel.targetFov(cfg: Cfg, s: State): number
	local base = num(cfg.BaseFov, 70)
	if s.downed then
		return math.clamp(num(cfg.DownedFov, 62), FOV_MIN, FOV_MAX)
	end
	if s.seated then
		local top = math.max(1, num(s.vehicleTopSpeed, 60))
		local f = math.clamp(num(s.vehicleSpeed, 0) / top, 0, 1)
		local start = math.clamp(num(cfg.SpeedFovStart, 0.35), 0, 0.9)
		local k = math.clamp((f - start) / (1 - start), 0, 1)
		return math.clamp(base + (num(cfg.VehicleFovMax, 82) - base) * k * k, FOV_MIN, FOV_MAX)
	end
	if s.sneaking then
		return math.clamp(num(cfg.SneakFov, 66), FOV_MIN, FOV_MAX)
	end
	if s.sprinting then
		local top = math.max(1, num(s.topSpeed, 21))
		local f = math.clamp(num(s.speed, 0) / top, 0, 1)
		return math.clamp(base + (num(cfg.SprintFov, 76) - base) * f, FOV_MIN, FOV_MAX)
	end
	return math.clamp(base, FOV_MIN, FOV_MAX)
end

-- Camera drop (studs) for a landing at the given downward speed. Soft landings produce nothing.
function CameraFeel.landingDip(cfg: Cfg, fallSpeed: number): number
	local lo = num(cfg.LandingDipMinFall, 18)
	local hi = math.max(lo + 1, num(cfg.LandingDipMaxFall, 70))
	local v = math.abs(num(fallSpeed, 0))
	if v <= lo then
		return 0
	end
	local k = math.clamp((v - lo) / (hi - lo), 0, 1)
	return math.clamp(num(cfg.LandingDipMax, 1.6), 0, 3) * k
end

-- Exponential approach, stable for any dt (no overshoot, no NaN).
function CameraFeel.approach(current: number, target: number, rate: number, dt: number): number
	if current ~= current then
		return target
	end
	local a = 1 - math.exp(-math.max(0, num(rate, 6)) * math.clamp(num(dt, 0), 0, 0.5))
	return current + (target - current) * a
end

return CameraFeel
