--!nonstrict
-- Crew jobs: start at the board, track phases from world events, pay out by the frozen split, and show a
-- results story. One code path handles solo and five-player crews. A delivery with no job open starts a
-- "fence run" so stolen loot always has a legal home.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local MissionFlow = require(ReplicatedStorage.Shared.Core.MissionFlow)
local SplitLedger = require(ReplicatedStorage.Shared.Core.SplitLedger)
local Comms = require(script.Parent.Comms)

local MissionService = { ctx = nil :: any }

local jobs = {} -- crewId -> { flow, shares, lastDeliverer, lastPhase, crew }
local jobCounter = 0

local function now()
	return os.clock()
end

local function playerByKey(key: string): Player?
	return Players:GetPlayerByUserId(tonumber(key) or 0)
end

function MissionService.init(ctx)
	MissionService.ctx = ctx
end

function MissionService.isJobActive(crewId: string): boolean
	local j = jobs[crewId]
	return j ~= nil and j.flow:isActive()
end

local function objectiveFor(job): (string, string)
	local phase = job.flow:phase()
	local unit = job.crew.unit and job.crew.unit.label or "your pier"
	if job.raid then
		local r = job.raid
		if not r.active then
			return "Raid over", ""
		elseif r.entry == nil then
			return (if r.recovery then "Recover your stash from " else "Break into ") .. r.targetName .. "'s hideout", r.unit.label .. ": cut the shield breaker on the outside wall, or the pier door at the back. Lasers inside drop your bag." .. (if r.recovery then string.format(" They owe you %d.", r.recovery.remaining) else "")
		elseif not r.cracked then
			return "Crack the safe", "Stay on the safe. A crewmate beside you halves the time. Laser trips can lock it."
		elseif r.stolen == 0 then
			return "Nothing above the floor", "The safe was nearly empty. Close the job from the board or wait it out."
		elseif phase == "Escaping" or phase == "LootTaken" then
			return "Get the bundles home", "Deliver to " .. unit .. ". Bags left inside the hideout for 8 s go back into their safe."
		end
		return "Grab the bundles", "They're on the floor by the safe. One per trip, or use a trunk."
	end
	if phase == "Started" then
		return "Get to the Aurora Exchange", "North of Aurora Plaza. Front (loud), loading dock (code), or the parking-deck roof."
	elseif phase == "OnSite" then
		return "Take what you came for", string.format("Cut display cases. The vault needs two keycard swipes or a %d s drill.", Config.Museum.DrillSeconds)
	elseif phase == "LootTaken" then
		return "Get the haul out", string.format("Any exit. Heavy loot can't climb. Lockdown drops the front shutter %d s after the alarm.", Config.Museum.LockdownDelaySeconds)
	elseif phase == "Escaping" then
		return "Deliver to " .. unit, "Drop bags on the delivery table at your hideout. Dropped bags can be taken by anyone."
	end
	return "Job closed", ""
end

local function pushHud(job)
	local title, sub = objectiveFor(job)
	local phase = job.flow:phase()
	local M = Blueprint.Museum
	local target = if phase == "Escaping" then (job.crew.unit and job.crew.unit.spawn.Position or nil) elseif job.raid and job.raid.active then job.raid.unit.spawn.Position elseif phase ~= "Closed" then Vector3.new(M.x, 3, M.z + M.d / 2 + 10) else nil
	local snapshot = {
		targetX = target and target.X or nil,
		targetZ = target and target.Z or nil,
		jobActive = job.flow:isActive(),
		phase = job.flow:phase(),
		objective = title,
		objectiveDetail = sub,
		deliveredValue = job.flow.job.deliveredValue,
		startedAt = job.flow.job.startedAt,
		isRaid = job.raid ~= nil,
	}
	for _, p in ipairs(job.crew.members) do
		Net.event("MissionState"):FireClient(p, snapshot)
	end
end

local function memberKeys(crew): { string }
	local out = {}
	for _, p in ipairs(crew.members) do
		table.insert(out, Comms.key(p))
	end
	return out
end

