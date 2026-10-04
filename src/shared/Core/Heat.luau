--!strict
-- Police heat per player, separate from the museum's local alarm. Heat only decays while the
-- player is unseen. Vehicles seen with a wanted driver become "recognized" for a while, so
-- swapping drivers is not a free escape and pursuers can read the situation.

export type Cfg = { heatPerLevel: number, maxHeat: number, decayPerSecond: number, unseenGrace: number, recognitionSeconds: number }

local Heat = {}
Heat.__index = Heat

export type Entry = { heat: number, lastSeenAt: number, lastReason: string? }

export type Heat = typeof(setmetatable({} :: {
	cfg: Cfg,
	players: { [string]: Entry },
	vehicles: { [string]: number }, -- vehicle key -> recognized until
	listeners: { (string, number, number, string?) -> () },
}, Heat))

Heat.Labels = { [0] = "No attention", [1] = "Police notified", [2] = "Active pursuit", [3] = "Citywide pursuit" }

function Heat.new(cfg: Cfg): Heat
	return setmetatable({ cfg = cfg, players = {}, vehicles = {}, listeners = {} }, Heat)
end

function Heat.onLevelChange(self: Heat, fn: (string, number, number, string?) -> ())
	table.insert(self.listeners, fn)
end

local function entry(self: Heat, key: string): Entry
	local e = self.players[key]
	if not e then
		local ne: Entry = { heat = 0, lastSeenAt = -1e9, lastReason = nil }
		self.players[key] = ne
		e = ne
	end
	return e
end

function Heat.levelOf(self: Heat, key: string): number
	local e = self.players[key]
	if not e then
		return 0
	end
	return math.min(3, math.floor(e.heat / self.cfg.heatPerLevel))
end

function Heat.heatOf(self: Heat, key: string): number
	local e = self.players[key]
	return if e then e.heat else 0
end

local function setHeat(self: Heat, key: string, value: number, reason: string?)
	local e = entry(self, key)
	local before = self:levelOf(key)
	e.heat = math.clamp(value, 0, self.cfg.maxHeat)
	if reason then
		e.lastReason = reason
	end
	local after = self:levelOf(key)
	if after ~= before then
		for _, fn in ipairs(self.listeners) do
			fn(key, before, after, reason)
		end
	end
end

function Heat.add(self: Heat, key: string, amount: number, reason: string, now: number)
	local e = entry(self, key)
	e.lastSeenAt = now
	setHeat(self, key, e.heat + amount, reason)
end

function Heat.seen(self: Heat, key: string, now: number)
	entry(self, key).lastSeenAt = now
end

function Heat.clear(self: Heat, key: string, reason: string?)
	setHeat(self, key, 0, reason)
end

function Heat.remove(self: Heat, key: string)
	self.players[key] = nil
end

function Heat.recognizeVehicle(self: Heat, vehicleKey: string, now: number)
	self.vehicles[vehicleKey] = now + self.cfg.recognitionSeconds
end

function Heat.isVehicleRecognized(self: Heat, vehicleKey: string, now: number): boolean
	local until_ = self.vehicles[vehicleKey]
	return until_ ~= nil and now < until_
end

function Heat.step(self: Heat, dt: number, now: number)
	for key, e in pairs(self.players) do
		if e.heat > 0 and now - e.lastSeenAt >= self.cfg.unseenGrace then
			setHeat(self, key, e.heat - self.cfg.decayPerSecond * dt, nil)
		end
	end
	for v, until_ in pairs(self.vehicles) do
		if now >= until_ then
			self.vehicles[v] = nil
		end
	end
end

function Heat.wanted(self: Heat): { string }
	local out = {}
	for key in pairs(self.players) do
		if self:levelOf(key) > 0 then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

return Heat
