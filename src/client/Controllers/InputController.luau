--!nonstrict
-- Input bindings for keyboard, gamepad and touch: sprint, sneak, drop, crew log. The server owns the
-- resulting movement state; this only sends intent.
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local InputController = {}

local sneaking = false
local sprinting = false
local hud

local function setSneak(on: boolean)
	if sneaking ~= on then
		sneaking = on
		if on then
			sprinting = false
		end
		Net.event("SetSneak"):FireServer(on)
	end
end

local function setSprint(on: boolean)
	if sprinting ~= on then
		sprinting = on
		if on then
			sneaking = false
		end
		Net.event("SetSprint"):FireServer(on)
	end
end

local function touchButton(name: string, title: string, pos: UDim2)
	ContextActionService:SetTitle(name, title)
	ContextActionService:SetPosition(name, pos)
end

function InputController.init(hudController)
	hud = hudController
	ContextActionService:BindAction("Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			setSprint(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setSprint(false)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction("Sneak", function(_, state)
		if state == Enum.UserInputState.Begin then
			setSneak(not sneaking)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("DropBag", function(_, state)
		if state == Enum.UserInputState.Begin then
			Net.event("DropCarry"):FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("CrewLog", function(_, state)
		if state == Enum.UserInputState.Begin then
			hud.toggleLog()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.L, Enum.KeyCode.DPadUp)
	if UserInputService.TouchEnabled then
		touchButton("Sprint", "RUN", UDim2.new(1, -230, 1, -130))
		touchButton("Sneak", "SNEAK", UDim2.new(1, -160, 1, -200))
		touchButton("DropBag", "DROP", UDim2.new(1, -300, 1, -200))
		touchButton("CrewLog", "LOG", UDim2.new(1, -90, 1, -270))
		hud.setHints("RUN / SNEAK / DROP buttons · tap prompts to interact")
	elseif UserInputService.GamepadEnabled then
		hud.setHints("L3 sprint · B sneak · Y drop bag · X interact · D-pad up log")
	end
	-- Sneak ends when the character respawns
	local player = game:GetService("Players").LocalPlayer
	player.CharacterAdded:Connect(function()
		sneaking = false
		sprinting = false
	end)
end

return InputController
