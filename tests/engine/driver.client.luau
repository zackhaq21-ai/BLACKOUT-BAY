--!nonstrict
-- Test-only client: supplies real seat input on request, never positions or rewards. Built only into the
-- engine-test place. Keeps stray human keyboard input from steering automated clients.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
-- This script exists only in the engine-test place; the server hook creates EngineControl only under test args.
local requireRuntime = require :: any -- PlayerModule is injected by Roblox at runtime, so the sourcemap cannot see it
local controls = requireRuntime(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
controls:Disable()
local net = ReplicatedStorage:WaitForChild("EngineControl", 60)
if not net then
	return
end
local seat
net.OnClientEvent:Connect(function(action, value)
	if action == "Drive" then
		seat = value
	elseif action == "Stop" then
		if seat then
			seat.ThrottleFloat = 0
			seat.SteerFloat = 0
		end
		seat = nil
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = true -- real client dismount input
		end
	end
end)
RunService:BindToRenderStep("GlasshouseEngineDrive", Enum.RenderPriority.Last.Value + 10, function()
	if seat and seat.Parent then
		seat.ThrottleFloat = 1
		seat.SteerFloat = 0
	end
end)
