--!nonstrict
-- BLACKOUT BAY client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Net = require(ReplicatedStorage.Shared.Net)

local HudController = require(script.Controllers.HudController)
local BoardController = require(script.Controllers.BoardController)
local KeypadController = require(script.Controllers.KeypadController)
local ResultsController = require(script.Controllers.ResultsController)
local InputController = require(script.Controllers.InputController)
local VehicleController = require(script.Controllers.VehicleController)
local NameplateController = require(script.Controllers.NameplateController)
local AudioController = require(script.Controllers.AudioController)

-- The HUD shows cash and names; hide the default leaderboard to keep the screen clean on phones.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

HudController.init()
local bootstrap = {}
local ok, result = pcall(function()
	return Net.func("GetBootstrap"):InvokeServer()
end)
if ok and type(result) == "table" then
	bootstrap = result
else
	warn("[GLASSHOUSE] bootstrap failed: " .. tostring(result))
end
HudController.applyBootstrap(bootstrap)
BoardController.init(bootstrap)
KeypadController.init()
ResultsController.init()
InputController.init(HudController)
VehicleController.init(HudController)
NameplateController.init()
AudioController.init(HudController)
Net.event("MissionRequest"):FireServer({ action = "refresh" })
Net.event("CrewRequest"):FireServer({ action = "refresh" })
HudController.toast("Welcome to Blackout Bay. Your pier is behind you; the job board is on the back wall.", "info")