function MissionService.startJob(player: Player, silent: boolean?)
	local Crew = MissionService.ctx.services.Crew
	local crew = Crew.crewOf(player)
	if not crew then
		return
	end
	if MissionService.isJobActive(crew.id) then
		Comms.toast(player, "Your crew is already on a job.", "info")
		return
	end
	if player:GetAttribute("Jailed") then
		Comms.toast(player, "You're in a cell. Get out first.", "warn")
		return
	end
	jobCounter += 1
	local jobId = string.format("job%d_%s", jobCounter, crew.id)
	local flow = MissionFlow.new(jobId, crew.id, memberKeys(crew), now)
	local job = { flow = flow, shares = table.clone(crew.shares), lastDeliverer = nil, lastPhase = "Started", crew = crew, resolvedAt = nil, raid = nil }
	jobs[crew.id] = job
	-- If any member is already inside the museum, the job is on site immediately
	for _, p in ipairs(crew.members) do
		if MissionService.ctx.services.Security.isInside(p) then
			flow:memberEnteredSite(Comms.key(p))
		end
	end
	if not silent then
		MissionService.ctx.services.EventLog.crew(crew.id, Comms.name(player) .. " started the Aurora Exchange job (split locked)")
		Comms.toastMany(crew.members, "Job started: the Aurora Exchange. Split is locked. Good luck.", "good")
	end
	Crew.broadcast(crew)
	pushHud(job)
	return job
end

local function closeJob(crewId: string, reason: string)
	local job = jobs[crewId]
	if not job or not job.flow:isActive() then
		return
	end
	local flow = job.flow
	flow:close(reason)
	MissionService.ctx.services.Loot.clearFakes(crewId)
	if job.raid then
		MissionService.ctx.services.Raid.onJobClosed(crewId, reason)
	end
	local present = flow:presentMembers()
	local deliverer = job.lastDeliverer and Comms.key(job.lastDeliverer) or nil
	local payouts = SplitLedger.distribute(flow.job.deliveredValue, job.shares, present, deliverer)
	local Economy = MissionService.ctx.services.Economy
	local EventLog = MissionService.ctx.services.EventLog
	local payoutRows = {}
	for key, amount in pairs(payouts) do
		local p = playerByKey(key)
		if p and amount > 0 then
			if Config.Hideout.PayoutsToStash then
				MissionService.ctx.services.Hideout.depositStash(p, amount, "job payout " .. flow.job.id)
			else
				Economy.credit(p, amount, "job payout " .. flow.job.id)
			end
			Economy.bumpStat(p, "delivered", amount)
		end
		table.insert(payoutRows, { userId = tonumber(key), name = p and Comms.name(p) or key, amount = amount, share = job.shares[key] or 0 })
	end
	table.sort(payoutRows, function(a, b)
		return a.amount > b.amount
	end)
	local summary = flow:summary()
	-- XP (one credit per job id, durable via ProfileOps): quiet, paid jobs earn the most
	local Data = MissionService.ctx.services.Data
	local C = Config.Commerce
	local xp = C.XpEmpty
	if flow.job.deliveredValue > 0 then
		xp = C.XpDelivered + math.min(C.XpDeliveredCap, math.floor(flow.job.deliveredValue / 100) * C.XpPerHundredDelivered)
		if summary.headline == "GHOST CREW" then
			xp += C.XpGhostBonus
		end
	end
	for _, key in ipairs(present) do
		local p = playerByKey(key)
		if p then
			Data.applyOp(p, { kind = "Run", id = flow.job.id, xp = xp, won = flow.job.deliveredValue > 0 })
			MissionService.ctx.services.Cosmetics.push(p)
		end
	end
	EventLog.crew(crewId, string.format("Job closed (%s): %d delivered", reason, flow.job.deliveredValue), if flow.job.deliveredValue > 0 then "good" else "warn")
	-- Results: what happened, what you kept, what you lost, what next
	local lines = {}
	for _, e in ipairs(summary.log) do
		table.insert(lines, { t = e.t - flow.job.startedAt, text = e.text, kind = e.kind })
	end
	local results = {
		headline = summary.headline,
		reason = summary.reason,
		deliveredValue = summary.deliveredValue,
		escalation = summary.escalation,
		maxSecurityLevel = summary.maxSecurityLevel,
		payouts = payoutRows,
		lines = lines,
		durationSeconds = (flow.job.closedAt or now()) - flow.job.startedAt,
		xp = xp,
		next = if job.raid then "Payouts went to your hideout stash. Bank some from the board's Hideout tab if you want it safe." else "Walk to the job board to run it again. Payouts sit in your stash: bank or spend on defences from the Hideout tab.",
	}
	for _, p in ipairs(job.crew.members) do
		Net.event("Results"):FireClient(p, results)
		Comms.cue(p, if summary.deliveredValue > 0 then "Payout" else "Drop")
	end
	pushHud(job)
	MissionService.ctx.services.Crew.broadcast(job.crew)
end

function MissionService.closeJobOfCrew(crewId: string, reason: string)
	closeJob(crewId, reason)
end

