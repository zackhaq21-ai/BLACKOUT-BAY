--!strict
-- Museum security as a readable world state: 0 Quiet, 1 Suspicious, 2 Alert, 3 Lockdown.
-- Observers (guards, cameras) report exposure per player; loud actions escalate directly.
-- The latest escalation keeps a reason so the player can learn why they were spotted.

export type Level = number

export type Cfg = {
	fillPerSecond: number,
	sneakMultiplier: number,
	decayPerSecond: number,
	suspiciousThreshold: number,
	alertThreshold: number,
	lockdownDelay: number,
	calmSeconds: number,
}

local SecurityState = {}
SecurityState.__index = SecurityState

export type SecurityState = typeof(setmetatable({} :: {
	cfg: Cfg,
	level: Level,
	reason: string?,
	reasonPlayer: string?,
	suspicion: { [string]: { [string]: number } }, -- observer -> player -> 0..1+
	lastReportAt: number,
	alertAt: number?,
	camerasDisabledUntil: number,
	powerCutUntil: number,
	listeners: { (Level, string?, string?) -> () },
}, SecurityState))

SecurityState.Labels = { [0] = "Quiet", [1] = "Suspicious", [2] = "Alert", [3] = "Lockdown" }

function SecurityState.new(cfg: Cfg): SecurityState
	return setmetatable({
		cfg = cfg,
		level = 0,
		suspicion = {},
		lastReportAt = -1e9,
		camerasDisabledUntil = -1,
		powerCutUntil = -1,
		listeners = {},
	}, SecurityState)
end

function SecurityState.onChange(self: SecurityState, fn: (Level, string?, string?) -> ())
	table.insert(self.listeners, fn)
end

local function setLevel(self: SecurityState, level: Level, reason: string?, playerKey: string?, now: number)
	if level == self.level then
		return
	end
	local rising = level > self.level
	self.level = level
	if rising then
		self.reason = reason
		self.reasonPlayer = playerKey
		if level >= 2 then
			self.alertAt = self.alertAt or now
		end
	end
	if level == 0 then
		self.alertAt = nil
		self.reason = nil
		self.reasonPlayer = nil
	end
	for _, fn in ipairs(self.listeners) do
		fn(level, reason, playerKey)
	end
end

-- Observer sees player for dt seconds. Returns the observer's suspicion of that player (0..1).
function SecurityState.report(self: SecurityState, observerId: string, observerLabel: string, playerKey: string, dt: number, sneaking: boolean, now: number): number
	local byObserver = self.suspicion[observerId]
	if not byObserver then
		byObserver = {}
		self.suspicion[observerId] = byObserver
	end
	local rate = self.cfg.fillPerSecond * (if sneaking then self.cfg.sneakMultiplier else 1)
	local v = math.min((byObserver[playerKey] or 0) + rate * dt, 1)
	byObserver[playerKey] = v
	self.lastReportAt = now
	if v >= self.cfg.alertThreshold and self.level < 2 then
		setLevel(self, 2, "Spotted by " .. observerLabel, playerKey, now)
	elseif v >= self.cfg.suspiciousThreshold and self.level < 1 then
		setLevel(self, 1, observerLabel .. " noticed something", playerKey, now)
	end
	return v
end

-- A loud action (smash, drill, alarm trip) is heard. `heardBy` is a label for the reason.
function SecurityState.noise(self: SecurityState, label: string, playerKey: string?, now: number)
	self.lastReportAt = now
	if self.level < 2 then
		setLevel(self, 2, label, playerKey, now)
	end
end

function SecurityState.suspicionOf(self: SecurityState, playerKey: string): (number, string?)
	local best, who = 0, nil
	for observerId, byObserver in pairs(self.suspicion) do
		local v = byObserver[playerKey]
		if v and v > best then
			best, who = v, observerId
		end
	end
	return best, who
end

function SecurityState.camerasActive(self: SecurityState, now: number): boolean
	return now >= self.camerasDisabledUntil and now >= self.powerCutUntil
end

function SecurityState.disableCameras(self: SecurityState, now: number, seconds: number)
	self.camerasDisabledUntil = math.max(self.camerasDisabledUntil, now + seconds)
end

-- Power cut lifts lockdown shutters while active (handled by the caller via powerCutActive).
function SecurityState.cutPower(self: SecurityState, now: number, seconds: number)
	self.powerCutUntil = math.max(self.powerCutUntil, now + seconds)
end

function SecurityState.powerCutActive(self: SecurityState, now: number): boolean
	return now < self.powerCutUntil
end

-- Called every tick. Decays suspicion, applies lockdown delay and calm-down.
function SecurityState.step(self: SecurityState, dt: number, now: number)
	for _, byObserver in pairs(self.suspicion) do
		for playerKey, v in pairs(byObserver) do
			local nv = v - self.cfg.decayPerSecond * dt
			if nv <= 0 then
				byObserver[playerKey] = nil
			else
				byObserver[playerKey] = nv
			end
		end
	end
	if self.level == 2 and self.alertAt and now - self.alertAt >= self.cfg.lockdownDelay then
		setLevel(self, 3, "Lockdown: shutters down", self.reasonPlayer, now)
	end
	if self.level > 0 and now - self.lastReportAt >= self.cfg.calmSeconds then
		-- stand down one level at a time; lockdown releases straight to quiet so a stale shutter never traps a run
		local nextLevel = if self.level == 3 then 0 else self.level - 1
		self.lastReportAt = now
		setLevel(self, nextLevel, nil, nil, now)
	end
end

function SecurityState.reset(self: SecurityState, now: number)
	self.suspicion = {}
	self.alertAt = nil
	self.lastReportAt = -1e9
	setLevel(self, 0, nil, nil, now)
end

return SecurityState
