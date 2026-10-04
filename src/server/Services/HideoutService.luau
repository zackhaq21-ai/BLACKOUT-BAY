--!nonstrict
-- Hideout units: assignment to crews, spawning players at home, delivery table, garage prompts, stash sign.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local HideoutRecord = require(ReplicatedStorage.Shared.Core.HideoutRecord)
local StashRules = require(ReplicatedStorage.Shared.Core.StashRules)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Comms = require(script.Parent.Comms)

local HideoutService = { ctx = nil :: any }

local units = {} -- from world
local unitCrews = {} -- unitId -> { crewId = true }
local unitOwner = {} -- unitId -> userId whose defences are built there
local lastUnread = {} -- Player -> unread count last seen (to announce raids that happened while away)

function HideoutService.init(ctx)
	HideoutService.ctx = ctx
	units = ctx.world.hideouts
	for _, u in ipairs(units) do
		unitCrews[u.id] = {}
		Builder.prompt(u.deliveryTable, "Deliver haul", "Delivery table", 0.6, "Deliver", { UnitId = u.id })
		Builder.prompt(u.board, "Open job board", "Job board", 0, "Board", { UnitId = u.id })
		-- Garage prompts on the two partition pieces
		local parts = {}
		for _, c in ipairs(u.model:GetChildren()) do
			if c.Name == "Partition" then
				table.insert(parts, c)
			end
		end
		if parts[1] then
			Builder.prompt(parts[1], "Roll out Kestrel", "Garage (fast, 2 seats, 2 bags)", 0.8, "SpawnVehicle", { UnitId = u.id, Kind = "Kestrel" })
		end
		if parts[2] then
			Builder.prompt(parts[2], "Roll out Courier Van", "Garage (slow, 4 seats, 5 bags)", 0.8, "SpawnVehicle", { UnitId = u.id, Kind = "Courier" })
		end
	end
end

local function crewCount(unitId: string): number
	local n = 0
	for _ in pairs(unitCrews[unitId]) do
		n += 1
	end
	return n
end

function HideoutService.assignUnit(crew)
	local best, bestN = nil, math.huge
	for _, u in ipairs(units) do
		local n = crewCount(u.id)
		if n < bestN then
			best, bestN = u, n
		end
	end
	if best then
		unitCrews[best.id][crew.id] = true
	end
	return best
end

function HideoutService.releaseUnit(crew)
	if crew.unit then
		unitCrews[crew.unit.id][crew.id] = nil
	end
end

function HideoutService.unitById(id: string)
	for _, u in ipairs(units) do
		if u.id == id then
			return u
		end
	end
	return nil
end

-- The live unit of a crew led by userId on this server (raids target it instead of the lockup).
function HideoutService.unitOfLeader(userId: number)
	for unitId, owner in pairs(unitOwner) do
		if owner == userId then
			return HideoutService.unitById(unitId)
		end
	end
	return nil
end

-- Bind a crew's unit to its leader's hideout record (defences by tier). Called on crew creation and leader change.
function HideoutService.bindCrewUnit(crew)
	local unit = crew.unit
	if not unit then
		return
	end
	local current = unitOwner[unit.id]
	if current and current ~= crew.leader.UserId then
		-- unit shared by several crews: first owner keeps it unless that owner is gone
		local stillHere = Players:GetPlayerByUserId(current)
		if stillHere and HideoutService.ctx.services.Crew.crewOf(stillHere) and HideoutService.ctx.services.Crew.crewOf(stillHere).unit == unit then
			return
		end
	end
	local Raid = HideoutService.ctx.services.Raid
	if Raid.raidOfCrew(crew.id) or Raid.raidOnUnit(unit.id) then
		return
	end
	local owner = crew.leader
	task.spawn(function()
		local record = HideoutService.ctx.services.HideoutStore.load(owner.UserId)
		if not owner.Parent or unitOwner[unit.id] == owner.UserId and Raid.unitState(unit.id) and Raid.unitState(unit.id).tier == record.tier then
			return
		end
		unitOwner[unit.id] = owner.UserId
		HideoutService.ctx.services.HideoutStore.rememberName(owner.UserId, Comms.name(owner))
		Raid.bindUnit(unit, owner.UserId, Comms.name(owner), record.tier)
		HideoutService.refreshSign(unit, owner, record)
	end)
