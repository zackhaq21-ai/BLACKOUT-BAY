--!nonstrict
-- REVIEW SCAFFOLD ONLY, carried over from the prototype. Config.Commerce.Enabled is false and every id is 0,
-- so nothing can be purchased. When a release is separately authorised: permanent cosmetics use game passes
-- (one-time ownership confirmed by Roblox); developer products are fulfilled ONLY through ProcessReceipt after
-- the entitlement and the receipt are durable in the same profile transaction.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ProfileOps = require(ReplicatedStorage.Shared.Core.ProfileOps)
local Comms = require(script.Parent.Comms)

local CommerceService = { ctx = nil :: any }

local passMap, productMap = {}, {}
for _, item in ipairs(Config.Commerce.Catalog) do
	if item.PassId > 0 then
		assert(not passMap[item.PassId], "Duplicate pass ID")
		passMap[item.PassId] = item
	end
	if item.ProductId > 0 then
		assert(not productMap[item.ProductId], "Duplicate product ID")
		productMap[item.ProductId] = item
	end
end

function CommerceService.enabled(): boolean
	return Config.Commerce.Enabled and not RunService:IsStudio()
end

function CommerceService.init(ctx)
	CommerceService.ctx = ctx
end

local function canCommerce(player: Player): boolean
	return CommerceService.enabled() and CommerceService.ctx.services.Data.isLive(player)
end

-- Re-check Roblox's ownership service; never trust the client to grant an item.
function CommerceService.reconcile(player: Player)
	if not canCommerce(player) then
		return
	end
	local Data = CommerceService.ctx.services.Data
	for passId, item in pairs(passMap) do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok and owns then
			Data.applyOp(player, { kind = "Pass", item = item.Id })
		end
	end
end

function CommerceService.prompt(player: Player, itemId: string): (boolean, string)
	if not canCommerce(player) then
		return false, "Shop preview only. Nothing is for sale in this build."
	end
	local item = ProfileOps.find(Config.Commerce.Catalog, itemId)
	if not item or item.PassId <= 0 then
		return false, "Unavailable"
	end
	local profile = CommerceService.ctx.services.Data.get(player)
	if profile and ProfileOps.owns(profile.data, item.Id) then
		return false, "Already owned"
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.PassId)
	if not ok then
		return false, "Ownership check unavailable"
	end
	if owns then
		CommerceService.ctx.services.Data.applyOp(player, { kind = "Pass", item = item.Id })
		return false, "Already owned"
	end
	local infoOk, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, item.PassId, Enum.InfoType.GamePass)
	if not infoOk or not info.IsForSale then
		return false, "Not for sale"
	end
	local prompted = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, item.PassId)
	return prompted, if prompted then "Roblox confirmation opened" else "Shop unavailable"
end

function CommerceService.start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId)
		if CommerceService.enabled() and passMap[passId] then
			CommerceService.reconcile(player)
		end
	end)
	MarketplaceService.ProcessReceipt = function(receipt)
		local deferred = Enum.ProductPurchaseDecision.NotProcessedYet
		if not CommerceService.enabled() then
			return deferred
		end
		local item = productMap[receipt.ProductId]
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not item or not player or not CommerceService.ctx.services.Data.isLive(player) then
			return deferred
		end
		if type(receipt.PurchaseId) ~= "string" or #receipt.PurchaseId > 160 then
			return deferred
		end
		-- Grant only when the entitlement + receipt are durable in the same transaction; safe to re-run.
		local _, durable = CommerceService.ctx.services.Data.applyOp(player, { kind = "Receipt", receipt = receipt.PurchaseId, item = item.Id })
		if durable then
			Comms.toast(player, item.Name .. " is yours permanently.", "good")
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return deferred
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			CommerceService.ctx.services.Data.waitFor(player)
			CommerceService.reconcile(player)
		end)
	end)
end

return CommerceService
