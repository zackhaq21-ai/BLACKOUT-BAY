--!nonstrict
-- Single entry point for client intent: proximity prompts and remotes. Validates the character, distance,
-- and rate before routing to the owning service. Held prompts (drill, glass cutting) report while held.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Core.RateLimiter)
local Comms = require(script.Parent.Comms)

local InteractionService = { ctx = nil :: any }

local limiter = RateLimiter.new(Config.Net.RequestsPerSecond, Config.Net.Burst)
local handlers = {}
local holdHandlers = {} -- tag -> { begin = fn?, hold = fn?, done = fn? }
local holding = {} -- player -> { prompt, tag, thread }

local function allowed(player: Player, cost: number?): boolean
	return limiter:allow(Comms.key(player), os.clock(), cost)
end

local function validPrompt(player: Player, prompt: ProximityPrompt): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local part = prompt.Parent
	if not part or not part:IsA("BasePart") then
		return false
	end
	local range = math.max(prompt.MaxActivationDistance, Config.Net.InteractRange) + 4
	return (part.Position - root.Position).Magnitude <= range
end

-- Same validation as a real prompt trigger; used by the engine test hook so tests exercise the handlers.
function InteractionService.dispatch(player: Player, prompt: ProximityPrompt): boolean
	local tag = prompt:GetAttribute("Tag")
	local fn = tag and handlers[tag]
	if not fn or not validPrompt(player, prompt) then
		return false
	end
	local ok, err = pcall(fn, player, prompt)
	if not ok then
		warn("[Interaction] " .. tostring(tag) .. " failed: " .. tostring(err))
		return false
	end
	return true
end

function InteractionService.register(tag: string, fn)
	handlers[tag] = fn
end

function InteractionService.registerHold(tag: string, spec)
	holdHandlers[tag] = spec
end

function InteractionService.init(ctx)
	InteractionService.ctx = ctx
end

function InteractionService.start()
	local S = InteractionService.ctx.services
	-- Prompt routes
	InteractionService.register("Deliver", S.Hideout.onDeliver)
	InteractionService.register("SpawnVehicle", S.Hideout.onSpawnVehicle)
	InteractionService.register("LootPickup", S.Loot.onPickup)
	InteractionService.register("LootTake", S.Loot.onTake)
	InteractionService.register("CaseCut", S.Loot.onCaseCut)
	InteractionService.register("Trunk", S.Vehicle.onTrunk)
	InteractionService.register("FrontSmash", S.Security.onFrontSmash)
	InteractionService.register("DockKeypad", S.Security.onKeypadOpen)
	InteractionService.register("DockRelease", S.Security.onDockRelease)
	InteractionService.register("JunctionBox", S.Security.onJunctionBox)
	InteractionService.register("CameraSwitch", S.Security.onCameraSwitch)
	InteractionService.register("OfficeCard", S.Security.onOfficeCard)
	InteractionService.register("Pickpocket", S.Security.onPickpocket)
	InteractionService.register("Reader", S.Security.onReader)
	InteractionService.register("Drill", S.Security.onDrillDone)
	InteractionService.register("Lockpick", S.Police.onLockpick)
	InteractionService.register("CellRelease", S.Police.onCellRelease)
	InteractionService.register("RaidBreaker", S.Raid.onBreaker)
	InteractionService.register("RaidPierDoor", S.Raid.onPierDoor)
	InteractionService.register("RaidSafe", S.Raid.onSafe)
	InteractionService.register("Takedown", S.Bounty.onTakedown)
	InteractionService.register("Contact", S.Contact.onTalk)
	InteractionService.registerHold("Drill", { begin = S.Security.onDrillStart, hold = function(player, _prompt, dt)
		S.Security.onDrillHold(player, dt)
	end })
	InteractionService.registerHold("CaseCut", { hold = S.Security.onCaseCutHold })
	InteractionService.registerHold("Takedown", { begin = S.Bounty.onTakedownHoldBegin, hold = S.Bounty.onTakedownHold })

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if not allowed(player) then
			return
		end
		local tag = prompt:GetAttribute("Tag")
		local fn = tag and handlers[tag]
		if fn and validPrompt(player, prompt) then
			local ok, err = pcall(fn, player, prompt)
			if not ok then
				warn("[Interaction] " .. tostring(tag) .. " failed: " .. tostring(err))
			end
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
		local tag = prompt:GetAttribute("Tag")
		local spec = tag and holdHandlers[tag]
		if not spec or not validPrompt(player, prompt) then
			return
		end
		if holding[player] then
			task.cancel(holding[player].thread)
		end
		if spec.begin then
			spec.begin(player, prompt)
		end
		local thread = task.spawn(function()
			local last = os.clock()
			while true do
				task.wait(0.25)
				local t = os.clock()
				if spec.hold then
					spec.hold(player, prompt, t - last)
				end
				last = t
			end
		end)
		holding[player] = { prompt = prompt, tag = tag, thread = thread }
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, player)
		local h = holding[player]
		if h and h.prompt == prompt then
			task.cancel(h.thread)
			holding[player] = nil
			local spec = h.tag and holdHandlers[h.tag]
			if spec and spec.ended then
				spec.ended(player, prompt)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local h = holding[player]
		if h then
			task.cancel(h.thread)
			holding[player] = nil
		end
		limiter:forget(Comms.key(player))
	end)

	-- Remotes
	Net.event("CrewRequest").OnServerEvent:Connect(function(player, req)
		if allowed(player) then
			S.Crew.handleRequest(player, req)
		end
	end)
	Net.event("MissionRequest").OnServerEvent:Connect(function(player, req)
		if allowed(player) then
			S.Mission.handleRequest(player, req)
		end
	end)
	Net.event("KeypadSubmit").OnServerEvent:Connect(function(player, req)
		if allowed(player) and type(req) == "table" and type(req.code) == "string" and #req.code <= 8 then
			S.Security.onKeypadSubmit(player, req.targetId, req.code)
		end
	end)
	Net.event("ProfileRequest").OnServerEvent:Connect(function(player, req)
		if allowed(player) then
			S.Cosmetics.handleRequest(player, req)
		end
	end)
	Net.event("HideoutRequest").OnServerEvent:Connect(function(player, req)
		if allowed(player) then
			S.Hideout.handleRequest(player, req)
		end
	end)
	Net.event("DropCarry").OnServerEvent:Connect(function(player)
		if allowed(player) then
			S.Loot.drop(player, nil)
		end
	end)
	Net.event("SetSneak").OnServerEvent:Connect(function(player, on)
		if allowed(player, 0.5) then
			S.Movement.setSneak(player, on == true)
		end
	end)
	Net.event("SetSprint").OnServerEvent:Connect(function(player, on)
		if allowed(player, 0.5) then
			S.Movement.setSprint(player, on == true)
		end
	end)
	Net.func("GetBootstrap").OnServerInvoke = function(player)
		local profile = S.Data.waitFor(player, 10)
		local crew = S.Crew.ensure(player)
		return {
			cash = profile and profile.data.cash or 0,
			saveable = profile and profile.saveable or false,
			crew = S.Crew.snapshot(crew),
			routes = S.Mission.ctx.world.blueprint.Routes,
			museumName = "Aurora Exchange",
			buildTag = Config.BuildTag,
			securityLevel = S.Security.level(),
			worldEvents = S.WorldEvent.snapshot(),
			convoy = S.Convoy.snapshot(),
			weather = S.Environment.snapshot(),
		}
	end
end

return InteractionService
