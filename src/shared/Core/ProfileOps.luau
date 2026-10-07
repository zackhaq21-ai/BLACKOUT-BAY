--!strict
-- Pure, merge-safe profile operations, carried over from the Studio-tested prototype's ProfileModel and
-- adapted to this profile schema. Ops are applied to the STORED value inside UpdateAsync (never a stale
-- full profile), so XP, wins, entitlements and receipts cannot be lost or duplicated:
--   Run      {id, xp, won, source?, day?}  credited once per run id; diminished per source per day when day is given
--   Standing {id, source, xp, day}         award credited once per id; diminished per source per day
--   Onboarding {step}                      first-session step, monotonic
--   Accomplish {id, xp}                    accomplishment once per id; credits its own Standing plain
--   Entry      {entry}                     museum entry seen (front/dock/roof), set once
--   Receipt  {receipt, item}    entitlement + receipt committed together, idempotent per receipt
--   Pass     {item}             ownership confirmed by Roblox (game pass)
--   Equip    {item}             only owned items; never changes stats

export type CatalogItem = { Id: string, Name: string, Kind: string, EarnedXP: number | boolean, PassId: number, ProductId: number, Color: { number } }

export type Op = { kind: string, id: string?, xp: number?, won: boolean?, receipt: string?, item: string?, source: string?, day: string?, step: number? }

local ProfileOps = {}

-- Progression dependencies are injected (ProfileOps.configure) so this module stays free of require paths
-- and the CLI tests, the server and Studio all use the same code. Without them, awards are credited plain.
ProfileOps.deps = { Standing = nil :: any, Onboarding = nil :: any, config = nil :: any }
ProfileOps.progressionConfig = nil :: any

function ProfileOps.configure(standing: any, onboarding: any, config: any)
	ProfileOps.deps = { Standing = standing, Onboarding = onboarding, config = config }
	ProfileOps.progressionConfig = config
end

local function ensureStanding(p: any)
	if type(p.awardsSeen) ~= "table" then
		p.awardsSeen = {}
	end
	if type(p.standingDay) ~= "table" or type(p.standingDay.counts) ~= "table" then
		p.standingDay = { day = "", counts = {} }
	end
	if type(p.onboarding) ~= "table" then
		p.onboarding = { step = 1, done = false }
	end
	if type(p.accomplishments) ~= "table" then
		p.accomplishments = {}
	end
	if type(p.entries) ~= "table" then
		p.entries = {}
	end
end

local function clampStep(step: any): number
	if type(step) ~= "number" or step ~= step or step < 1 then
		return 1
	end
	return math.floor(math.min(step, 6))
end

-- Daily counter for a source; rolls the day over and prunes the awardsSeen set when it grows.
local function bump(p: any, source: string, day: string?): number
	ensureStanding(p)
	local sd = p.standingDay
	if day and sd.day ~= day then
		sd.day = day
		sd.counts = {}
	end
	local before = sd.counts[source] or 0
	sd.counts[source] = before + 1
	return before
end

local function prune(p: any, day: string?)
	local cfg = ProfileOps.progressionConfig
	local maxSeen = cfg and cfg.MaxAwardsSeen or 400
	local n = 0
	for _ in pairs(p.awardsSeen) do
		n += 1
	end
	if n <= maxSeen or not day then
		return
	end
	for id, seenDay in pairs(p.awardsSeen) do
		if type(seenDay) ~= "string" or seenDay < day then
			p.awardsSeen[id] = nil
		end
	end
end

local function diminished(p: any, source: string?, xp: number, day: string?, presentMembers: number?): number
	local cfg = ProfileOps.progressionConfig
	local Standing = ProfileOps.deps.Standing
	if not cfg or not Standing or not source then
		return math.max(0, math.floor(if xp == xp then xp else 0))
	end
	local count = bump(p, source, day)
	return Standing.award(cfg, source, xp, presentMembers or 1, count)
end

local function applyEarned(p: any, catalog: { CatalogItem })
	for _, item in ipairs(catalog) do
		if type(item.EarnedXP) == "number" and p.xp >= item.EarnedXP then
			p.entitlements[item.Id] = true
		end
	end
end

-- Mutates and returns `p` (a migrated profile data table). Returns (p, changed).
function ProfileOps.apply(p: any, op: Op, catalog: { CatalogItem }): (any, boolean)
	local changed = false
	ensureStanding(p)
	if op.kind == "Run" and type(op.id) == "string" and type(op.xp) == "number" then
		if not p.runsSeen[op.id] then
			p.runsSeen[op.id] = true
			p.xp += diminished(p, if op.source then op.source else "job", op.xp, op.day, (op :: any).members)
			p.stats.jobs += 1
			if op.won then
				p.wins += 1
			end
			changed = true
		end
	elseif op.kind == "Standing" and type(op.id) == "string" and type(op.source) == "string" and type(op.xp) == "number" and op.xp == op.xp then
		if not p.awardsSeen[op.id] then
			p.awardsSeen[op.id] = op.day or "?"
			p.xp += diminished(p, op.source, op.xp, op.day, (op :: any).members)
			prune(p, op.day)
			changed = true
		end
	elseif op.kind == "Accomplish" and type(op.id) == "string" and #op.id <= 40 and type(op.xp) == "number" and op.xp == op.xp then
		if not p.accomplishments[op.id] then
			p.accomplishments[op.id] = op.day or "?"
			p.xp += math.max(0, math.min(100000, math.floor(op.xp)))
			changed = true
		end
	elseif op.kind == "Entry" and type(op.item) == "string" and (op.item == "front" or op.item == "dock" or op.item == "roof") then
		if not p.entries[op.item] then
			p.entries[op.item] = true
			changed = true
		end
	elseif op.kind == "Onboarding" and type(op.step) == "number" then
		local target = clampStep(op.step)
		local current = clampStep(p.onboarding.step)
		if target > current then
			p.onboarding = { step = target, done = target >= 6 }
			changed = true
		end
	elseif op.kind == "Receipt" and type(op.receipt) == "string" and type(op.item) == "string" then
		if not p.receipts[op.receipt] then
			p.receipts[op.receipt] = true
			p.entitlements[op.item] = true
			changed = true
		end
	elseif op.kind == "Pass" and type(op.item) == "string" then
		if not p.entitlements[op.item] then
			p.entitlements[op.item] = true
			changed = true
		end
	elseif op.kind == "Equip" and type(op.item) == "string" then
		for _, item in ipairs(catalog) do
			if item.Id == op.item and p.entitlements[item.Id] then
				local slot = if item.Kind == "Decor" then "decor" else "equipped"
				if p[slot] ~= item.Id then
					p[slot] = item.Id
					changed = true
				end
			end
		end
	end
	applyEarned(p, catalog)
	return p, changed
end

-- Entitlements are permanent: nothing in a raid or a lost run may remove them.
function ProfileOps.owns(p: any, itemId: string): boolean
	return p.entitlements[itemId] == true
end

function ProfileOps.find(catalog: { CatalogItem }, itemId: string): CatalogItem?
	for _, item in ipairs(catalog) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

return ProfileOps
