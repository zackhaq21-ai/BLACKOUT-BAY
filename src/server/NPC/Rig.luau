--!nonstrict
-- NPC character rigs built at runtime. Prefers a default R15 rig from Players:CreateHumanoidModelFromDescription
-- (no asset ids needed); falls back to a simple block rig if that is unavailable (e.g. offline Studio).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)

local Rig = {}

local function blockRig(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = m
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = root.CFrame
	torso.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = root.CFrame * CFrame.new(0, 1.6, 0)
	head.Parent = m
	for _, side in ipairs({ -1, 1 }) do
		local leg = Instance.new("Part")
		leg.Name = if side < 0 then "Left Leg" else "Right Leg"
		leg.Size = Vector3.new(1, 2, 1)
		leg.CFrame = root.CFrame * CFrame.new(side * 0.5, -2, 0)
		leg.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = leg
		w.Parent = root
	end
	for _, p in ipairs({ torso, head }) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = root
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 2
	humanoid.Parent = m
	m.PrimaryPart = root
	return m
end

function Rig.create(name: string, color: Color3, label: string, parent: Instance, cf: CFrame): Model
	local model
	local ok, result = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and result then
		model = result
		model.Name = name
		-- Strip any default scripts/animations and recolour as a uniform
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("Decal") or d:IsA("Accessory") then
				d:Destroy()
			elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.Color = color
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	else
		model = blockRig(name)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.Color = color
			end
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = true
	-- Cap/vest accent so guards and police read at a glance
	local head = model:FindFirstChild("Head")
	if head then
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Size = Vector3.new(1.3, 0.4, 1.3)
		cap.Color = Palette.Night
		cap.Material = Enum.Material.SmoothPlastic
		cap.CanCollide = false
		cap.Massless = true
		cap.CFrame = head.CFrame * CFrame.new(0, 0.75, 0)
		cap.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = cap
		w.Parent = cap
		local bb = Instance.new("BillboardGui")
		bb.Name = "Nameplate"
		bb.Size = UDim2.fromOffset(160, 30)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.MaxDistance = 60
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = label
		tl.TextColor3 = Palette.PaleStone
		tl.TextStrokeTransparency = 0.3
		tl.TextScaled = true
		tl.Font = Enum.Font.GothamMedium
		tl.Parent = bb
		bb.Parent = head
	end
	model:SetAttribute("NPC", true)
	model:SetAttribute("Label", label)
	model.Parent = parent
	model:PivotTo(cf)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d:SetNetworkOwner(nil)
		end
	end
	return model
end

function Rig.setPlateText(model: Model, text: string)
	local head = model:FindFirstChild("Head")
	local bb = head and head:FindFirstChild("Nameplate")
	local tl = bb and bb:FindFirstChildOfClass("TextLabel")
	if tl then
		tl.Text = text
	end
end

return Rig
