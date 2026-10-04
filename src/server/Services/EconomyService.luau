--!nonstrict
-- Earned currency ("Marks"). Server-authoritative; every change is logged with a reason.
-- Cash is also exposed as a player attribute so every nameplate shows it (everyone can see what you have).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Comms = require(script.Parent.Comms)

local EconomyService = { ctx = nil :: any }

function EconomyService.init(ctx)
	EconomyService.ctx = ctx
end

function EconomyService.start()
	local Data = EconomyService.ctx.services.Data
	local function setup(player)
		local profile = Data.waitFor(player)
		if profile then
			player:SetAttribute("Cash", profile.data.cash)
			Comms.hud(player, { cash = profile.data.cash, saveable = profile.saveable, saveReason = profile.reason })
			if not profile.saveable then
				Comms.toast(player, "Progress will not be saved this session: " .. tostring(profile.reason), "warn")
			end
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(setup, p)
	end
end

function EconomyService.balance(player: Player): number
	local profile = EconomyService.ctx.services.Data.get(player)
	return if profile then profile.data.cash else 0
end

local function apply(player: Player, delta: number, reason: string): boolean
	local Data = EconomyService.ctx.services.Data
	local profile = Data.get(player)
	if not profile then
		return false
	end
	if delta ~= math.floor(delta) then
		return false
	end
	local newBalance = profile.data.cash + delta
	if newBalance < 0 then
		return false
	end
	profile.data.cash = newBalance
	Data.markDirty(player)
	player:SetAttribute("Cash", newBalance)
	EconomyService.ctx.services.EventLog.money(Comms.key(player), delta, reason, newBalance)
	Comms.hud(player, { cash = newBalance })
	return true
end

function EconomyService.credit(player: Player, amount: number, reason: string): boolean
	if amount <= 0 then
		return false
	end
	return apply(player, amount, reason)
end

function EconomyService.debit(player: Player, amount: number, reason: string): boolean
	if amount <= 0 then
		return false
	end
	return apply(player, -amount, reason)
end

function EconomyService.bumpStat(player: Player, stat: string, by: number?)
	local Data = EconomyService.ctx.services.Data
	local profile = Data.get(player)
	if profile and profile.data.stats[stat] ~= nil then
		profile.data.stats[stat] += by or 1
		Data.markDirty(player)
	end
end

function EconomyService.lootValue(kind: string): number
	local spec = Config.Economy.Loot[kind]
	return if spec then spec.value else 0
end

return EconomyService
