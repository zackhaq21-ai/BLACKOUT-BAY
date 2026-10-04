-- Local Studio launch helper only. Starts actual native game; no test teleports or rewards.
-- run-in-roblox closes its own Studio instance after the user stops this play session.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio())
if not RunService:IsEdit() then while task.wait(5) do end end
local starter = Instance.new("LocalScript")
starter.Name = "GlasshousePrivateSoloStart"
starter.Source = [==[
local player = game:GetService("Players").LocalPlayer
local net = game.ReplicatedStorage:WaitForChild("Glasshouse"):WaitForChild("Net")
local attempted = false
net.State.OnClientEvent:Connect(function(state)
	if not attempted and state.status == "Lobby" and state.host == player.UserId and state.saveStatus ~= "Loading" then
		attempted = true
		task.delay(0.5, function() net.Command:FireServer("Start", "Shuffle") end)
	end
end)
]==]
starter.Parent = game.StarterPlayer.StarterPlayerScripts
print("GLASSHOUSE_PRIVATE_PLAY_OPENING")
game:GetService("StudioTestService"):ExecutePlayModeAsync({privateGlasshousePlay = true})
print("GLASSHOUSE_PRIVATE_PLAY_STOPPED")
