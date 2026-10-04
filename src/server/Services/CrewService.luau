--!nonstrict
-- Crews: one to five players, a join code, a payout split and a hideout unit. Every player is always in a
-- crew (solo crews are crews of one) so delivery, payout and logs have one code path.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SplitLedger = require(ReplicatedStorage.Shared.Core.SplitLedger)
local Comms = require(script.Parent.Comms)

local CrewService = { ctx = nil :: any }

local crews = {} -- id -> crew
local playerCrew = {} -- Player -> crewId
local counter = 0
local usedCodes = {}

local LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ"

local function makeCode(): string
	local rng = Random.new()
	while true do
		local s = ""
		for _ = 1, 4 do
			local i = rng:NextInteger(1, #LETTERS)
			s ..= LETTERS:sub(i, i)
		end
		if not usedCodes[s] then
			usedCodes[s] = true
			return s
		end
	end
end

local function memberKeys(crew): { string }
	local out = {}
	for _, p in ipairs(crew.members) do
		table.insert(out, Comms.key(p))
	end
	return out
end

function CrewService.init(ctx)
	CrewService.ctx = ctx
end

function CrewService.snapshot(crew)
	local Loot = CrewService.ctx.services.Loot
	local Mission = CrewService.ctx.services.Mission
	local members = {}
	for _, p in ipairs(crew.members) do
		local carrying = Loot and Loot.carriedLabel(p) or nil
		table.insert(members, {
			userId = p.UserId,
			name = Comms.name(p),
			isLeader = p == crew.leader,
			carrying = carrying,
			cash = p:GetAttribute("Cash") or 0,
			share = crew.shares[Comms.key(p)] or 0,
			jailed = p:GetAttribute("Jailed") == true,
		})
	end
	return {
		id = crew.id,
		code = crew.code,
		leaderId = crew.leader.UserId,
		members = members,
		shares = crew.shares,
		unitLabel = crew.unit and crew.unit.label or "?",
		unitId = crew.unit and crew.unit.id or nil,
		colorIndex = crew.colorIndex,
		jobActive = Mission and Mission.isJobActive(crew.id) or false,
		maxSize = Config.Server.MaxCrewSize,
	}
end

function CrewService.broadcast(crew)
	local snap = CrewService.snapshot(crew)
	for _, p in ipairs(crew.members) do
		Net.event("CrewState"):FireClient(p, snap)
		p:SetAttribute("CrewId", crew.id)
		p:SetAttribute("CrewColor", crew.colorIndex)
	end
end

local function createCrew(leader: Player)
	counter += 1
	local crew = {
		id = "crew" .. counter,
		leader = leader,
		members = { leader },
		code = makeCode(),
		shares = { [Comms.key(leader)] = 100 },
		colorIndex = ((counter - 1) % 6) + 1,
		unit = nil,
	}
	crews[crew.id] = crew
	playerCrew[leader] = crew.id
	local Hideout = CrewService.ctx.services.Hideout
	crew.unit = Hideout.assignUnit(crew)
	crew.colorIndex = crew.unit and crew.unit.index or crew.colorIndex
	CrewService.broadcast(crew)
	CrewService.ctx.services.EventLog.crew(crew.id, Comms.name(leader) .. " formed a crew at " .. (crew.unit and crew.unit.label or "the harbour"))
	return crew
end

local function destroyCrew(crew)
	crews[crew.id] = nil
	usedCodes[crew.code] = nil
	CrewService.ctx.services.Hideout.releaseUnit(crew)
end

function CrewService.ensure(player: Player)
	local id = playerCrew[player]
	if id and crews[id] then
		return crews[id]
	end
	return createCrew(player)
end

function CrewService.crewOf(player: Player)
	local id = playerCrew[player]
	return id and crews[id] or nil
end

function CrewService.get(crewId: string)
	return crews[crewId]
end

function CrewService.playersOf(crewId: string): { Player }
	local crew = crews[crewId]
	return if crew then table.clone(crew.members) else {}
end

function CrewService.sameCrew(a: Player, b: Player): boolean
	return playerCrew[a] ~= nil and playerCrew[a] == playerCrew[b]
end

local function removeMember(crew, player: Player, reason: string, by: Player?)
	local idx = table.find(crew.members, player)
	if not idx then
		return
	end
	local Mission = CrewService.ctx.services.Mission
	local Loot = CrewService.ctx.services.Loot
	local carrying = Loot.carriedLabels(player)
	table.remove(crew.members, idx)
	crew.shares[Comms.key(player)] = nil
	playerCrew[player] = nil
	if Mission then
		Mission.memberLeft(crew.id, player, carrying)
	end
	local line = Comms.name(player) .. " " .. reason
	if #carrying > 0 then
		line ..= " carrying " .. table.concat(carrying, ", ")
	end
	if by then
		line ..= " (by " .. Comms.name(by) .. ")"
	end
	CrewService.ctx.services.EventLog.crew(crew.id, line, "warn")
	if #crew.members == 0 then
		destroyCrew(crew)
		return
	end
	if crew.leader == player then
		crew.leader = crew.members[1]
		CrewService.ctx.services.EventLog.crew(crew.id, Comms.name(crew.leader) .. " now leads the crew")
	end
	-- Next job's split resets to equal; an active job keeps its frozen shares in MissionFlow.
	crew.shares = SplitLedger.equal(memberKeys(crew))
	CrewService.broadcast(crew)
end

function CrewService.leave(player: Player)
	local crew = CrewService.crewOf(player)
	if not crew then
		return
	end
	if #crew.members == 1 then
		Comms.toast(player, "You're already running solo.", "info")
		return
	end
	removeMember(crew, player, "left the crew")
	Comms.toast(player, "You left the crew. You're on your own now.", "warn")
	if player.Parent then
		createCrew(player)
	end
end

function CrewService.join(player: Player, code: string)
	if type(code) ~= "string" or #code ~= 4 then
		Comms.toast(player, "Enter a 4-letter crew code.", "warn")
		return
	end
	code = string.upper(code)
	local target
	for _, c in pairs(crews) do
		if c.code == code then
			target = c
			break
		end
	end
	if not target then
		Comms.toast(player, "No crew with code " .. code .. ".", "warn")
		return
	end
	local current = CrewService.crewOf(player)
	if current == target then
		Comms.toast(player, "You're already in that crew.", "info")
		return
	end
	if #target.members >= Config.Server.MaxCrewSize then
		Comms.toast(player, "That crew is full (max " .. Config.Server.MaxCrewSize .. ").", "warn")
		return
	end
	local Mission = CrewService.ctx.services.Mission
	if Mission and Mission.isJobActive(target.id) then
		Comms.toast(player, "That crew is on a job. Join when it closes.", "warn")
		return
	end
	if current and Mission and Mission.isJobActive(current.id) then
		Comms.toast(player, "Close your current job before joining another crew.", "warn")
		return
	end
	if current then
		if #current.members == 1 then
			playerCrew[player] = nil
			destroyCrew(current)
		else
			removeMember(current, player, "left the crew")
		end
	end
	table.insert(target.members, player)
	playerCrew[player] = target.id
	target.shares = SplitLedger.equal(memberKeys(target))
	CrewService.ctx.services.EventLog.crew(target.id, Comms.name(player) .. " joined the crew")
	CrewService.broadcast(target)
	Comms.toastMany(target.members, Comms.name(player) .. " joined the crew.", "good")
	-- Move them to the crew's hideout so the crew starts together
	CrewService.ctx.services.Hideout.sendHome(player)
end

function CrewService.kick(leader: Player, targetUserId: number)
	local crew = CrewService.crewOf(leader)
	if not crew or crew.leader ~= leader then
		Comms.toast(leader, "Only the crew leader can do that.", "warn")
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == leader or not table.find(crew.members, target) then
		return
	end
	removeMember(crew, target, "was removed from the crew", leader)
	Comms.toast(target, "You were removed from the crew by " .. Comms.name(leader) .. ".", "warn")
	createCrew(target)
end

function CrewService.setShares(leader: Player, shares)
	local crew = CrewService.crewOf(leader)
	if not crew or crew.leader ~= leader then
		Comms.toast(leader, "Only the crew leader sets the split.", "warn")
		return
	end
	local Mission = CrewService.ctx.services.Mission
	if Mission and Mission.isJobActive(crew.id) then
		Comms.toast(leader, "The split is locked while a job is running.", "warn")
		return
	end
	if type(shares) ~= "table" then
		return
	end
	local clean = {}
	for k, v in pairs(shares) do
		if type(k) == "string" and type(v) == "number" then
			clean[k] = math.floor(v)
		end
	end
	local ok, err = SplitLedger.validate(clean, memberKeys(crew), Config.Economy.MinSplitPercent)
	if not ok then
		Comms.toast(leader, "Split rejected: " .. tostring(err), "warn")
		return
	end
	crew.shares = clean
	CrewService.ctx.services.EventLog.crew(crew.id, Comms.name(leader) .. " set the split")
	CrewService.broadcast(crew)
end

function CrewService.handleRequest(player: Player, req)
	if type(req) ~= "table" then
		return
	end
	local action = req.action
	if action == "join" then
		CrewService.join(player, req.code)
	elseif action == "leave" then
		CrewService.leave(player)
	elseif action == "kick" then
		if type(req.userId) == "number" then
			CrewService.kick(player, req.userId)
		end
	elseif action == "setShares" then
		CrewService.setShares(player, req.shares)
	elseif action == "refresh" then
		local crew = CrewService.ensure(player)
		CrewService.broadcast(crew)
		CrewService.ctx.services.EventLog.sendTo(player, crew.id)
	end
end

function CrewService.start()
	Players.PlayerAdded:Connect(function(player)
		CrewService.ensure(player)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		CrewService.ensure(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local crew = CrewService.crewOf(player)
		if crew then
			if #crew.members == 1 then
				playerCrew[player] = nil
				destroyCrew(crew)
			else
				removeMember(crew, player, "left the server")
			end
		end
	end)
	-- Periodic refresh so carried items / cash on the crew card stay current
	task.spawn(function()
		while true do
			task.wait(3)
			for _, crew in pairs(crews) do
				CrewService.broadcast(crew)
			end
		end
	end)
end

return CrewService
