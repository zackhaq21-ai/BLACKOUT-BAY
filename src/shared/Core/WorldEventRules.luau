--!strict
-- Server-authoritative world-event state machine (pure): one active instance per event id, bounded
-- duration, per-event cooldown, explicit end reasons. Services register handlers around this.

export type Def = { id: string, duration: number, cooldown: number }
export type Active = { id: string, startedAt: number, endsAt: number, startedBy: string?, data: any? }

local WorldEventRules = {}
WorldEventRules.__index = WorldEventRules

export type WorldEventRules = typeof(setmetatable({} :: {
	defs: { [string]: Def },
	active: { [string]: Active },
	lastEndedAt: { [string]: number },
}, WorldEventRules))

function WorldEventRules.new(defs: { Def }): WorldEventRules
	local map: { [string]: Def } = {}
	for _, d in ipairs(defs) do
		map[d.id] = d
	end
	return setmetatable({ defs = map, active = {}, lastEndedAt = {} }, WorldEventRules)
end

function WorldEventRules.canStart(self: WorldEventRules, id: string, now: number): (boolean, string?)
	local def = self.defs[id]
	if not def then
		return false, "unknown event"
	end
	if self.active[id] then
		return false, "already active"
	end
	local last = self.lastEndedAt[id]
	if last and now - last < def.cooldown then
		return false, string.format("cooling down (%d s)", math.ceil(def.cooldown - (now - last)))
	end
	return true, nil
end

function WorldEventRules.start(self: WorldEventRules, id: string, now: number, startedBy: string?, data: any?): (Active?, string?)
	local ok, err = self:canStart(id, now)
	if not ok then
		return nil, err
	end
	local def = self.defs[id]
	local a: Active = { id = id, startedAt = now, endsAt = now + def.duration, startedBy = startedBy, data = data }
	self.active[id] = a
	return a, nil
end

-- Ends an active event now (expiry, counterplay, shutdown). Returns the instance that ended.
function WorldEventRules.stop(self: WorldEventRules, id: string, now: number): Active?
	local a = self.active[id]
	if not a then
		return nil
	end
	self.active[id] = nil
	self.lastEndedAt[id] = now
	return a
end

-- Expire due events. Returns the list of ended instances.
function WorldEventRules.step(self: WorldEventRules, now: number): { Active }
	local ended = {}
	for id, a in pairs(self.active) do
		if now >= a.endsAt then
			table.insert(ended, a)
			self.active[id] = nil
			self.lastEndedAt[id] = now
		end
	end
	return ended
end

function WorldEventRules.get(self: WorldEventRules, id: string): Active?
	return self.active[id]
end

function WorldEventRules.secondsLeft(self: WorldEventRules, id: string, now: number): number
	local a = self.active[id]
	return if a then math.max(0, a.endsAt - now) else 0
end

return WorldEventRules
