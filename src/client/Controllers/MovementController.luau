--!nonstrict
-- Character feel (client-only, cosmetic): landing response, sprint start cue, speed-synchronised animation
-- check. The server still owns WalkSpeed, jump and carry rules; nothing here changes where the character is.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Vfx = require(script.Parent.Parent.Fx.Vfx)

local MovementController = {}

local player = Players.LocalPlayer
local camera, audio
local connections = {}
local lastFallSpeed = 0

local function clear()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	connections = {}
end

local function hook(char: Model)
	clear()
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then
		return
	end
	-- Track the fall so the landing knows how hard it was
	table.insert(connections, hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			lastFallSpeed = 0
		elseif new == Enum.HumanoidStateType.Landed then
			local v = math.max(lastFallSpeed, -root.AssemblyLinearVelocity.Y)
			if camera then
				camera.landed(v)
			end
			if v > Config.Presentation.Camera.LandingDipMinFall then
				Vfx.burst("Dust", root.Position - Vector3.new(0, 2.8, 0), math.clamp(v / 50, 0.4, 1.2))
				if audio then
					audio.feel("Land", math.clamp(v / 60, 0.2, 1))
				end
			end
		end
	end))
	table.insert(connections, game:GetService("RunService").Heartbeat:Connect(function()
		if hum:GetState() == Enum.HumanoidStateType.Freefall then
			lastFallSpeed = math.max(lastFallSpeed, -root.AssemblyLinearVelocity.Y)
		end
	end))
	-- Sprint start cue (intent attribute replicated back from the server)
	table.insert(connections, player:GetAttributeChangedSignal("Sprinting"):Connect(function()
		if player:GetAttribute("Sprinting") == true and audio then
			audio.feel("SprintStart", 0.6)
		end
	end))
end

function MovementController.init(cameraController, audioController)
	camera = cameraController
	audio = audioController
	if player.Character then
		hook(player.Character)
	end
	player.CharacterAdded:Connect(hook)
end

return MovementController