end

function HideoutService.unbindCrewUnit(crew)
	local unit = crew.unit
	if unit and unitOwner[unit.id] == crew.leader.UserId then
		if HideoutService.ctx.services.Raid.raidOnUnit(unit.id) then
			return -- defences stay up until the raid ends; rebindUnit runs then
		end
		unitOwner[unit.id] = nil
		HideoutService.ctx.services.Raid.unbindUnit(unit.id)
	end
end

-- After a raid on a live unit, bind it to whichever crew leads there now (if any).
function HideoutService.rebindUnit(unit)
	local Crew = HideoutService.ctx.services.Crew
	local owner = unitOwner[unit.id]
	local ownerPlayer = owner and Players:GetPlayerByUserId(owner)
	local ownerCrew = ownerPlayer and Crew.crewOf(ownerPlayer)
	if ownerCrew and ownerCrew.unit == unit and ownerCrew.leader == ownerPlayer then
		return -- same owner, defences already reset
	end
	unitOwner[unit.id] = nil
	HideoutService.ctx.services.Raid.unbindUnit(unit.id)
	for crewId in pairs(unitCrews[unit.id] or {}) do
		local crew = Crew.get(crewId)
		if crew then
			HideoutService.bindCrewUnit(crew)
			return
		end
	end
end

function HideoutService.refreshSign(unit, owner: Player, record)
	local gui = unit.stashSign:FindFirstChild("Label")
	local tl = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
	if tl then
		tl.Text = string.format("%s\nSTASH %d\nTIER %d", Comms.name(owner), record.stash, record.tier)
	end
end

-- Send a player their hideout state (stash, tier, reports). Loads from the store.
function HideoutService.pushState(player: Player)
	task.spawn(function()
		local Store = HideoutService.ctx.services.HideoutStore
		local record = Store.load(player.UserId)
		if not player.Parent then
			return
		end
		player:SetAttribute("Stash", record.stash)
		player:SetAttribute("HideoutTier", record.tier)
		local raided = lastUnread[player] ~= nil and record.unread > lastUnread[player]
		if lastUnread[player] == nil and record.ownerName ~= Comms.name(player) then
			local name = Comms.name(player)
			Store.apply(player.UserId, function(r)
				return HideoutRecord.setName(r, name), nil
			end)
		end
		lastUnread[player] = record.unread
		local nextCost = StashRules.upgradeCost(Config.Hideout, record.tier)
		Net.event("HideoutState"):FireClient(player, {
			stash = record.stash,
			tier = record.tier,
			maxTier = StashRules.maxTier(Config.Hideout),
			nextCost = nextCost,
			nextDesc = nextCost and Config.Hideout.Tiers[record.tier + 1].desc or nil,
			unread = record.unread,
			reports = record.reports,
			raidActive = HideoutRecord.isRaidActive(record, os.time()),
			bankFee = Config.Hideout.BankFeeFraction,
			bankingEnabled = Config.Hideout.BankingEnabled,
			exposed = StashRules.exposed(Config.Hideout, record.stash),
			fullExposure = Config.Hideout.FullExposure,
			backend = Store.backend,
			now = os.time(),
		})
		if raided then
			Comms.toast(player, "Your hideout was raided while you were away. Read the report on the job board (Hideout tab).", "alarm")
			Comms.cue(player, "Alarm")
		end
		local crew = HideoutService.ctx.services.Crew.crewOf(player)
		if crew and crew.leader == player and crew.unit and unitOwner[crew.unit.id] == player.UserId then
			HideoutService.refreshSign(crew.unit, player, record)
			local state = HideoutService.ctx.services.Raid.unitState(crew.unit.id)
			if state and state.tier ~= record.tier and not HideoutService.ctx.services.Raid.raidOfCrew(crew.id) then
				HideoutService.ctx.services.Raid.bindUnit(crew.unit, player.UserId, Comms.name(player), record.tier)
			end
		end
	end)
