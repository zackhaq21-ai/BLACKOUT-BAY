--!strict
-- Pure rules for the armored convoy: route choice, cargo state (claimed exactly once), threat escalation,
-- breach eligibility, formation speed, abandonment and the public (client-safe) view. No Roblox APIs.

export type Pt = { x: number, z: number }
export type Route = { name: string, waypoints: { Pt }, checkpoints: { number } }
export type Cfg = {
	AnticipationSeconds: number,
	MaxDurationSeconds: number,
	CooldownSeconds: number,
	CargoValues: { number },
	BreachSeconds: number,
	BlackoutBreachFactor: number,
	LockSeconds: number,
	StopSpeed: number,
	CruiseSpeed: number,
	AlertSpeedFactor: number,
	MinSpawnDistanceFromPlayers: number,
	FormationGap: number,
	AbandonSeconds: number,
}
export type Cargo = { state: "secured" | "minted", lockedUntil: number, mintedAt: number?, by: string?, crates: { string } }
export type Alert = { level: number, since: number, lastThreat: string? }
export type Actor = { alive: boolean, jailed: boolean, seated: boolean, distance: number }

local ConvoyRules = {}

local MAX_CRATES = 5
local MAX_TOTAL = 30000

-- Event definition for WorldEventRules, clamped against bad config.
function ConvoyRules.definition(cfg: Cfg): { id: string, duration: number, cooldown: number }
	local duration = math.clamp(tonumber(cfg.MaxDurationSeconds) or 300, 120, 900)
	local cooldown = math.clamp(tonumber(cfg.CooldownSeconds) or 600, duration, 3600)
	return { id = "convoy", duration = duration, cooldown = cooldown }
end

-- Server-owned crate values. Rejects anything that is not a finite positive number and bounds count/total.
function ConvoyRules.cargoValues(cfg: Cfg): ({ number }?, string?)
	local values = cfg.CargoValues
	if type(values) ~= "table" or #values == 0 then
		return nil, "no cargo configured"
	end
	if #values > MAX_CRATES then
		return nil, "too many crates"
	end
	local out, total = {}, 0
	for _, v in ipairs(values) do
		if type(v) ~= "number" or v ~= v or v == math.huge or v <= 0 then
			return nil, "invalid crate value"
		end
		local whole = math.floor(v)
		total += whole
		table.insert(out, whole)
	end
	if total > MAX_TOTAL then
		return nil, "cargo total too high"
	end
	return out, nil
end

function ConvoyRules.newCargo(): Cargo
	return { state = "secured", lockedUntil = 0, mintedAt = nil, by = nil, crates = {} }
end

