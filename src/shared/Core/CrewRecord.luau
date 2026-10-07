--!strict
-- Durable crew identity (pure). One record per owner; every mutation is a transform applied to the stored value.
-- Bounded: members, history and milestones never grow past config. Names are validated here and FILTERED by
-- the server with Roblox TextService before anyone sees them.

export type Entry = { t: number, kind: string, text: string, value: number }
export type Record = {
	version: number,
	id: string,
	name: string,
	filtered: boolean,
	createdAt: number,
	renamedAt: number,
	ownerUserId: number,
	ownerName: string,
	members: { [string]: string },
	totals: { [string]: number },
	bests: { [string]: number },
	history: { Entry },
	milestones: { [string]: number },
}
export type Cfg = { NameMin: number, NameMax: number, RenameCooldownSeconds: number, MaxMembers: number, MaxHistory: number, MaxMilestones: number, LedgerLines: number }

local CrewRecord = {}

local TOTALS = { "jobs", "delivered", "raids", "raidTaken", "recovered", "convoys", "bounties", "blackoutResets", "arrests", "accomplishments" }
local BESTS = { "biggestJob", "biggestRaid", "highestBounty", "biggestCrate" }

local function num(v: any): number?
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return nil
end

function CrewRecord.default(ownerUserId: number, ownerName: string, now: number): Record
	local totals, bests = {}, {}
	for _, k in ipairs(TOTALS) do
		totals[k] = 0
	end
	for _, k in ipairs(BESTS) do
		bests[k] = 0
	end
	return {
		version = 1,
		id = "crew_" .. tostring(ownerUserId),
		name = ownerName .. "'s crew",
		filtered = true, -- the default name contains only the owner's display name
		createdAt = now,
		renamedAt = 0,
		ownerUserId = ownerUserId,
		ownerName = ownerName,
		members = { [tostring(ownerUserId)] = ownerName },
		totals = totals,
		bests = bests,
		history = {},
		milestones = {},
	}
end

-- Validate stored data field by field; anything malformed falls back to the default for that field.
function CrewRecord.migrate(raw: any, ownerUserId: number, ownerName: string, now: number, cfg: Cfg): Record
	local d = CrewRecord.default(ownerUserId, ownerName, now)
	if type(raw) ~= "table" then
		return d
	end
	if type(raw.name) == "string" and #raw.name >= cfg.NameMin and #raw.name <= cfg.NameMax and raw.filtered == true then
		d.name = raw.name
	end
	d.createdAt = num(raw.createdAt) or now
	d.renamedAt = num(raw.renamedAt) or 0
	if type(raw.members) == "table" then
		local n = 0
		for k, v in pairs(raw.members) do
			if n >= cfg.MaxMembers then
				break
			end
			if type(k) == "string" and tonumber(k) and type(v) == "string" and #v <= 32 then
				d.members[k] = v
				n += 1
			end
		end
	end
	d.members[tostring(ownerUserId)] = ownerName
	for _, k in ipairs(TOTALS) do
		local v = type(raw.totals) == "table" and num(raw.totals[k]) or nil
		if v and v >= 0 and v < 1e12 then
			d.totals[k] = math.floor(v)
		end
	end
	for _, k in ipairs(BESTS) do
		local v = type(raw.bests) == "table" and num(raw.bests[k]) or nil
		if v and v >= 0 and v < 1e12 then
			d.bests[k] = math.floor(v)
		end
	end
	if type(raw.history) == "table" then
		for _, e in ipairs(raw.history) do
			if #d.history >= cfg.MaxHistory then
				break
			end
			if type(e) == "table" and num(e.t) and type(e.kind) == "string" and #e.kind <= 24 and type(e.text) == "string" and #e.text <= 120 then
				table.insert(d.history, { t = e.t, kind = e.kind, text = e.text, value = num(e.value) or 0 })
			end
		end
	end
	if type(raw.milestones) == "table" then
		local n = 0
		for k, v in pairs(raw.milestones) do
			if n >= cfg.MaxMilestones then
				break
			end
			if type(k) == "string" and #k <= 40 and num(v) then
				d.milestones[k] = v
				n += 1
			end
		end
	end
	return d
end

-- Normalise and validate a proposed name. Returns (normalised, nil) or (nil, reason). Filtering is separate.
function CrewRecord.validateName(cfg: Cfg, name: any): (string?, string?)
	if type(name) ~= "string" then
		return nil, "name must be text"
	end
	local s = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #s < cfg.NameMin then
		return nil, string.format("at least %d characters", cfg.NameMin)
	end
	if #s > cfg.NameMax then
		return nil, string.format("at most %d characters", cfg.NameMax)
	end
	if s:find("[%c]") then
		return nil, "no control characters"
	end
	if not s:find("%w") then
		return nil, "needs at least one letter or digit"
	end
	return s, nil
end