end

-- Deposit earned value into a player's stash (payouts). Returns true when stored.
function HideoutService.depositStash(player: Player, amount: number, reason: string): boolean
	local Store = HideoutService.ctx.services.HideoutStore
	local ok, newStash = Store.apply(player.UserId, function(r)
		return HideoutRecord.deposit(r, amount)
	end)
	if ok then
		HideoutService.ctx.services.EventLog.money(Comms.key(player), amount, "stash: " .. reason, newStash)
		HideoutService.pushState(player)
		return true
	end
	Comms.toast(player, string.format("Could not store %d in your stash (%s). Paid to your wallet instead.", amount, tostring(newStash)), "warn")
	HideoutService.ctx.services.Economy.credit(player, amount, reason .. " (stash unavailable)")
	return false
end

local function listTargets(player: Player)
	local S = HideoutService.ctx.services
	local Store = S.HideoutStore
	local crew = S.Crew.crewOf(player)
	local mates = {}
	if crew then
		for _, m in ipairs(crew.members) do
			mates[m.UserId] = true
		end
	end
	local out = {}
	local listed = {}
	-- Online leaders on this server (raid happens at their pier)
	for unitId, ownerId in pairs(unitOwner) do
		if ownerId ~= player.UserId and not mates[ownerId] then
			local rec = Store.cached(ownerId) or Store.load(ownerId)
			local unit = HideoutService.unitById(unitId)
			listed[ownerId] = true
			table.insert(out, { userId = ownerId, name = Store.nameOf(ownerId), stash = rec.stash, tier = rec.tier, online = true, where = unit and unit.label or "?", exposed = StashRules.exposed(Config.Hideout, rec.stash), raidActive = HideoutRecord.isRaidActive(rec, os.time()) })
		end
	end
	for _, row in ipairs(Store.richest(Config.Hideout.RaidListSize + 4)) do
		if row.userId ~= player.UserId and not mates[row.userId] and not listed[row.userId] and #out < Config.Hideout.RaidListSize + 6 then
			local rec = Store.cached(row.userId) or Store.load(row.userId)
			if rec.ownerName then
				Store.rememberName(row.userId, rec.ownerName)
			end
			listed[row.userId] = true
			table.insert(out, { userId = row.userId, name = Store.nameOf(row.userId), stash = row.stash, tier = rec and rec.tier or nil, online = Players:GetPlayerByUserId(row.userId) ~= nil, where = "Breakwater Lockup", exposed = StashRules.exposed(Config.Hideout, row.stash), raidActive = rec and HideoutRecord.isRaidActive(rec, os.time()) or false })
		end
	end
	table.sort(out, function(a, b)
		return a.stash > b.stash
	end)
	Net.event("RaidTargets"):FireClient(player, { targets = out, backend = Store.backend })
end

