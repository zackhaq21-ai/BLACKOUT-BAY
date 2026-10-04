--!nonstrict
-- Server-authoritative movement state: sprint, sneak and carry weight set WalkSpeed; heavy carriers
-- cannot climb or jump. Clients only request intent.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MovementService = { ctx = nil :: any }

function MovementService.init(ctx)
	MovementService.ctx = ctx
end

function MovementService.apply(player: Player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local Loot = MovementService.ctx.services.Loot
	local heavy = Loot and Loot.isCarryingHeavy(player) or false
	local carrying = Loot and Loot.carriedLabel(player) ~= nil or false
	local sneaking = player:GetAttribute("Sneaking") == true
	local sprinting = player:GetAttribute("Sprinting") == true
	local speed = Config.Player.WalkSpeed
	if heavy then
		speed = Config.Player.HeavyCarrySpeed
	elseif sprinting then
		speed = if carrying then Config.Player.LightCarrySprintSpeed else Config.Player.SprintSpeed
	end
	if sneaking then
		speed = math.min(speed, Config.Player.SneakSpeed)
	end
	humanoid.WalkSpeed = speed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = if heavy then 0 else 50
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, not heavy)
end

function MovementService.setSneak(player: Player, on: boolean)
	player:SetAttribute("Sneaking", on == true)
	if on then
		player:SetAttribute("Sprinting", false)
	end
	MovementService.apply(player)
end

function MovementService.setSprint(player: Player, on: boolean)
	player:SetAttribute("Sprinting", on == true)
	if on then
		player:SetAttribute("Sneaking", false)
	end
	MovementService.apply(player)
end

function MovementService.start()
	local function hook(player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Humanoid", 10)
			player:SetAttribute("Sneaking", false)
			player:SetAttribute("Sprinting", false)
			MovementService.apply(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
		if p.Character then
			MovementService.apply(p)
		end
	end
end

return MovementService
