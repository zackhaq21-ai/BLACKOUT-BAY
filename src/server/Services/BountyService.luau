--!nonstrict
-- Bounties: placed from a contributor's stash onto a target's hideout record (persists across servers and
-- offline), stacked, shown on nameplates, and claimed once by a hunter who takes the target down on foot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local HideoutRecord = require(ReplicatedStorage.Shared.Core.HideoutRecord)
local BountyRecord = require(ReplicatedStorage.Shared.Core.BountyRecord)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Comms = require(script.Parent.Comms)

local BountyService = { ctx = nil :: any }
local BC = Config.Bounty
local takedowns = {} -- hunter -> { target, progress } (server-timed hold)
local claiming = {} -- hunter -> true while a claim transform is in flight
local stunnedUntil = {} -- Player -> os.clock()

local function unix()
	return os.time()
end

-- Keep the takedown prompt on a wanted player's character in sync with their bounty.
function BountyService.syncPrompt(target: Player, total: number)
	target:SetAttribute("Bounty", total)
	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local existing = root:FindFirstChild("TakedownPrompt")
	if total > 0 then
		if not existing then
			local pp = Builder.prompt(root, "Take down", "", BC.TakedownSeconds, "Takedown", { TargetUserId = target.UserId })
			pp.Name = "TakedownPrompt"
			pp.MaxActivationDistance = BC.TakedownRange
			existing = pp
		end
		existing.ObjectText = string.format("Bounty %d · within %d studs, on foot", total, BC.TakedownRange)
	elseif existing then
		existing:Destroy()
	end
end

local function load(userId: number)
	return BountyService.ctx.services.HideoutStore.load(userId)
end

function BountyService.totalOn(userId: number): number
	local rec = BountyService.ctx.services.HideoutStore.cached(userId) or load(userId)
	return BountyRecord.total(rec.bounty)
end

function BountyService.place(player: Player, targetUserId: number, amount: number)
	local S = BountyService.ctx.services
	if type(targetUserId) ~= "number" or targetUserId ~= targetUserId or targetUserId ~= math.floor(targetUserId) or targetUserId <= 0 then
		return
	end
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge then
		Comms.toast(player, "Enter a whole number.", "warn")
		return
	end
	amount = math.floor(amount)
	if amount < BC.MinContribution or amount > BC.MaxContribution then
		Comms.toast(player, string.format("Bounties are %d to %d.", BC.MinContribution, BC.MaxContribution), "warn")
		return
	end
	if targetUserId == player.UserId then
		Comms.toast(player, "You can't put a bounty on yourself.", "warn")
		return
	end
	local crew = S.Crew.crewOf(player)
	if crew then
		for _, m in ipairs(crew.members) do
			if m.UserId == targetUserId then
				Comms.toast(player, "Not on a crewmate. Leave the crew first if you mean it.", "warn")
				return
			end
		end
	end
	local targetName = S.HideoutStore.nameOf(targetUserId)
	-- Debit the contributor's stash first; credit the target's bounty; refund on failure. Never credit first.
	local okSpend, errSpend = S.HideoutStore.apply(player.UserId, function(r)
		return HideoutRecord.spend(r, amount, unix())
	end)
	if not okSpend then
		Comms.toast(player, "Can't fund the bounty: " .. tostring(errSpend), "warn")
		return
	end
	local from = Comms.key(player)
	local okPlace, errPlace, rec = S.HideoutStore.apply(targetUserId, function(r)
		local b, err = BountyRecord.place(r.bounty, from, tostring(targetUserId), amount, unix(), BC.MinContribution)
		if not b then
			return nil, err
		end
		r.bounty = b
		return r, nil
	end)
	if not okPlace then
		S.HideoutStore.apply(player.UserId, function(r)
			return HideoutRecord.deposit(r, amount)
		end)
		Comms.toast(player, "Bounty refused: " .. tostring(errPlace) .. ". Refunded.", "warn")
		S.Hideout.pushState(player)
		return
	end
	local total = BountyRecord.total(rec.bounty)
	S.EventLog.money(from, -amount, "bounty on " .. targetName, 0)
	if crew then
		S.EventLog.crew(crew.id, string.format("%s put %d on %s (bounty now %d)", Comms.name(player), amount, targetName, total))
	end
	Comms.toast(player, string.format("Bounty on %s is now %d. Anyone outside their crew who takes them down on foot collects it. Not you: contributors can't claim.", targetName, total), "good")
	S.Hideout.pushState(player)
	local target = Players:GetPlayerByUserId(targetUserId)
	if target then
		BountyService.syncPrompt(target, total)
		Comms.toast(target, string.format("A bounty was placed on you: %d. Hunters can take you down on foot. Stay in cars, stay with your crew, or lose them.", total), "alarm")
		Comms.cue(target, "Siren")
	end
	Comms.toastAll(string.format("WANTED: %s · bounty %d", targetName, total), "alarm")
