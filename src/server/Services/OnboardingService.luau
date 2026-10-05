--!nonstrict
-- First-session guidance driven by observed play (move, board, job, loot, deliver). Returning players skip it.
-- The step is a monotonic profile op; nothing here can lock progression. Hints replace the idle objective
-- text and arrive as one short toast per step.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Onboarding = require(ReplicatedStorage.Shared.Core.Onboarding)
local Standing = require(ReplicatedStorage.Shared.Core.Standing)
local Comms = require(script.Parent.Comms)

local OnboardingService = {}
OnboardingService.ctx = nil :: any

local PC = Config.Progression
local states: { [Player]: any } = {}
local spawnPos: { [Player]: Vector3 } = {}
local toasted: { [Player]: { [number]: boolean } } = {}

local function stateOf(player: Player)
	local s = states[player]
	if s then
		return s
	end
	local profile = OnboardingService.ctx.services.Data.get(player)
	if not profile then
		return nil
	end
	s = Onboarding.fromStored(profile.data.onboarding)
	if not s.done and Standing.skipsOnboarding(PC, profile.data.stats.jobs) then
		s = Onboarding.complete(s)
	end
	states[player] = s
	return s
end

function OnboardingService.state(player: Player)
	return stateOf(player)
end

-- Idle objective shown when the player has no job: the step hint, or the standard idle line once done.
function OnboardingService.idleObjective(player: Player): (string, string)
	local s = stateOf(player)
	if not s then
		return Onboarding.hint(Onboarding.complete(Onboarding.new()))
	end
	return Onboarding.hint(s)
end

local function pushIdle(player: Player)
	local S = OnboardingService.ctx.services
	local crew = S.Crew.crewOf(player)
	if crew and S.Mission.isJobActive(crew.id) then
		return
	end
	local title, detail = OnboardingService.idleObjective(player)
	Net.event("MissionState"):FireClient(player, { jobActive = false, phase = "Idle", objective = title, objectiveDetail = detail })
end

function OnboardingService.advance(player: Player, event: string)
	local s = stateOf(player)
	if not s or s.done then
		return
	end
	local new, changed = Onboarding.advance(s, event)
	if not changed then
		return
	end
	states[player] = new
	local S = OnboardingService.ctx.services
	S.Data.applyOp(player, { kind = "Onboarding", step = new.step })
	S.Telemetry.track("onboarding_step", { step = Onboarding.stepName(new) })
	toasted[player] = toasted[player] or {}
	if not toasted[player][new.step] then
		toasted[player][new.step] = true
		local title, detail = Onboarding.hint(new)
		if new.done then
			Comms.toast(player, "First run done. Payouts land in your stash; bank or spend them from the board. Raids and bounties open as your Standing grows.", "good")
		else
			Comms.toast(player, title .. ": " .. detail, "info")
		end
	end
	pushIdle(player)
end

-- Hooks called by other services
function OnboardingService.onJobStarted(crew)
	for _, p in ipairs(crew.members) do
		OnboardingService.advance(p, "jobStarted")
	end
end

function OnboardingService.onJobClosed(player: Player, deliveredValue: number)
	if deliveredValue > 0 then
		OnboardingService.advance(player, "jobPaid")
	end
	pushIdle(player)
end

local function onLootEvent(kind: string, data)
	if not data.player then
		return
	end
	if kind == "pickup" then
		OnboardingService.advance(data.player, "lootPicked")
	elseif kind == "deliver" then
		OnboardingService.advance(data.player, "delivered")
	end
end

function OnboardingService.init(ctx)
	OnboardingService.ctx = ctx
end

function OnboardingService.start()
	local S = OnboardingService.ctx.services
	S.Loot.onEvent(onLootEvent)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			local root = char:WaitForChild("HumanoidRootPart", 10)
			if root then
				task.wait(1) -- after the pier placement
				spawnPos[player] = root.Position
			end
		end)
		task.spawn(function()
			S.Data.waitFor(player, 15)
			pushIdle(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		spawnPos[player] = nil
		toasted[player] = nil
	end)
	-- Movement step: cheap 1 s poll only for players still on the first step
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in ipairs(Players:GetPlayers()) do
				local s = states[p]
				if s and not s.done and s.step == 1 then
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					local origin = spawnPos[p]
					if root and origin and (root.Position - origin).Magnitude >= PC.Onboarding.MoveDistance then
						OnboardingService.advance(p, "moved")
					end
				end
			end
		end
	end)
end

return OnboardingService
