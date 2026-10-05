--!strict
-- Pure progression maths: ranks from durable XP ("Standing" to players), option unlocks per rank, award sizing
-- with a crew bonus and per-source daily diminishing. No Roblox APIs.

export type Rank = { id: string, name: string, xp: number }
export type Cfg = {
	Ranks: { Rank },
	Unlocks: { [string]: string },
	UnlockLabels: { [string]: string },
	Awards: { [string]: number },
	CrewBonusPerExtraMember: number,
	Diminish: { [string]: { number } },
	MaxAwardsSeen: number,
	Onboarding: { SkipAfterJobs: number, MoveDistance: number },
}

local Standing = {}

local function num(v: any, fallback: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else fallback
end

function Standing.rankFor(cfg: Cfg, xp: number): Rank
	local x = math.max(0, num(xp, 0))
	local best = cfg.Ranks[1]
	for _, r in ipairs(cfg.Ranks) do
		if x >= r.xp then
			best = r
		end
	end
	return best
end

function Standing.nextRank(cfg: Cfg, xp: number): Rank?
	local x = math.max(0, num(xp, 0))
	for _, r in ipairs(cfg.Ranks) do
		if x < r.xp then
			return r
		end
	end
	return nil
end

function Standing.rankIndex(cfg: Cfg, id: string): number
	for i, r in ipairs(cfg.Ranks) do
		if r.id == id then
			return i
		end
	end
	return 1
end

-- Is the option available at this XP? Unknown keys are available (nothing silently locks).
function Standing.unlocked(cfg: Cfg, xp: number, key: string): boolean
	local need = cfg.Unlocks[key]
	if not need then
		return true
	end
	return Standing.rankIndex(cfg, Standing.rankFor(cfg, xp).id) >= Standing.rankIndex(cfg, need)
end

-- Reason text when locked, else nil.
function Standing.lockReason(cfg: Cfg, xp: number, key: string): string?
	if Standing.unlocked(cfg, xp, key) then
		return nil
	end
	local need = cfg.Ranks[Standing.rankIndex(cfg, cfg.Unlocks[key])]
	return string.format("%s unlocks at %s (%d Standing; you have %d)", cfg.UnlockLabels[key] or key, need.name, need.xp, math.floor(math.max(0, num(xp, 0))))
end

-- Keys unlocked exactly at this rank (for "what did I just unlock" messages).
function Standing.unlocksAt(cfg: Cfg, rankId: string): { string }
	local out = {}
	for key, need in pairs(cfg.Unlocks) do
		if need == rankId then
			table.insert(out, key)
		end
	end
	table.sort(out)
	return out
end

-- Crew bonus multiplier: +X% per present member beyond the first.
function Standing.crewFactor(cfg: Cfg, presentMembers: number): number
	local extra = math.max(0, math.floor(num(presentMembers, 1)) - 1)
	return 1 + extra * math.clamp(num(cfg.CrewBonusPerExtraMember, 0.1), 0, 0.5)
end

-- Diminishing factor for the n-th award of a source today (n is 1-based count BEFORE this award + 1).
function Standing.diminish(cfg: Cfg, source: string, countToday: number): number
	local rule = cfg.Diminish[source]
	if not rule then
		return 1
	end
	local fullCount = math.max(0, math.floor(num(rule[1], 0)))
	local factor = math.clamp(num(rule[2], 1), 0, 1)
	return if math.max(0, math.floor(num(countToday, 0))) < fullCount then 1 else factor
end

-- Base award for a source. Jobs are computed by the caller (value-based); others come from the table.
function Standing.baseAward(cfg: Cfg, source: string): number
	return math.max(0, math.floor(num(cfg.Awards[source], 0)))
end

-- Final award given the stored day counters. Deterministic for a given stored state.
function Standing.award(cfg: Cfg, source: string, base: number, presentMembers: number, countToday: number): number
	local b = math.max(0, math.floor(num(base, 0)))
	return math.floor(b * Standing.crewFactor(cfg, presentMembers) * Standing.diminish(cfg, source, countToday) + 0.5)
end

-- Day key for diminishing windows (UTC date from a unix time).
function Standing.dayKey(unixTime: number): string
	local t = math.max(0, math.floor(num(unixTime, 0)))
	return os.date("!%Y-%m-%d", t)
end

-- Returning players skip onboarding.
function Standing.skipsOnboarding(cfg: Cfg, jobsCompleted: number): boolean
	return math.max(0, num(jobsCompleted, 0)) >= math.max(1, num(cfg.Onboarding.SkipAfterJobs, 1))
end

return Standing
