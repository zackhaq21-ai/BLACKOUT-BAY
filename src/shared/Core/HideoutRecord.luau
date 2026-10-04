--!strict
-- The persisted hideout record and the pure transforms applied to it inside UpdateAsync.
-- One record per owner. Every change to the stash or the raid lock goes through these functions on the
-- stored value, never on a cached copy, so two servers, two attackers, or a reconnecting owner can never
-- each spend the same money. Transforms return (newRecord | nil to abort, result).

export type Clue = { t: number, text: string }

export type Report = {
	t: number,
	raidId: string?,
	raider: string,
	raiderName: string,
	crewNames: { string },
	entry: string,
	defences: { string },
	lost: number,
	retained: number,
	recovered: number?, -- value the victim got back (physical intercept or recovery mission)
	recoveryUntil: number?,
	recoveryRaider: string?,
	recovery: boolean?, -- true when this report describes a recovery against the record owner
	clues: { Clue }?,
}

export type Record = {
	version: number,
	stash: number,
	tier: number,
	raid: { server: string, raider: string, raiderName: string, startedAt: number, expiresAt: number, cracked: boolean? }?,
	lastRaidEndedAt: number,
	lastBankAt: number,
	reports: { Report },
	unread: number,
	lifetimeLost: number,
	lifetimeEarned: number,
	ownerName: string?,
	recoveries: { [string]: number }?, -- raidId -> value already recovered FROM this record (one claim chain per raid)
}

local HideoutRecord = {}

local VERSION = 1

function HideoutRecord.default(): Record
	return {
		version = VERSION,
		stash = 0,
		tier = 0,
		raid = nil,
		lastRaidEndedAt = 0,
		lastBankAt = 0,
		reports = {},
		unread = 0,
		lifetimeLost = 0,
		lifetimeEarned = 0,
		ownerName = nil,
		recoveries = {},
	}
end

-- Accept anything the store hands back and produce a valid record (migration + defaults).
function HideoutRecord.migrate(raw: any): Record
	local d = HideoutRecord.default()
	if type(raw) ~= "table" then
		return d
	end
	if type(raw.stash) == "number" and raw.stash >= 0 then
		d.stash = math.floor(raw.stash)
	end
	if type(raw.tier) == "number" then
		d.tier = math.clamp(math.floor(raw.tier), 0, 6)
	end
	if type(raw.raid) == "table" and type(raw.raid.expiresAt) == "number" then
		d.raid = raw.raid
	end
	for _, k in ipairs({ "lastRaidEndedAt", "lastBankAt", "unread", "lifetimeLost", "lifetimeEarned" }) do
		if type(raw[k]) == "number" then
			(d :: any)[k] = raw[k]
		end
	end
	if type(raw.reports) == "table" then
		d.reports = raw.reports
	end
	if type(raw.ownerName) == "string" then
		d.ownerName = raw.ownerName
	end
	if type(raw.recoveries) == "table" then
		d.recoveries = raw.recoveries
	end
	return d
end

local function raidActive(r: Record, now: number): boolean
	return r.raid ~= nil and now < r.raid.expiresAt
end

-- Deposit earned value into the stash (payouts, retained bags). Always allowed.
function HideoutRecord.deposit(r: Record, amount: number): (Record?, number)
	if amount <= 0 or amount ~= math.floor(amount) then
		return nil, 0
	end
	r.stash += amount
	r.lifetimeEarned += amount
	return r, r.stash
end

-- Owner upgrades a tier from the stash. Blocked while a raid is active (the defences are in play).
function HideoutRecord.upgrade(r: Record, cost: number, maxTier: number, now: number): (Record?, string?)
	if raidActive(r, now) then
		return nil, "raid in progress"
	end
	if r.tier >= maxTier then
		return nil, "already at max tier"
	end
	if r.stash < cost then
		return nil, "not enough in the stash"
	end
	r.stash -= cost
	r.tier += 1
	return r, nil
end

-- Owner spends stash on preparation (fake bags). Blocked while a raid is active.
function HideoutRecord.spend(r: Record, amount: number, now: number): (Record?, string?)
	if raidActive(r, now) then
		return nil, "raid in progress"
	end
	if amount <= 0 or amount ~= math.floor(amount) then
		return nil, "bad amount"
	end
	if r.stash < amount then
		return nil, "not enough in the stash"
	end
	r.stash -= amount
	return r, nil
end

-- Owner banks stash into the wallet. Blocked while a raid is active or during the cooldown.
-- Returns the amount removed from the stash (the caller credits the wallet with amount - fee).
function HideoutRecord.bank(r: Record, amount: number, cooldown: number, now: number): (Record?, string?)
	if raidActive(r, now) then
		return nil, "raid in progress"
	end
	if now - r.lastBankAt < cooldown then
		return nil, string.format("bank cooling down (%d s)", math.ceil(cooldown - (now - r.lastBankAt)))
	end
	if amount <= 0 or amount ~= math.floor(amount) or amount > r.stash then
		return nil, "bad amount"
	end
	r.stash -= amount
	r.lastBankAt = now
	return r, nil
end

-- Raider claims the exclusive raid lock. Fails if another raid is active or the cooldown holds.
function HideoutRecord.claimRaid(r: Record, server: string, raider: string, raiderName: string, now: number, maxSeconds: number, cooldown: number): (Record?, string?)
	if raidActive(r, now) then
		return nil, "already being raided"
	end
	if now - r.lastRaidEndedAt < cooldown then
		return nil, string.format("raided recently (%d s)", math.ceil(cooldown - (now - r.lastRaidEndedAt)))
	end
	r.raid = { server = server, raider = raider, raiderName = raiderName, startedAt = now, expiresAt = now + maxSeconds, cracked = false }
	return r, nil
