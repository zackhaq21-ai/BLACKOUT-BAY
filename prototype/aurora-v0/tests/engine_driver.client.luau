-- Test-only client: supplies seat input, never positions or rewards.
local RS = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer
-- Keep human keyboard activity in other tasks from steering this automated client.
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
controls:Disable()
local net = game.ReplicatedStorage:WaitForChild("Glasshouse"):WaitForChild("EngineControl")
local seat
net.OnClientEvent:Connect(function(action, value)
	if action == "Drive" then seat = value
	elseif action == "Stop" then
		if seat then seat.ThrottleFloat = 0; seat.SteerFloat = 0 end
		seat = nil
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Jump = true end -- actual client jump/dismount input
	end
end)
RS:BindToRenderStep("GlasshouseEngineDrive", Enum.RenderPriority.Last.Value + 10, function()
	if seat and seat.Parent then seat.ThrottleFloat = 1; seat.SteerFloat = 0 end
end)