-- Start a raid job for the raider's crew (same phases and payout path as a heist).
function MissionService.startRaidJob(player: Player, raid)
	local job = MissionService.startJob(player, true)
	if job then
		job.raid = raid
		job.flow:log("start", nil, "Raid on " .. raid.targetName .. "'s hideout at " .. raid.unit.label)
		pushHud(job)
	end
	return job
end

-- Minted bundles belong to the crew's job from the moment they exist (touched + phase LootTaken).
function MissionService.minted(crewId: string, itemIds: { string }, label: string)
	local job = jobs[crewId]
	if job and job.flow:isActive() then
		job.flow:lootMinted(itemIds, label)
		pushHud(job)
	end
end

function MissionService.closeJobByPlayer(player: Player)
	local crew = MissionService.ctx.services.Crew.crewOf(player)
	if not crew or not MissionService.isJobActive(crew.id) then
		return
	end
	closeJob(crew.id, "Called off by " .. Comms.name(player))
end

function MissionService.deliver(player: Player, crew)
	local Loot = MissionService.ctx.services.Loot
	if #Loot.carriedBy(player) == 0 then
		Comms.toast(player, "You're not carrying anything.", "info")
		return
	end
	local job = jobs[crew.id]
	if not job or not job.flow:isActive() then
		job = MissionService.startJob(player, true)
		if not job then
			return
		end
		MissionService.ctx.services.EventLog.crew(crew.id, Comms.name(player) .. " fenced loot with no job open (fence run)")
	end
	local total = Loot.deliver(player, job.flow.job.id)
	if total > 0 then
		job.lastDeliverer = player
		Comms.toastMany(crew.members, string.format("%s delivered %d to %s.", Comms.name(player), total, crew.unit and crew.unit.label or "the hideout"), "good")
	end
end

-- Events from other services ------------------------------------------------------------------
local function jobOf(crewId: string?)
	local j = crewId and jobs[crewId]
	return if j and j.flow:isActive() then j else nil
end

local function onLootEvent(kind: string, data)
	local Loot = MissionService.ctx.services.Loot
	local EventLog = MissionService.ctx.services.EventLog
	if data.item and data.item.kind == "Fake" then
		return -- decoys never count as the job's loot
	end
	if kind == "pickup" then
		local job = jobOf(data.crewId)
		if job then
			job.flow:lootPicked(Comms.name(data.player), data.item.id, data.item.label)
			if data.fromState == "InCase" then
				EventLog.crew(data.crewId, Comms.name(data.player) .. " took the " .. data.item.label)
			end
		end
		local where = Blueprint.nearestLandmark(data.player.Character and data.player.Character:GetPivot().Position.X or 0, data.player.Character and data.player.Character:GetPivot().Position.Z or 0)
		local _ = where
	elseif kind == "stolen" then
		local victim = jobOf(data.fromCrewId)
		local pos = data.player.Character and data.player.Character:GetPivot().Position or Vector3.zero
		local where = Blueprint.nearestLandmark(pos.X, pos.Z)
		local line = string.format("%s took your %s near %s", Comms.name(data.player), data.item.label, where)
		EventLog.crew(data.fromCrewId, line, "alarm")
		if victim then
			victim.flow:lootStolen(Comms.name(data.player), data.item.id, data.item.label)
		end
		local Crew = MissionService.ctx.services.Crew
		Comms.toastMany(Crew.playersOf(data.fromCrewId), line, "alarm")
	elseif kind == "drop" then
		local job = jobOf(data.crewId)
		if job and data.player then
			local pos = data.position or Vector3.zero
			job.flow:lootDropped(Comms.name(data.player), data.item.id, data.item.label, (data.note or "dropped") .. " near " .. Blueprint.nearestLandmark(pos.X, pos.Z))
		end
	elseif kind == "deliver" then
		local job = jobOf(data.crewId)
		if job then
			job.flow:lootDelivered(Comms.name(data.player), data.item.id, data.item.label, data.value)
			pushHud(job)
		end
	elseif kind == "casecut" then
		local job = jobOf(data.crewId)
		if job then
			job.flow:log("cut", Comms.name(data.player), Comms.name(data.player) .. " cut a display case")
		end
	end
	local _ = Loot
end

function MissionService.note(player: Player, text: string)
	local crew = MissionService.ctx.services.Crew.crewOf(player)
	if not crew then
		return
	end
	MissionService.ctx.services.EventLog.crew(crew.id, Comms.name(player) .. " " .. text)
	local job = jobOf(crew.id)
	if job then
		job.flow:log("note", Comms.name(player), Comms.name(player) .. " " .. text)
	end
end

