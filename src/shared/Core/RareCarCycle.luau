--!strict
-- Weekly rare-car cycle for ONE server. Pure logic: the heist is completable once per week per
-- server, one circulating car, ownership transfers through a 120-second break-in that can be
-- interrupted, transfers never duplicate the car nor reopen the heist, and the weekly reset
-- returns the car and reopens the heist. Persistence across server restarts is NOT solved here
-- (see docs/DESIGN.md "Rare car persistence" for the open decision).

export type Cfg = { weekAnchorUnix: number, weekSeconds: number, breakInSeconds: number }

export type Location = "HeistSite" | "Owned" | "Stored"

local RareCarCycle = {}
RareCarCycle.__index = RareCarCycle

export type RareCarCycle = typeof(setmetatable({} :: {
	cfg: Cfg,
	week: number,
	heistCompleted: boolean,
	owner: string?,
	location: Location,
	breakIn: { thief: string, startedAt: number }?,
	log: { string },
}, RareCarCycle))

function RareCarCycle.weekOf(cfg: Cfg, nowUnix: number): number
	return math.floor((nowUnix - cfg.weekAnchorUnix) / cfg.weekSeconds)
end

function RareCarCycle.secondsUntilReset(cfg: Cfg, nowUnix: number): number
	local week = RareCarCycle.weekOf(cfg, nowUnix)
	return cfg.weekAnchorUnix + (week + 1) * cfg.weekSeconds - nowUnix
end

function RareCarCycle.new(cfg: Cfg, nowUnix: number): RareCarCycle
	return setmetatable({
		cfg = cfg,
		week = RareCarCycle.weekOf(cfg, nowUnix),
		heistCompleted = false,
		owner = nil,
		location = "HeistSite" :: Location,
		breakIn = nil,
		log = {},
	}, RareCarCycle)
end

local function note(self: RareCarCycle, s: string)
	table.insert(self.log, s)
end

-- Call every tick. Applies the weekly reset exactly once per week boundary.
function RareCarCycle.step(self: RareCarCycle, nowUnix: number): boolean
	local week = RareCarCycle.weekOf(self.cfg, nowUnix)
	if week ~= self.week then
		self.week = week
		self.heistCompleted = false
		self.owner = nil
		self.location = "HeistSite"
		self.breakIn = nil -- an in-progress theft is cancelled by the reset
		note(self, "weekly reset: car returned to the heist site")
		return true
	end
	return false
end

function RareCarCycle.heistAvailable(self: RareCarCycle): boolean
	return not self.heistCompleted and self.location == "HeistSite"
end

function RareCarCycle.completeHeist(self: RareCarCycle, thief: string): (boolean, string?)
	if not self:heistAvailable() then
		return false, "heist already completed this week"
	end
	self.heistCompleted = true
	self.owner = thief
	self.location = "Owned"
	note(self, thief .. " stole the car from the heist site")
	return true, nil
end

function RareCarCycle.store(self: RareCarCycle, by: string): (boolean, string?)
	if self.owner ~= by then
		return false, "not the owner"
	end
	if self.breakIn then
		return false, "break-in in progress"
	end
	self.location = "Stored"
	return true, nil
end

function RareCarCycle.takeOut(self: RareCarCycle, by: string): (boolean, string?)
	if self.owner ~= by then
		return false, "not the owner"
	end
	if self.breakIn then
		return false, "break-in in progress"
	end
	self.location = "Owned"
	return true, nil
end

function RareCarCycle.beginBreakIn(self: RareCarCycle, thief: string, nowUnix: number): (boolean, string?)
	if not self.owner then
		return false, "nobody owns the car"
	end
	if thief == self.owner then
		return false, "owner cannot break into own car"
	end
	if self.breakIn then
		return false, "someone is already breaking in"
	end
	self.breakIn = { thief = thief, startedAt = nowUnix }
	note(self, thief .. " started a break-in")
	return true, nil
end

-- Interruption rules: the break-in is cancelled if the thief stops (leaves range, dies, logs out)
-- or the owner/anyone interrupts it. Progress is not banked: a new attempt restarts at zero.
function RareCarCycle.interruptBreakIn(self: RareCarCycle, reason: string): boolean
	if not self.breakIn then
		return false
	end
	note(self, self.breakIn.thief .. "'s break-in interrupted: " .. reason)
	self.breakIn = nil
	return true
end

function RareCarCycle.breakInProgress(self: RareCarCycle, nowUnix: number): number
	if not self.breakIn then
		return 0
	end
	return math.clamp((nowUnix - self.breakIn.startedAt) / self.cfg.breakInSeconds, 0, 1)
end

-- Returns true when the transfer happened on this call.
function RareCarCycle.tryCompleteBreakIn(self: RareCarCycle, nowUnix: number): (boolean, string?)
	local b = self.breakIn
	if not b then
		return false, nil
	end
	if nowUnix - b.startedAt < self.cfg.breakInSeconds then
		return false, nil
	end
	local previous = self.owner
	self.owner = b.thief
	self.location = "Owned"
	self.breakIn = nil
	note(self, b.thief .. " took the car from " .. tostring(previous))
	return true, previous
end

return RareCarCycle
