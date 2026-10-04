--!strict
-- Crew job state machine. Phases are coarse and readable; alarms and police heat are overlays owned
-- by other systems. Every transition and notable event is logged so the results screen can tell the
-- story of the run and betrayal is explainable from evidence.

export type Phase = "Idle" | "Started" | "OnSite" | "LootTaken" | "Escaping" | "Closed"

export type LogEntry = { t: number, kind: string, actor: string?, text: string, data: any? }

export type Job = {
	id: string,
	crewId: string,
	phase: Phase,
	startedAt: number,
	closedAt: number?,
	closeReason: string?,
	members: { [string]: boolean }, -- members at start; stays for payout eligibility
	left: { [string]: number }, -- member -> time they left mid-job
	arrested: { [string]: boolean },
	touched: { [string]: boolean }, -- item ids this crew has handled
	delivered: { [string]: number }, -- item id -> value credited
	deliveredValue: number,
	log: { LogEntry },
	escalation: string?, -- what raised the alarm, if anything
	maxSecurityLevel: number,
}

local MissionFlow = {}
MissionFlow.__index = MissionFlow

export type MissionFlow = typeof(setmetatable({} :: { job: Job, now: () -> number, maxLog: number }, MissionFlow))

local ORDER: { [string]: number } = { Idle = 0, Started = 1, OnSite = 2, LootTaken = 3, Escaping = 4, Closed = 5 }

function MissionFlow.new(jobId: string, crewId: string, memberIds: { string }, now: (() -> number)?): MissionFlow
	local nowFn = now or function()
		return 0
	end
	local members = {}
	for _, id in ipairs(memberIds) do
		members[id] = true
	end
	local job: Job = {
			id = jobId,
			crewId = crewId,
			phase = "Started" :: Phase,
			startedAt = nowFn(),
			members = members,
			left = {},
			arrested = {},
			touched = {},
			delivered = {},
			deliveredValue = 0,
			log = {},
			maxSecurityLevel = 0,
			closedAt = nil,
			closeReason = nil,
			escalation = nil,
		}
	local self = setmetatable({ now = nowFn, maxLog = 60, job = job }, MissionFlow)
	self:log("start", nil, "Job started")
	return self
end

function MissionFlow.log(self: MissionFlow, kind: string, actor: string?, text: string, data: any?)
	table.insert(self.job.log, { t = self.now(), kind = kind, actor = actor, text = text, data = data })
	if #self.job.log > self.maxLog then
		table.remove(self.job.log, 1)
	end
end

function MissionFlow.phase(self: MissionFlow): Phase
	return self.job.phase
end

function MissionFlow.isActive(self: MissionFlow): boolean
	return self.job.phase ~= "Closed"
end

local function advance(self: MissionFlow, to: Phase, text: string)
	if ORDER[to] > ORDER[self.job.phase] and self.job.phase ~= "Closed" then
		self.job.phase = to
		self:log("phase", nil, text, { phase = to })
	end
end

function MissionFlow.memberEnteredSite(self: MissionFlow, _memberId: string)
	if not self:isActive() then
		return
	end
	advance(self, "OnSite", "Crew is on site")
end

function MissionFlow.lootPicked(self: MissionFlow, memberId: string, itemId: string, label: string)
	if not self:isActive() then
		return
	end
	self.job.touched[itemId] = true
	self:log("pickup", memberId, memberId .. " took " .. label, { itemId = itemId })
	advance(self, "LootTaken", "Loot in hand")
end

