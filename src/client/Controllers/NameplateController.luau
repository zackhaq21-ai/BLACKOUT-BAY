--!nonstrict
-- Nameplates: everyone can see what you have. Name, crew colour, cash, what you carry, and police attention.
-- Crewmates also show distance so a crew can find each other without a map.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Parent.UI.Theme)

local NameplateController = {}

local player = Players.LocalPlayer
local plates = {} -- Player -> { gui, name, info }

local function fmt(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function attach(other: Player, char: Model)
	local head = char:WaitForChild("Head", 10)
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "GlassPlate"
	bb.Size = UDim2.fromOffset(200, 54)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 120
	bb.AlwaysOnTop = false
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 22)
	name.BackgroundTransparency = 1
	name.Font = Theme.FontBold
	name.TextSize = 18
	name.TextStrokeTransparency = 0.3
	name.TextColor3 = Theme.Text
	name.Text = other.DisplayName
	name.Parent = bb
	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, 0, 0, 30)
	info.Position = UDim2.new(0, 0, 0, 22)
	info.BackgroundTransparency = 1
	info.Font = Theme.Font
	info.TextSize = 14
	info.TextStrokeTransparency = 0.3
	info.TextColor3 = Palette.Gold
	info.TextWrapped = true
	info.Parent = bb
	bb.Parent = head
	plates[other] = { gui = bb, name = name, info = info }
end

local function hook(other: Player)
	if other == player then
		return
	end
	if other.Character then
		task.spawn(attach, other, other.Character)
	end
	other.CharacterAdded:Connect(function(char)
		attach(other, char)
	end)
end

local function refresh()
	local myCrew = player:GetAttribute("CrewId")
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for other, plate in pairs(plates) do
		if not other.Parent or not plate.gui.Parent then
			plates[other] = nil
		else
			local crewId = other:GetAttribute("CrewId")
			local colorIndex = other:GetAttribute("CrewColor") or 1
			local sameCrew = crewId ~= nil and crewId == myCrew
			plate.name.TextColor3 = if sameCrew then Palette.CrewColors[colorIndex] or Theme.Accent else Theme.Text
			local parts = { "stash " .. fmt(other:GetAttribute("Stash") or 0) .. " · T" .. tostring(other:GetAttribute("HideoutTier") or 0) }
			local carrying = other:GetAttribute("Carrying")
			if carrying then
				table.insert(parts, "carrying " .. carrying)
			end
			if (other:GetAttribute("Bounty") or 0) > 0 then
				table.insert(parts, "BOUNTY " .. fmt(other:GetAttribute("Bounty")))
			end
			if (other:GetAttribute("HeatLevel") or 0) > 0 then
				table.insert(parts, "WANTED")
			end
			if other:GetAttribute("Jailed") then
				table.insert(parts, "in a cell")
			end
			if sameCrew and myRoot and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
				table.insert(parts, string.format("%d st", math.floor((other.Character.HumanoidRootPart.Position - myRoot.Position).Magnitude)))
				plate.gui.MaxDistance = 400
			else
				plate.gui.MaxDistance = 120
			end
			plate.info.Text = table.concat(parts, " · ")
			plate.info.TextColor3 = if (other:GetAttribute("HeatLevel") or 0) > 0 or (other:GetAttribute("Bounty") or 0) > 0 then Palette.SecurityRed else Palette.Gold
		end
	end
end

function NameplateController.init()
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(p)
		plates[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
end

return NameplateController