end

local function holdsLock(r: Record, server: string, raider: string, now: number): boolean
	return r.raid ~= nil and r.raid.server == server and r.raid.raider == raider and now < r.raid.expiresAt
end

-- The safe is cracked: take the exposed amount atomically. Only the lock holder may do this.
function HideoutRecord.crack(r: Record, server: string, raider: string, exposed: (number) -> number, now: number): (Record?, number)
	if not holdsLock(r, server, raider, now) then
		return nil, 0
	end
	if r.raid and r.raid.cracked then
		return nil, 0 -- one crack per raid: retained bags cannot be re-stolen in the same raid
	end
	(r.raid :: any).cracked = true
	local amount = exposed(r.stash)
	if amount <= 0 then
		return r, 0
	end
	r.stash -= amount
	r.lifetimeLost += amount
	return r, amount
end

-- Retained value flows back into the stash (bags the defences kept). Allowed during a raid.
function HideoutRecord.retain(r: Record, amount: number): (Record?, number)
	if amount <= 0 then
		return nil, 0
	end
	r.stash += amount
	return r, r.stash
end

-- Open a provisional report when a raid starts so clues have somewhere to land. Not counted as unread.
function HideoutRecord.openReport(r: Record, report: Report, maxReports: number): Record
	if report.raidId and HideoutRecord.reportFor(r, report.raidId) then
		return r
	end
	table.insert(r.reports, 1, report)
	while #r.reports > maxReports do
		table.remove(r.reports)
	end
	return r
end

-- Release the lock and file the report. Only the lock holder (or an expired lock) may release.
-- If a provisional report with the same raidId exists it is finalized in place (clues kept).
function HideoutRecord.releaseRaid(r: Record, server: string, raider: string, report: Report?, maxReports: number, now: number): (Record?, string?)
	if r.raid and not (r.raid.server == server and r.raid.raider == raider) and now < r.raid.expiresAt then
		return nil, "not the lock holder"
	end
	r.raid = nil
	r.lastRaidEndedAt = now
	if report then
		local existing = if report.raidId then HideoutRecord.reportFor(r, report.raidId) else nil
		if existing then
			for k, v in pairs(report :: any) do
				if k ~= "clues" then
					(existing :: any)[k] = v
				end
			end
		else
			table.insert(r.reports, 1, report)
			while #r.reports > maxReports do
				table.remove(r.reports)
			end
		end
		r.unread += 1
	end
	return r, nil
end

function HideoutRecord.setName(r: Record, name: string): Record
	r.ownerName = name
	return r
end

-- Victim side: find the report for a raid.
function HideoutRecord.reportFor(r: Record, raidId: string): Report?
	for _, rep in ipairs(r.reports) do
		if rep.raidId == raidId then
			return rep
		end
	end
	return nil
end

-- What the victim may still recover for a raid: lost minus already recovered, only inside the window.
function HideoutRecord.recoverable(r: Record, raidId: string, now: number): number
	local rep = HideoutRecord.reportFor(r, raidId)
	if not rep or not rep.recoveryUntil or now >= rep.recoveryUntil then
		return 0
	end
	return math.max(0, rep.lost - (rep.recovered or 0))
end

-- Victim side: credit a recovered amount against the report (bounded by what was lost).
function HideoutRecord.noteRecovered(r: Record, raidId: string, amount: number): (Record?, number)
	local rep = HideoutRecord.reportFor(r, raidId)
	if not rep or amount <= 0 then
		return nil, 0
	end
	local room = math.max(0, rep.lost - (rep.recovered or 0))
	local credited = math.min(room, math.floor(amount))
	if credited <= 0 then
		return nil, 0
	end
	rep.recovered = (rep.recovered or 0) + credited
	return r, credited
end

-- Victim side: raiders leave clues on the victim's report while the stolen bundles move.
function HideoutRecord.addClue(r: Record, raidId: string, clue: Clue, maxClues: number): Record?
	local rep = HideoutRecord.reportFor(r, raidId)
	if not rep then
		return nil
	end
	local clues: { Clue } = rep.clues or {}
	table.insert(clues, clue)
	while #clues > maxClues do
		table.remove(clues, 1)
	end
	rep.clues = clues
	return r
end

-- Raider side: a recovery crack. Needs the lock like a normal crack, takes at most `remaining`
-- (what the victim is still owed) and never more than the stash. Idempotent per raid: the total
-- taken for a raidId is recorded so retries or a second mission cannot take it twice.
function HideoutRecord.recover(r: Record, server: string, raider: string, raidId: string, remaining: number, now: number): (Record?, number)
	if not holdsLock(r, server, raider, now) then
		return nil, 0
	end
	if r.raid and r.raid.cracked then
		return nil, 0
	end
	(r.raid :: any).cracked = true
	local recoveries: { [string]: number } = r.recoveries or {}
	-- never debit this record more than it took for this raid, even if earlier recovered bundles were lost
	local already = recoveries[raidId] or 0
	local amount = math.max(0, math.min(math.floor(remaining) - already, r.stash))
	if amount <= 0 then
		r.recoveries = recoveries
		return r, 0
	end
	r.stash -= amount
	r.lifetimeLost += amount
	recoveries[raidId] = already + amount
	r.recoveries = recoveries
	return r, amount
end

function HideoutRecord.markRead(r: Record): Record
	r.unread = 0
	return r
end

function HideoutRecord.isRaidActive(r: Record, now: number): boolean
	return raidActive(r, now)
end

return HideoutRecord