-- Choose a route: never the last one, never one whose start is within `minDist` of a player if any other
-- qualifies; ties broken by the rng. Malformed player entries are ignored.
function ConvoyRules.pickRoute(routes: { Route }, lastIndex: number?, players: { Pt }, minDist: number, pick: (number) -> number): number?
	if type(routes) ~= "table" or #routes == 0 then
		return nil
	end
	local function clear(r: Route): boolean
		local s = r.waypoints[1]
		for _, p in ipairs(players) do
			if type(p) == "table" and type(p.x) == "number" and type(p.z) == "number" then
				if (p.x - s.x) ^ 2 + (p.z - s.z) ^ 2 < minDist * minDist then
					return false
				end
			end
		end
		return true
	end
	local preferred, fallback = {}, {}
	for i, r in ipairs(routes) do
		if i ~= lastIndex or #routes == 1 then
			table.insert(fallback, i)
			if clear(r) then
				table.insert(preferred, i)
			end
		end
	end
	local pool = if #preferred > 0 then preferred else fallback
	if #pool == 0 then
		return nil
	end
	return pool[math.clamp(pick(#pool), 1, #pool)]
end

function ConvoyRules.routeLength(route: Route): number
	local len = 0
	for i = 2, #route.waypoints do
		local a, b = route.waypoints[i - 1], route.waypoints[i]
		len += math.abs(b.x - a.x) + math.abs(b.z - a.z)
	end
	return len
end

-- Seconds the breach hold takes right now. The blackout factor applies only while the grid is down.
function ConvoyRules.breachSeconds(cfg: Cfg, gridDown: boolean): number
	local base = math.clamp(tonumber(cfg.BreachSeconds) or 10, 3, 60)
	if not gridDown then
		return base
	end
	local f = tonumber(cfg.BlackoutBreachFactor) or 1
	if f ~= f then
		f = 1
	end
	return math.max(3, base * math.clamp(f, 0.3, 1))
end

-- Who may breach, and when. Returns nil when allowed, else a short reason.
function ConvoyRules.breachRefusal(cfg: Cfg, cargo: Cargo, actor: Actor, transportSpeed: number, now: number): string?
	if cargo.state ~= "secured" then
		return "cargo already taken"
	end
	if not actor.alive then
		return "not alive"
	end
	if actor.jailed then
		return "jailed"
	end
	if actor.seated then
		return "on foot only"
	end
	if actor.distance > 9 then
		return "too far from the doors"
	end
	if transportSpeed >= cfg.StopSpeed then
		return "the transport is moving"
	end
	if now < cargo.lockedUntil then
		return string.format("doors sealed (%d s)", math.ceil(cargo.lockedUntil - now))
	end
	return nil
end

-- The one transition that pays: secured → minted. The second caller, same tick or later, gets false.
function ConvoyRules.claimCargo(cargo: Cargo, by: string, now: number): boolean
	if cargo.state ~= "secured" then
		return false
	end
	cargo.state = "minted"
	cargo.mintedAt = now
	cargo.by = by
	return true
end

-- An interrupted breach seals the doors.
function ConvoyRules.sealDoors(cfg: Cfg, cargo: Cargo, now: number)
	if cargo.state == "secured" then
		cargo.lockedUntil = math.max(cargo.lockedUntil, now + math.clamp(tonumber(cfg.LockSeconds) or 20, 0, 120))
	end
end

-- Threat escalation. Levels: 0 calm, 1 alert, 2 engaged, 3 lockdown. Never decreases during an event.
local THREAT_LEVEL = { seen = 1, block = 1, blockade = 2, breachBegin = 2, ram = 2, damage = 2, breached = 3, crippled = 3 }
function ConvoyRules.newAlert(now: number): Alert
	return { level = 0, since = now, lastThreat = nil }
end

function ConvoyRules.escalate(alert: Alert, threat: string, now: number): boolean
	local lvl = THREAT_LEVEL[threat]
	if not lvl then
		return false
	end
	alert.lastThreat = threat
	if lvl > alert.level then
		alert.level = lvl
		alert.since = now
		return true
	end
	return false
end

-- Cruise speed by alert: calm cruise; alert/engaged faster; lockdown (crippled/breached) the transport stops.
function ConvoyRules.cruiseSpeed(cfg: Cfg, alert: Alert, crippled: boolean): number
	if crippled then
		return 0
	end
	local base = math.clamp(tonumber(cfg.CruiseSpeed) or 26, 8, 60)
	if alert.level >= 1 then
		return math.min(base * math.clamp(tonumber(cfg.AlertSpeedFactor) or 1.3, 1, 2), 60)
	end
	return base
end

-- Planned halts are skipped once the convoy is engaged.
function ConvoyRules.haltsAtCheckpoints(alert: Alert): boolean
	return alert.level < 2
end

-- Follower speed factor from the gap to the vehicle ahead: closes up when far, backs off when close.
function ConvoyRules.followFactor(gap: number, desired: number): number
	if gap < desired * 0.6 then
		return 0
	elseif gap < desired then
		return 0.6
	elseif gap > desired * 2 then
		return 1.35
	end
	return 1
end

-- Loose crate abandonment: dropped and untouched for the window.
function ConvoyRules.abandoned(cfg: Cfg, droppedSince: number, now: number): boolean
	return now - droppedSince >= math.clamp(tonumber(cfg.AbandonSeconds) or 150, 30, 600)
end

-- Rare curated variant: during a Storm the convoy takes the Seawall route with one heavy sealed crate.
-- Not easy money: the carrier is slow, cannot climb or jump, and police heat still applies.
export type StormCfg = { Chance: number, RouteName: string, CargoValue: number, CargoLabel: string }
function ConvoyRules.pickVariant(storm: StormCfg?, weather: string, roll: number): string
	if not storm or weather ~= "Storm" then
		return "standard"
	end
	local chance = math.clamp(tonumber(storm.Chance) or 0, 0, 1)
	return if math.clamp(if roll ~= roll then 1 else roll, 0, 1) < chance then "storm" else "standard"
end

function ConvoyRules.cargoFor(cfg: Cfg, storm: StormCfg?, variant: string): ({ number }?, string, string?)
	if variant == "storm" and storm then
		local v = math.floor(tonumber(storm.CargoValue) or 0)
		if v <= 0 or v > MAX_TOTAL then
			return nil, "Light", "invalid storm cargo"
		end
		return { v }, "Heavy", nil
	end
	local values, err = ConvoyRules.cargoValues(cfg)
	return values, "Light", err
end

function ConvoyRules.routeIndexByName(routes: { Route }, name: string): number?
	for i, r in ipairs(routes) do
		if r.name == name then
			return i
		end
	end
	return nil
end

-- What every client may know. Never includes crate values, the route index or the players' heat.
export type Public = { phase: string, cargo: string, crates: number, alert: number }
function ConvoyRules.publicState(phase: string, cargo: Cargo, alert: Alert, loose: number): Public
	return {
		phase = phase,
		cargo = if cargo.state == "secured" then (if alert.level >= 3 then "sealed" else "secured") else (if loose > 0 then "loose" else "taken"),
		crates = if cargo.state == "secured" then 0 else #cargo.crates,
		alert = alert.level,
	}
end

return ConvoyRules
