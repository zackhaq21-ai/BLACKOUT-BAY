--!nonstrict
-- Earned/owned looks. A suit recolours the character; it never changes stats, hitboxes or visibility.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ProfileOps = require(ReplicatedStorage.Shared.Core.ProfileOps)
local Comms = require(script.Parent.Comms)

local CosmeticsService = { ctx = nil :: any }
local equipAt = {}

function CosmeticsService.init(ctx)
	CosmeticsService.ctx = ctx
end

function CosmeticsService.apply(player: Player)
	local profile = CosmeticsService.ctx.services.Data.get(player)
	local char = player.Character
	if not profile or not char then
		return
	end
	local item = ProfileOps.find(Config.Commerce.Catalog, profile.data.equipped)
	if not item or not ProfileOps.owns(profile.data, item.Id) or item.Kind ~= "Suit" then
		return
	end
	local color = Color3.fromRGB(item.Color[1], item.Color[2], item.Color[3])
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Name ~= "Head" then
			p.Color = color
			p.Material = Enum.Material.SmoothPlastic
		end
	end
end

function CosmeticsService.push(player: Player)
	local profile = CosmeticsService.ctx.services.Data.get(player)
	if not profile then
		return
	end
	Net.event("ProfileState"):FireClient(player, {
		xp = profile.data.xp,
		wins = profile.data.wins,
		jobs = profile.data.stats.jobs,
		entitlements = profile.data.entitlements,
		equipped = profile.data.equipped,
		catalog = Config.Commerce.Catalog,
		commerce = CosmeticsService.ctx.services.Commerce.enabled(),
		saveable = profile.saveable,
	})
end

function CosmeticsService.handleRequest(player: Player, req)
	if type(req) ~= "table" then
		return
	end
	local Data = CosmeticsService.ctx.services.Data
	if req.action == "equip" and type(req.item) == "string" and #req.item <= 40 then
		local now = os.clock()
		if now - (equipAt[player] or -10) < 2 then
			return
		end
		equipAt[player] = now
		local profile = Data.get(player)
		if not profile or not ProfileOps.owns(profile.data, req.item) then
			Comms.toast(player, "Earn this look first. No gameplay tool ever requires a purchase.", "warn")
			return
		end
		Data.applyOp(player, { kind = "Equip", item = req.item })
		CosmeticsService.apply(player)
		CosmeticsService.push(player)
	elseif req.action == "buy" and type(req.item) == "string" and #req.item <= 40 then
		task.spawn(function()
			local _, message = CosmeticsService.ctx.services.Commerce.prompt(player, req.item)
			Comms.toast(player, message, "info")
		end)
	elseif req.action == "refresh" then
		CosmeticsService.push(player)
	end
end

function CosmeticsService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Humanoid", 10)
			task.wait(0.2)
			CosmeticsService.apply(player)
		end)
		task.spawn(function()
			CosmeticsService.ctx.services.Data.waitFor(player)
			CosmeticsService.apply(player)
			CosmeticsService.push(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		equipAt[player] = nil
	end)
end

return CosmeticsService