end

-- Server-side eligibility for a takedown attempt. Returns (target, reason). Checked at hold start, every
-- tick of the hold, and again at completion; the client decides nothing.
local function eligible(hunter: Player, prompt: ProximityPrompt): (Player?, string?)
	local S = BountyService.ctx.services
	local targetUserId = tonumber(prompt:GetAttribute("TargetUserId"))
	local target = targetUserId and Players:GetPlayerByUserId(targetUserId)
	if not target then
		return nil, "target gone"
	end
	if target == hunter then
		return nil, "that's you"
	end
	if S.Crew.sameCrew(hunter, target) then
		return nil, "crewmates can't claim each other"
	end
	if hunter:GetAttribute("Jailed") or target:GetAttribute("Jailed") then
		return nil, "not from a cell"
	end
	if (stunnedUntil[hunter] or 0) > os.clock() then
		return nil, "you're down"
	end
	local hhum = hunter.Character and hunter.Character:FindFirstChildOfClass("Humanoid")
	local thum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not hhum or hhum.Health <= 0 or not thum or thum.Health <= 0 then
		return nil, "not standing"
	end
	if thum.SeatPart then
		return nil, "they're in a vehicle: takedowns only work on foot"
	end
	if hhum.SeatPart then
		return nil, "get out of the vehicle first"
	end
	local hroot = (hunter.Character :: Model):FindFirstChild("HumanoidRootPart")
	local troot = (target.Character :: Model):FindFirstChild("HumanoidRootPart")
	if not hroot or not troot or not hroot:IsA("BasePart") or not troot:IsA("BasePart") or (hroot.Position - troot.Position).Magnitude > BC.TakedownRange then
		return nil, "too far"
	end
	if (tonumber(target:GetAttribute("Bounty")) or 0) <= 0 then
		return nil, "no bounty"
	end
	return target, nil
end

-- Hold lifecycle (server-timed, like the safe crack): progress only accumulates while eligible.
function BountyService.onTakedownHoldBegin(hunter: Player, prompt: ProximityPrompt)
	local target, why = eligible(hunter, prompt)
	if not target then
		if why and why ~= "no bounty" then
			Comms.toast(hunter, "No takedown: " .. why .. ".", "warn")
		end
		return
	end
	takedowns[hunter] = { target = target, progress = 0, prompt = prompt }
end

function BountyService.onTakedownHold(hunter: Player, prompt: ProximityPrompt, dt: number)
	local td = takedowns[hunter]
	if not td or td.prompt ~= prompt then
		return
	end
	local target = eligible(hunter, prompt)
	if not target or target ~= td.target then
		takedowns[hunter] = nil
		Comms.hud(hunter, { cuffing = 0 })
		return
	end
	td.progress += dt
	Comms.hud(hunter, { cuffing = math.clamp(td.progress / BC.TakedownSeconds, 0, 1) })
	if td.progress >= BC.TakedownSeconds then
		BountyService.completeTakedown(hunter, prompt)
	end
end

-- Prompt Triggered (client hold finished). Accepted only if the server clock agrees, within a small tolerance.
function BountyService.onTakedown(hunter: Player, prompt: ProximityPrompt)
	local td = takedowns[hunter]
	if not td or td.prompt ~= prompt or td.progress < BC.TakedownSeconds - 0.35 then
		return
	end
	BountyService.completeTakedown(hunter, prompt)
end

