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
local Stats = game:GetService("Stats")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local function clientPerf(seconds: number)
	local frames, t0 = 0, os.clock()
	local worst = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		frames += 1
		worst = math.max(worst, dt)
	end)
	task.wait(seconds)
	conn:Disconnect()
	local elapsed = math.max(0.001, os.clock() - t0)
	local playing, emitters = 0, 0
	for _, s in ipairs(SoundService:GetDescendants()) do
		if s:IsA("Sound") and s.IsPlaying then
			playing += 1
		end
	end
	for _, d in ipairs(Workspace.Terrain:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Enabled then
			emitters += 1
		end
	end
	local okMem, mem = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	return {
		fps = math.floor(frames / elapsed * 10) / 10,
		worstFrameMs = math.floor(worst * 1000 * 10) / 10,
		clientMemoryMb = if okMem then math.floor(mem) else -1,
		playingSounds = playing,
		enabledEmitters = emitters,
		fov = Workspace.CurrentCamera and math.floor(Workspace.CurrentCamera.FieldOfView * 10) / 10 or -1,
	}
end
local function setTier(name: string): string
	local okReq, env = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers"):WaitForChild("EnvironmentController"))
	end)
	if not okReq then
		return "unavailable"
	end
	for _ = 1, 6 do
		if env.tierLabel() == name then
			return name
		end
		env.cycleTier()
	end
	return env.tierLabel()
end
local seat
net.OnClientEvent:Connect(function(action, value)
	if action == "Perf" then
		local sample = clientPerf(type(value) == "number" and value or 2)
		net:FireServer("Perf", sample)
		return
	elseif action == "SetTier" then
		net:FireServer("Tier", setTier(tostring(value)))
		return
	end
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
