--!nonstrict
-- Server-authoritative movement state: sprint, sneak and carry weight set WalkSpeed; heavy carriers
-- cannot climb or jump. Clients only request intent.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MovementService = { ctx = nil :: any }

local relocateRevision = {} -- userId -> revision
local grace = {} -- userId -> os.clock() until which speed checks are skipped
local motion = {} -- userId -> { position, time }
local FOOT_SPEED = 32 -- studs/s allowance on foot (sprint 21 + slack)
local SEAT_SPEED = 90 -- studs/s allowance seated (fastest car 70 + slack)

-- Move a character reliably: drop any seat weld, briefly take server ownership so an in-flight client
-- physics update cannot undo the move, then restore normal ownership (carried over from the prototype).
function MovementService.relocate(player: Player, cf: CFrame)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local id = player.UserId
	relocateRevision[id] = (relocateRevision[id] or 0) + 1
	local revision = relocateRevision[id]
	local seat = hum.SeatPart
	hum.Sit = false
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") and weld.Part1 and weld.Part1:IsDescendantOf(char) then
		weld:Destroy()
	end
	pcall(function()
		if root:CanSetNetworkOwnership() then
			root:SetNetworkOwner(nil)
		end
	end)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(cf)
	grace[id] = os.clock() + 2
	motion[id] = { position = cf.Position, time = os.clock() }
	task.delay(0.5, function()
		while relocateRevision[id] == revision and root.Parent and player.Character == char and hum.SeatPart do
			task.wait(0.1)
		end
		if relocateRevision[id] == revision and root.Parent and player.Character == char and not hum.SeatPart then
			pcall(function()
				if root:CanSetNetworkOwnership() then
					root:SetNetworkOwnershipAuto()
				end
			end)
		end
	end)
end

-- Server-side sanity on character motion: NaN/far positions and impossible displacement snap back.
local function checkMotion(player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	local id, pos, now = player.UserId, root.Position, os.clock()
	local Hideout = MovementService.ctx.services.Hideout
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z or pos.Magnitude > 5000 then
		Hideout.sendHome(player)
		return
	end
	if pos.Y < -14 then
		-- fell into the sea: back to the pier, loot drops where you went under
		MovementService.ctx.services.Loot.dropAll(player, "lost in the water")
		Hideout.sendHome(player)
		return
	end
	local last = motion[id]
	local seated = hum.SeatPart ~= nil
	if last and now > (grace[id] or 0) then
		local flat = Vector3.new(pos.X, 0, pos.Z) - Vector3.new(last.position.X, 0, last.position.Z)
		local allowed = (if seated then SEAT_SPEED else FOOT_SPEED) * (now - last.time) + 9
		if flat.Magnitude > allowed then
			MovementService.relocate(player, CFrame.new(last.position))
			return
		end
	end
	motion[id] = { position = pos, time = now }
end

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
	Players.PlayerRemoving:Connect(function(player)
		relocateRevision[player.UserId] = nil
		grace[player.UserId] = nil
		motion[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, p in ipairs(Players:GetPlayers()) do
				checkMotion(p)
			end
		end
	end)
end

return MovementService
