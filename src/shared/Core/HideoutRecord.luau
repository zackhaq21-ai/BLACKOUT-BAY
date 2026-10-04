--!strict
-- The persisted hideout record and the pure transforms applied to it inside UpdateAsync.
-- One record per owner. Every change to the stash or the raid lock goes through these functions on the
-- stored value, never on a cached copy, so two servers, two attackers, or a reconnecting owner can never
-- each spend the same money. Transforms return (newRecord | nil to abort, result).

export type Report = {
	t: number,
	raider: string,
	raiderName: string,
	crewNames: { string },
	entry: string,
	defences: { string },
	lost: number,
	retained: number,
	recoveryUntil: number?,
	recoveryRaider: string?,
}

export type Record = {
	version: number,
	stash: number,
	tier: number,
	raid: { server: string, raider: string, raiderName: string, startedAt: number, expiresAt: number }?,
	lastRaidEndedAt: number,
	lastBankAt: number,
	reports: { Report },
	unread: number,
	lifetimeLost: number,
	lifetimeEarned: number,
	ownerName: string?,
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
	r.raid = { server = server, raider = raider, raiderName = raiderName, startedAt = now, expiresAt = now + maxSeconds }
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

-- Release the lock and file the report. Only the lock holder (or an expired lock) may release.
function HideoutRecord.releaseRaid(r: Record, server: string, raider: string, report: Report?, maxReports: number, now: number): (Record?, string?)
	if r.raid and not (r.raid.server == server and r.raid.raider == raider) and now < r.raid.expiresAt then
		return nil, "not the lock holder"
	end
	r.raid = nil
	r.lastRaidEndedAt = now
	if report then
		table.insert(r.reports, 1, report)
		while #r.reports > maxReports do
			table.remove(r.reports)
		end
		r.unread += 1
	end
	return r, nil
end

function HideoutRecord.setName(r: Record, name: string): Record
	r.ownerName = name
	return r
end

function HideoutRecord.markRead(r: Record): Record
	r.unread = 0
	return r
end

function HideoutRecord.isRaidActive(r: Record, now: number): boolean
	return raidActive(r, now)
end

return HideoutRecord
