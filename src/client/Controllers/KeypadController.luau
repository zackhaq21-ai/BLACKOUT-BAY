--!nonstrict
-- Numeric keypad for the dock door. Big buttons for touch; digits also typed on keyboard.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Make = require(script.Parent.Parent.UI.Make)

local KeypadController = {}

local player = Players.LocalPlayer
local gui, display
local entry = ""
local targetId = nil
local digits = 4
local firstButton

local function refresh()
	display.Text = if #entry > 0 then entry .. string.rep("•", math.max(0, digits - #entry)) else string.rep("•", digits)
end

local function press(d: string)
	if #entry < digits then
		entry ..= d
		refresh()
	end
end

local function submit()
	if #entry == digits then
		Net.event("KeypadSubmit"):FireServer({ targetId = targetId, code = entry })
		entry = ""
		refresh()
	end
end

function KeypadController.close()
	gui.Enabled = false
	GuiService.SelectedObject = nil
	entry = ""
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GlasshouseKeypad"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local panel = Make.panel(gui, "Keypad", UDim2.new(0, 260, 0, 380), UDim2.new(0.5, -130, 0.5, -190))
	panel.BackgroundTransparency = 0.05
	display = Make.label(panel, "Display", "••••", Theme.Big, Theme.Accent, true)
	display.TextXAlignment = Enum.TextXAlignment.Center
	display.Size = UDim2.new(1, 0, 0, 40)
	display.AutomaticSize = Enum.AutomaticSize.None
	local grid = Make.frame(panel, "Grid", UDim2.new(1, 0, 1, -50), UDim2.new(0, 0, 0, 50), Theme.Panel, 1)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.3333, -4, 0.25, -4)
	layout.CellPadding = UDim2.new(0, 4, 0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK" }
	for i, k in ipairs(keys) do
		local b = Make.button(grid, "K" .. k, k, if k == "OK" then Theme.Accent elseif k == "C" then Theme.Warn else Theme.PanelAlt, function()
			if k == "C" then
				entry = ""
				refresh()
			elseif k == "OK" then
				submit()
			else
				press(k)
			end
		end)
		b.TextColor3 = if k == "OK" or k == "C" then Theme.Panel else Theme.Text
		b.TextSize = Theme.Title
		b.LayoutOrder = i
		if i == 1 then
			firstButton = b
		end
	end
end

function KeypadController.init()
	build()
	Net.event("OpenKeypad").OnClientEvent:Connect(function(d)
		targetId = d.targetId
		digits = d.digits or 4
		entry = ""
		refresh()
		gui.Enabled = true
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = firstButton
		end
	end)
	Net.event("CloseKeypad").OnClientEvent:Connect(KeypadController.close)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not gui.Enabled or processed then
			return
		end
		local name = input.KeyCode.Name
		local digit = name:match("^Keypad(%d)$") or name:match("^(%d)$")
		if digit then
			press(digit)
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			submit()
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			entry = entry:sub(1, -2)
			refresh()
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			KeypadController.close()
		end
	end)
	-- Walking away closes it
	task.spawn(function()
		while true do
			task.wait(0.5)
			if gui.Enabled then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local keypad = workspace:FindFirstChild("DockKeypad", true)
				if root and keypad and (root.Position - keypad.Position).Magnitude > 12 then
					KeypadController.close()
				end
			end
		end
	end)
end

return KeypadController