function HideoutService.handleRequest(player: Player, req)
	if type(req) ~= "table" then
		return
	end
	local S = HideoutService.ctx.services
	local Store = S.HideoutStore
	local action = req.action
	if action == "refresh" then
		HideoutService.pushState(player)
	elseif action == "markRead" then
		Store.apply(player.UserId, function(r)
			return HideoutRecord.markRead(r), nil
		end)
		lastUnread[player] = 0
		HideoutService.pushState(player)
	elseif action == "upgrade" then
		local cur = Store.load(player.UserId)
		local cost = StashRules.upgradeCost(Config.Hideout, cur.tier)
		if not cost then
			Comms.toast(player, "Your hideout is at the top tier.", "info")
			return
		end
		local ok, err, rec = Store.apply(player.UserId, function(r)
			return HideoutRecord.upgrade(r, StashRules.upgradeCost(Config.Hideout, r.tier) or math.huge, StashRules.maxTier(Config.Hideout), os.time())
		end)
		if ok then
			Comms.toast(player, string.format("Hideout upgraded to tier %d: %s", rec.tier, Config.Hideout.Tiers[rec.tier].desc), "good")
			Comms.cue(player, "Payout")
			S.EventLog.money(Comms.key(player), -cost, "hideout upgrade", rec.stash)
		else
			Comms.toast(player, "Upgrade failed: " .. tostring(err), "warn")
		end
		HideoutService.pushState(player)
	elseif action == "bank" then
		if not Config.Hideout.BankingEnabled then
			Comms.toast(player, "Banking is off: everything you earn stays in the stash.", "warn")
			return
		end
		local amount = tonumber(req.amount)
		if not amount or amount ~= math.floor(amount) or amount <= 0 then
			return
		end
		local ok, err = Store.apply(player.UserId, function(r)
			return HideoutRecord.bank(r, amount, Config.Hideout.BankCooldownSeconds, os.time())
		end)
		if ok then
			local toWallet, fee = StashRules.bank(Config.Hideout, amount)
			S.Economy.credit(player, toWallet, "banked from stash")
			Comms.toast(player, string.format("Banked %d to your wallet (fee %d). The wallet can't be raided.", toWallet, fee), "good")
		else
			Comms.toast(player, "Bank failed: " .. tostring(err), "warn")
		end
		HideoutService.pushState(player)
	elseif action == "listTargets" then
		task.spawn(listTargets, player)
	elseif action == "startRaid" then
		S.Raid.startRaid(player, req.userId)
	elseif action == "recover" then
		S.Raid.startRecovery(player, req.raidId)
	end
end

function HideoutService.unitOf(player: Player)
	local crew = HideoutService.ctx.services.Crew.crewOf(player)
	return crew and crew.unit or nil
end

function HideoutService.sendHome(player: Player)
	local unit = HideoutService.unitOf(player)
	local char = player.Character
	if unit and char and char.PrimaryPart then
		HideoutService.ctx.services.Movement.relocate(player, unit.spawn + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)))
	end
end

function HideoutService.isAtUnit(player: Player, unit): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local p = root.Position
	local b = unit.bounds
	return p.X >= b.minX and p.X <= b.maxX and p.Z >= b.minZ and p.Z <= b.maxZ
end

function HideoutService.start()
	local Police = HideoutService.ctx.services.Police
	local function onCharacter(player: Player, char: Model)
		local root = char:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.NameDisplayDistance = 0
		end
		task.wait() -- let the default spawn settle, then place at home (or in jail)
		if Police and Police.isJailed(player) then
			Police.placeInCell(player)
		else
			HideoutService.sendHome(player)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		HideoutService.pushState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastUnread[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(30)
			for _, p in ipairs(Players:GetPlayers()) do
				HideoutService.pushState(p)
			end
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function(char)
			onCharacter(p, char)
		end)
		if p.Character then
			task.spawn(onCharacter, p, p.Character)
		end
		HideoutService.pushState(p)
	end
end

-- Interactions
function HideoutService.onDeliver(player: Player, prompt: ProximityPrompt)
	local unit = HideoutService.unitById(tostring(prompt:GetAttribute("UnitId")))
	local crew = HideoutService.ctx.services.Crew.crewOf(player)
	if not unit or not crew then
		return
	end
	if crew.unit ~= unit then
		Comms.toast(player, "This isn't your crew's hideout. Yours is " .. (crew.unit and crew.unit.label or "?") .. ".", "warn")
		return
	end
	HideoutService.ctx.services.Mission.deliver(player, crew)
end

function HideoutService.onSpawnVehicle(player: Player, prompt: ProximityPrompt)
	local unit = HideoutService.unitById(tostring(prompt:GetAttribute("UnitId")))
	local crew = HideoutService.ctx.services.Crew.crewOf(player)
	if not unit or not crew or crew.unit ~= unit then
		Comms.toast(player, "Only your own crew's garage works.", "warn")
		return
	end
	HideoutService.ctx.services.Vehicle.spawnCrewVehicle(crew, tostring(prompt:GetAttribute("Kind")), unit.vehicleSpawn, player)
end

local _ = Config
return HideoutService