-- Apply an already-FILTERED, validated name. Enforces the rename cooldown.
function CrewRecord.rename(r: Record, filteredName: string, now: number, cfg: Cfg): (Record?, string?)
	if now - r.renamedAt < cfg.RenameCooldownSeconds and r.renamedAt > 0 then
		return nil, string.format("rename again in %d s", math.ceil(cfg.RenameCooldownSeconds - (now - r.renamedAt)))
	end
	if filteredName == r.name then
		return nil, "that is already the name"
	end
	r.name = filteredName
	r.filtered = true
	r.renamedAt = now
	return r, nil
end

function CrewRecord.touchMember(r: Record, userId: number, name: string, cfg: Cfg): Record
	local key = tostring(userId)
	if r.members[key] then
		r.members[key] = name
		return r
	end
	local n = 0
	for _ in pairs(r.members) do
		n += 1
	end
	if n >= cfg.MaxMembers then
		return r
	end
	r.members[key] = name
	return r
end

-- Record something the crew did: totals and bests update by kind; history keeps the newest MaxHistory.
local KIND_TOTAL = { job = "jobs", raid = "raids", raidTaken = "raidTaken", recovery = "recovered", convoy = "convoys", bounty = "bounties", blackoutReset = "blackoutResets", arrest = "arrests", accomplishment = "accomplishments" }
local KIND_BEST = { job = "biggestJob", raid = "biggestRaid", bounty = "highestBounty", convoy = "biggestCrate" }

function CrewRecord.note(r: Record, kind: string, value: number, text: string, now: number, cfg: Cfg): Record
	local v = math.max(0, math.floor(num(value) or 0))
	local total = KIND_TOTAL[kind]
	if total then
		r.totals[total] = (r.totals[total] or 0) + (if kind == "job" or kind == "convoy" or kind == "raid" or kind == "bounty" or kind == "recovery" then 1 else 1)
		if kind == "job" then
			r.totals.delivered = (r.totals.delivered or 0) + v
		end
	end
	local best = KIND_BEST[kind]
	if best and v > (r.bests[best] or 0) then
		r.bests[best] = v
	end
	if type(text) == "string" and #text > 0 then
		table.insert(r.history, { t = now, kind = kind, text = text:sub(1, 120), value = v })
		while #r.history > cfg.MaxHistory do
			table.remove(r.history, 1)
		end
	end
	return r
end

-- Milestone (accomplishment) once per id.
function CrewRecord.milestone(r: Record, id: string, now: number, cfg: Cfg): (Record, boolean)
	if r.milestones[id] then
		return r, false
	end
	local n = 0
	for _ in pairs(r.milestones) do
		n += 1
	end
	if n >= cfg.MaxMilestones then
		return r, false
	end
	r.milestones[id] = now
	return r, true
end

-- Client-safe summary (no member ids beyond names)
function CrewRecord.summary(r: Record, now: number)
	local names = {}
	for _, n in pairs(r.members) do
		table.insert(names, n)
	end
	table.sort(names)
	local recent = {}
	for i = #r.history, math.max(1, #r.history - 4), -1 do
		table.insert(recent, r.history[i].text)
	end
	local milestones = 0
	for _ in pairs(r.milestones) do
		milestones += 1
	end
	return {
		name = r.name,
		days = math.max(0, math.floor((now - r.createdAt) / 86400)),
		ownerName = r.ownerName,
		members = names,
		totals = table.clone(r.totals),
		bests = table.clone(r.bests),
		recent = recent,
		milestones = milestones,
	}
end

-- Lines for the physical ledger wall (bounded by cfg.LedgerLines).
function CrewRecord.ledgerLines(r: Record, now: number, cfg: Cfg): { string }
	local lines = { r.name:upper(), string.format("since day %d · %d jobs · %d fenced", math.max(1, math.floor((now - r.createdAt) / 86400) + 1), r.totals.jobs or 0, r.totals.delivered or 0) }
	if (r.bests.biggestRaid or 0) > 0 then
		table.insert(lines, string.format("biggest raid %d", r.bests.biggestRaid))
	end
	if (r.bests.highestBounty or 0) > 0 then
		table.insert(lines, string.format("highest bounty %d", r.bests.highestBounty))
	end
	if (r.totals.convoys or 0) > 0 then
		table.insert(lines, string.format("%d convoy crates fenced", r.totals.convoys))
	end
	if (r.totals.blackoutResets or 0) > 0 then
		table.insert(lines, string.format("%d grids reset", r.totals.blackoutResets))
	end
	if (r.totals.arrests or 0) > 0 then
		table.insert(lines, string.format("%d arrests", r.totals.arrests))
	end
	for i = #r.history, 1, -1 do
		if #lines >= cfg.LedgerLines then
			break
		end
		table.insert(lines, "· " .. r.history[i].text)
	end
	while #lines > cfg.LedgerLines do
		table.remove(lines)
	end
	return lines
end

return CrewRecord