function BountyService.completeTakedown(hunter: Player, prompt: ProximityPrompt)
	local S = BountyService.ctx.services
	if claiming[hunter] then
		return
	end
	takedowns[hunter] = nil
	Comms.hud(hunter, { cuffing = 0 })
	local target = eligible(hunter, prompt)
	if not target then
		return
	end
	local targetUserId = target.UserId
	local troot = target.Character:FindFirstChild("HumanoidRootPart")
	local thum = target.Character:FindFirstChildOfClass("Humanoid")
	claiming[hunter] = true
	-- Atomic claim on the target's record; the second of two simultaneous hunters gets "no bounty".
	local hunterKey = Comms.key(hunter)
	local ok, result, rec = S.HideoutStore.apply(targetUserId, function(r)
		local b, payout, err = BountyRecord.claim(r.bounty, hunterKey, tostring(targetUserId), false, unix(), BC.ClaimCooldownSeconds)
		if payout <= 0 then
			return nil, err
		end
		r.bounty = b
		return r, payout
	end)
	claiming[hunter] = nil
	if not ok then
		Comms.toast(hunter, "No claim: " .. tostring(result), "warn")
		BountyService.syncPrompt(target, BountyRecord.total(rec and rec.bounty))
		return
	end
	local payout = result
	-- Consequences for the target: down for a few seconds, bag on the ground
	stunnedUntil[target] = os.clock() + BC.StunSeconds
	thum.PlatformStand = true
	task.delay(BC.StunSeconds, function()
		if thum.Parent then
			thum.PlatformStand = false
		end
	end)
	local dropped = S.Loot.dropAll(target, "taken down")
	BountyService.syncPrompt(target, 0)
	S.Hideout.depositStash(hunter, payout, "bounty on " .. Comms.name(target))
	S.Hideout.pushState(target)
	local where = Blueprint.nearestLandmark(troot.Position.X, troot.Position.Z)
	Comms.cue(hunter, "Payout")
	Comms.cue(target, "Arrest")
	Comms.toast(hunter, string.format("Takedown. %d collected on %s%s.", payout, Comms.name(target), if #dropped > 0 then " · they dropped " .. table.concat(dropped, ", ") else ""), "good")
	Comms.toast(target, string.format("%s took you down at %s and collected your bounty (%d).%s", Comms.name(hunter), where, payout, if #dropped > 0 then " You dropped " .. table.concat(dropped, ", ") .. "." else ""), "alarm")
	Comms.toastAll(string.format("%s collected the %d bounty on %s at %s.", Comms.name(hunter), payout, Comms.name(target), where), "info")
	local hcrew = S.Crew.crewOf(hunter)
	if hcrew then
		S.EventLog.crew(hcrew.id, string.format("%s took down %s at %s: +%d", Comms.name(hunter), Comms.name(target), where, payout), "good")
	end
	local tcrew = S.Crew.crewOf(target)
	if tcrew then
		S.EventLog.crew(tcrew.id, string.format("%s was taken down by %s at %s (bounty %d paid)", Comms.name(target), Comms.name(hunter), where, payout), "alarm")
	end
end

-- Wanted list for the board: online players with a bounty, plus anyone online you could place one on.
function BountyService.listWanted(player: Player)
	local S = BountyService.ctx.services
	local crew = S.Crew.crewOf(player)
	local mates = {}
	if crew then
		for _, m in ipairs(crew.members) do
			mates[m.UserId] = true
		end
	end
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			table.insert(out, { userId = p.UserId, name = Comms.name(p), bounty = p:GetAttribute("Bounty") or 0, crewmate = mates[p.UserId] == true, jailed = p:GetAttribute("Jailed") == true })
		end
	end
	table.sort(out, function(a, b)
		return a.bounty > b.bounty
	end)
	Net.event("WantedList"):FireClient(player, { wanted = out, min = BC.MinContribution, max = BC.MaxContribution, cooldown = BC.ClaimCooldownSeconds })
end

function BountyService.init(ctx)
	BountyService.ctx = ctx
end

function BountyService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			BountyService.syncPrompt(player, tonumber(player:GetAttribute("Bounty")) or 0)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		takedowns[player] = nil
		claiming[player] = nil
		stunnedUntil[player] = nil
		for hunter, td in pairs(takedowns) do
			if td.target == player then
				takedowns[hunter] = nil
				Comms.hud(hunter, { cuffing = 0 })
			end
		end
	end)
end

return BountyService