function MissionService.memberLeft(crewId: string, player: Player, carrying: { string })
	local job = jobOf(crewId)
	if job then
		job.flow:memberLeft(Comms.key(player), carrying)
		-- Payout keys are user ids; the log line uses the display name
		job.flow:log("left", Comms.name(player), Comms.name(player) .. " left the crew" .. (if #carrying > 0 then " carrying " .. table.concat(carrying, ", ") else ""))
		pushHud(job)
	end
end

function MissionService.memberArrested(player: Player, dropped: { string }, where: string)
	local crew = MissionService.ctx.services.Crew.crewOf(player)
	local job = crew and jobOf(crew.id)
	if job then
		job.flow:memberArrested(Comms.key(player), dropped, where)
		job.flow:log("arrest", Comms.name(player), Comms.name(player) .. " was arrested at " .. where .. (if #dropped > 0 then ", dropping " .. table.concat(dropped, ", ") else ""))
		MissionService.ctx.services.EventLog.crew(crew.id, Comms.name(player) .. " was arrested at " .. where, "alarm")
	end
end

function MissionService.memberReleased(player: Player)
	local crew = MissionService.ctx.services.Crew.crewOf(player)
	local job = crew and jobOf(crew.id)
	if job then
		job.flow:memberReleased(Comms.key(player))
	end
end

local function tick()
	local Loot = MissionService.ctx.services.Loot
	local Security = MissionService.ctx.services.Security
	for crewId, job in pairs(jobs) do
		if job.flow:isActive() then
			for _, p in ipairs(job.crew.members) do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local inside = Security.isInsideBounds(root.Position)
					if job.raid and job.raid.active then
						local b = job.raid.unit.bounds
						inside = root.Position.X >= b.minX and root.Position.X <= b.maxX and root.Position.Z >= b.minZ and root.Position.Z <= b.maxZ
					end
					if inside then
						job.flow:memberEnteredSite(Comms.key(p))
					elseif job.flow:phase() == "LootTaken" then
						local items = Loot.carriedBy(p)
						if #items > 0 then
							job.flow:lootLeftSite(Comms.name(p), items[1].label)
						end
					end
				end
			end
			-- Unresolved = touched items that are neither delivered nor destroyed
			local unresolved = 0
			for itemId in pairs(job.flow.job.touched) do
				local item = Loot.get(itemId)
				if item and item.state ~= "Delivered" and item.state ~= "Destroyed" then
					unresolved += 1
				end
			end
			local close, reason = job.flow:shouldAutoClose(unresolved, Config.Mission.StartWindowSeconds)
			if close and (reason == "Haul delivered" or reason == "Haul lost") then
				-- Grace period: the crew may go back for more before the job books
				if not job.resolvedAt then
					job.resolvedAt = now()
					Comms.toastMany(job.crew.members, string.format("%s. The job closes in %d s unless you touch more loot.", reason, Config.Mission.CloseGraceSeconds), "info")
				elseif now() - job.resolvedAt >= Config.Mission.CloseGraceSeconds then
					closeJob(crewId, reason)
				end
			elseif close then
				closeJob(crewId, reason)
			else
				job.resolvedAt = nil
			end
			if job.flow:isActive() and job.flow:phase() ~= job.lastPhase then
				job.lastPhase = job.flow:phase()
				pushHud(job)
			end
		end
	end
end

function MissionService.handleRequest(player: Player, req)
	if type(req) ~= "table" then
		return
	end
	if req.action == "start" then
		local crew = MissionService.ctx.services.Crew.crewOf(player)
		local unit = crew and crew.unit
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if unit and root and (root.Position - unit.board.Position).Magnitude <= 16 then
			MissionService.startJob(player)
		else
			Comms.toast(player, "Start jobs from your crew's job board at " .. (unit and unit.label or "your pier") .. ".", "warn")
		end
	elseif req.action == "close" then
		MissionService.closeJobByPlayer(player)
	elseif req.action == "refresh" then
		local crew = MissionService.ctx.services.Crew.crewOf(player)
		local job = crew and jobs[crew.id]
		if job then
			pushHud(job)
		else
			Net.event("MissionState"):FireClient(player, { jobActive = false, phase = "Idle", objective = "Open the job board at your pier", objectiveDetail = "Run solo now, or share your crew code and run it together." })
		end
	end
end

function MissionService.start()
	MissionService.ctx.services.Loot.onEvent(onLootEvent)
	MissionService.ctx.services.Security.onLevelChange(function(level, reason)
		for _, job in pairs(jobs) do
			if job.flow:isActive() and job.flow:phase() ~= "Started" then
				job.flow:securityChanged(level, reason)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
end

return MissionService
