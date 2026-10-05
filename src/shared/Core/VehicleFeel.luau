--!strict
-- Pure driving-feel maths shared by the seated client and NPC drivers: drive mode, torque curve, steering lock
-- and steering speed by speed, per class (heavy classes are slower-handed). Physics stays in constraints.

export type Tune = { maxSpeed: number, accel: number, brake: number, steer: number, mass: number }
export type Cfg = {
	SteerSpeedAtRest: number, SteerSpeedAtSpeed: number, SteerLockMin: number,
	LowSpeedTorqueBoost: number, HighSpeedTorqueFade: number, CoastDrag: number, ReverseFraction: number,
	BrakeThreshold: number, HeavyMass: number,
}

local VehicleFeel = {}

local function num(v: any, fallback: number): number
	return if type(v) == "number" and v == v then v else fallback
end

-- "drive" | "reverse" | "brake" | "coast": opposite throttle brakes first, reverse only once nearly stopped.
function VehicleFeel.mode(cfg: Cfg, throttle: number, forwardVel: number): string
	throttle = math.clamp(num(throttle, 0), -1, 1)
	forwardVel = num(forwardVel, 0)
	local threshold = math.max(0.5, num(cfg.BrakeThreshold, 4))
	if math.abs(throttle) < 0.05 then
		return "coast"
	end
	if throttle < 0 and forwardVel > threshold then
		return "brake"
	end
	if throttle > 0 and forwardVel < -threshold then
		return "brake"
	end
	return if throttle < 0 then "reverse" else "drive"
end

-- Torque multiplier on the configured accel: strong pulling away, fading toward top speed. Never negative.
function VehicleFeel.torqueFactor(cfg: Cfg, tune: Tune, forwardVel: number): number
	local top = math.max(1, num(tune.maxSpeed, 50))
	local f = math.clamp(math.abs(num(forwardVel, 0)) / top, 0, 1)
	local boost = math.max(1, num(cfg.LowSpeedTorqueBoost, 1.35))
	local fade = math.clamp(num(cfg.HighSpeedTorqueFade, 0.55), 0.2, 1)
	return boost + (fade - boost) * f
end

-- Target wheel speed (studs/s) for a throttle in the given mode.
function VehicleFeel.targetSpeed(cfg: Cfg, tune: Tune, throttle: number, mode: string): number
	local top = math.max(1, num(tune.maxSpeed, 50))
	throttle = math.clamp(num(throttle, 0), -1, 1)
	if mode == "drive" then
		return math.abs(throttle) * top
	elseif mode == "reverse" then
		return -math.abs(throttle) * top * math.clamp(num(cfg.ReverseFraction, 0.4), 0.1, 1)
	end
	return 0
end

function VehicleFeel.isHeavy(cfg: Cfg, tune: Tune): boolean
	return num(tune.mass, 1) >= num(cfg.HeavyMass, 2.5)
end

-- Fraction of full steering lock available at this speed (less lock at speed; heavy classes lose more).
function VehicleFeel.steerLock(cfg: Cfg, tune: Tune, forwardVel: number): number
	local top = math.max(1, num(tune.maxSpeed, 50))
	local f = math.clamp(math.abs(num(forwardVel, 0)) / top, 0, 1)
	local minLock = math.clamp(num(cfg.SteerLockMin, 0.4), 0.2, 1)
	if VehicleFeel.isHeavy(cfg, tune) then
		minLock = math.max(0.2, minLock - 0.1)
	end
	return 1 + (minLock - 1) * f
end

-- Servo angular speed by speed and class: parked cars turn the wheel quickly, heavy trucks slowly.
function VehicleFeel.steerSpeed(cfg: Cfg, tune: Tune, forwardVel: number): number
	local top = math.max(1, num(tune.maxSpeed, 50))
	local f = math.clamp(math.abs(num(forwardVel, 0)) / top, 0, 1)
	local rest = math.clamp(num(cfg.SteerSpeedAtRest, 6), 0.5, 20)
	local fast = math.clamp(num(cfg.SteerSpeedAtSpeed, 2.5), 0.5, rest)
	local s = rest + (fast - rest) * f
	return if VehicleFeel.isHeavy(cfg, tune) then s * 0.6 else s
end

-- Brake-light state for everyone to see: braking, or lifting off above walking pace.
function VehicleFeel.brakeLights(cfg: Cfg, throttle: number, forwardVel: number): boolean
	local mode = VehicleFeel.mode(cfg, throttle, forwardVel)
	return mode == "brake" or (mode == "coast" and math.abs(num(forwardVel, 0)) > 8)
end

return VehicleFeel