-- Items created by the job itself (stash bundles from a cracked safe) count as taken.
function MissionFlow.lootMinted(self: MissionFlow, itemIds: { string }, label: string)
	if not self:isActive() then
		return
	end
	for _, id in ipairs(itemIds) do
		self.job.touched[id] = true
	end
	self:log("mint", nil, string.format("%d x %s on the floor by the safe", #itemIds, label), { count = #itemIds })
	advance(self, "LootTaken", "Loot on the floor")
end

function MissionFlow.lootLeftSite(self: MissionFlow, memberId: string, label: string)
	if not self:isActive() then
		return
	end
	self:log("exit", memberId, memberId .. " left the building with " .. label)
	advance(self, "Escaping", "Getaway")
end

function MissionFlow.lootDropped(self: MissionFlow, memberId: string, itemId: string, label: string, note: string?)
	if not self:isActive() then
		return
	end
	self:log("drop", memberId, memberId .. " dropped " .. label .. (if note then " (" .. note .. ")" else ""), { itemId = itemId })
end

function MissionFlow.lootStolen(self: MissionFlow, thiefId: string, itemId: string, label: string)
	if not self:isActive() then
		return
	end
	self:log("stolen", thiefId, label .. " was taken by " .. thiefId, { itemId = itemId })
end

function MissionFlow.lootDelivered(self: MissionFlow, memberId: string, itemId: string, label: string, value: number)
	if not self:isActive() then
		return
	end
	if self.job.delivered[itemId] then
		return -- already credited; never double count
	end
	self.job.delivered[itemId] = value
	self.job.deliveredValue += value
	self:log("deliver", memberId, memberId .. " delivered " .. label, { itemId = itemId, value = value })
end

function MissionFlow.securityChanged(self: MissionFlow, level: number, reason: string?)
	if not self:isActive() then
		return
	end
	if level > self.job.maxSecurityLevel then
		self.job.maxSecurityLevel = level
		if level >= 2 and not self.job.escalation then
			self.job.escalation = reason or "alarm"
		end
		self:log("security", nil, reason or ("Security level " .. level), { level = level })
	end
end

function MissionFlow.memberLeft(self: MissionFlow, memberId: string, carryingLabels: { string })
	if not self:isActive() then
		return
	end
	self.job.left[memberId] = self.now()
	local text = memberId .. " left the crew"
	if #carryingLabels > 0 then
		text ..= " carrying " .. table.concat(carryingLabels, ", ")
	end
	self:log("left", memberId, text, { carrying = carryingLabels })
end

function MissionFlow.memberArrested(self: MissionFlow, memberId: string, droppedLabels: { string }, where: string?)
	if not self:isActive() then
		return
	end
	self.job.arrested[memberId] = true
	local text = memberId .. " was arrested"
	if where then
		text ..= " at " .. where
	end
	if #droppedLabels > 0 then
		text ..= ", dropping " .. table.concat(droppedLabels, ", ")
	end
	self:log("arrest", memberId, text, { dropped = droppedLabels })
end

function MissionFlow.memberReleased(self: MissionFlow, memberId: string)
	if not self:isActive() then
		return
	end
	self.job.arrested[memberId] = nil
	self:log("release", memberId, memberId .. " is back on the street")
end

-- Members who are still eligible for payout: started with the job, did not leave.
function MissionFlow.presentMembers(self: MissionFlow): { string }
	local out = {}
	for id in pairs(self.job.members) do
		if not self.job.left[id] then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

function MissionFlow.allPresentArrested(self: MissionFlow): boolean
	local present = self:presentMembers()
	if #present == 0 then
		return false
	end
	for _, id in ipairs(present) do
		if not self.job.arrested[id] then
			return false
		end
	end
	return true
end

-- Returns true if the job should auto-close: all touched items are resolved (delivered or lost)
-- as reported by the caller, or the crew is entirely arrested or gone, or the job timed out.
function MissionFlow.shouldAutoClose(self: MissionFlow, unresolvedTouched: number, maxSeconds: number): (boolean, string?)
	if not self:isActive() then
		return false, nil
	end
	if #self:presentMembers() == 0 then
		return true, "Crew disbanded"
	end
	if self:allPresentArrested() then
		return true, "Crew arrested"
	end
	if self.now() - self.job.startedAt >= maxSeconds then
		return true, "Job window expired"
	end
	if ORDER[self.job.phase] >= ORDER.LootTaken and unresolvedTouched == 0 then
		return true, if self.job.deliveredValue > 0 then "Haul delivered" else "Haul lost"
	end
	return false, nil
end

function MissionFlow.close(self: MissionFlow, reason: string): boolean
	if not self:isActive() then
		return false
	end
	self.job.phase = "Closed"
	self.job.closedAt = self.now()
	self.job.closeReason = reason
	self:log("close", nil, "Job closed: " .. reason)
	return true
end

-- Human-readable outcome used by the results screen.
function MissionFlow.summary(self: MissionFlow): { headline: string, reason: string, deliveredValue: number, escalation: string?, maxSecurityLevel: number, log: { LogEntry } }
	local j = self.job
	local headline
	if j.deliveredValue > 0 then
		headline = if j.maxSecurityLevel >= 2 then "Loud, but paid" else "Clean job"
	elseif j.closeReason == "Crew arrested" then
		headline = "Busted"
	elseif ORDER[j.phase] >= ORDER.LootTaken or j.closeReason == "Haul lost" then
		headline = "Walked away empty"
	else
		headline = "Called off"
	end
	return {
		headline = headline,
		reason = j.closeReason or "",
		deliveredValue = j.deliveredValue,
		escalation = j.escalation,
		maxSecurityLevel = j.maxSecurityLevel,
		log = j.log,
	}
end

return MissionFlow
