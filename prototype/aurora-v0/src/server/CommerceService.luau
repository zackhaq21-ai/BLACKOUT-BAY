-- REVIEW SCAFFOLD ONLY. Config and all IDs ship disabled. No live purchase is configured.
-- Permanent cosmetics should use PassId (one-time ownership), not repeatable products.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(game.ReplicatedStorage.Glasshouse.Config)
local Profiles = require(script.Parent.ProfileService)
local Commerce = {}
local passMap, productMap = {}, {}
for _, item in ipairs(Config.Catalog) do
	if item.PassId > 0 then assert(not passMap[item.PassId], "Duplicate pass ID"); passMap[item.PassId] = item end
	if item.ProductId > 0 then assert(not productMap[item.ProductId], "Duplicate product ID"); productMap[item.ProductId] = item end
end

function Commerce.enabled()
	return Config.CommerceEnabled and Config.DataStoreEnabled and not RunService:IsStudio()
end

function Commerce.reconcile(player)
	if not Commerce.enabled() or not Profiles.canCommerce(player.UserId) then return end
	for passId, item in pairs(passMap) do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok and owns then Profiles.queue(player.UserId, {kind = "Pass", item = item.Id}) end
	end
end

function Commerce.prompt(player, itemId)
	if not Commerce.enabled() or not Profiles.canCommerce(player.UserId) then return false, "Shop preview only" end
	local item
	for _, candidate in ipairs(Config.Catalog) do if candidate.Id == itemId then item = candidate end end
	if not item or item.PassId <= 0 then return false, "Unavailable" end
	if Profiles.get(player).entitlements[item.Id] then return false, "Already owned" end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.PassId)
	if not ok then return false, "Ownership check unavailable" end
	if owns then Profiles.queue(player.UserId, {kind = "Pass", item = item.Id}); return false, "Already owned" end
	-- The client shows Roblox's current price; Roblox's final confirmation is authoritative.
	local infoOK, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, item.PassId, Enum.InfoType.GamePass)
	if not infoOK or not info.IsForSale then return false, "Not for sale" end
	local prompted = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, item.PassId)
	return prompted, prompted and "Roblox confirmation opened" or "Shop unavailable"
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, _purchased)
	if not Commerce.enabled() or not passMap[passId] then return end
	-- Re-check the Roblox ownership service. Never trust the client to grant an item.
	Commerce.reconcile(player)
end)

MarketplaceService.ProcessReceipt = function(receipt)
	local deferred = Enum.ProductPurchaseDecision.NotProcessedYet
	if not Commerce.enabled() then return deferred end
	local item = productMap[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not item or not player or not Profiles.canPersist(player.UserId) then return deferred end
	if type(receipt.PurchaseId) ~= "string" or #receipt.PurchaseId > 160 then return deferred end
	-- Same key, atomic grant + durable receipt ledger, callback safe to re-run.
	local saved = Profiles.transaction(player.UserId, {kind = "Receipt", receipt = receipt.PurchaseId, item = item.Id})
	if saved then return Enum.ProductPurchaseDecision.PurchaseGranted end
	return deferred
end
return Commerce
