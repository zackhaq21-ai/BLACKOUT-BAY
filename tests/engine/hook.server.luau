--!nonstrict
-- Engine test hook. Built ONLY into build/BlackoutBay-EngineTest.rbxl (engine-test.project.json); never into the
-- shipped place. Exposes trusted server actions to the test driver through a BindableFunction. Positioning and
-- prompt dispatch go through the real services with their normal validation.
local StudioTest = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
if not RunService:IsStudio() then
	return
end
local args = StudioTest:GetTestArgs()
if type(args) ~= "table" or args.glasshouse ~= true then
	return
end
local server = game:GetService("ServerScriptService"):WaitForChild("Server")
while not server:GetAttribute("Ready") do
	task.wait(0.1)
end
local ctx = require(server.ServerContext).ctx
local S = ctx.services

local control = Instance.new("RemoteEvent")
control.Name = "EngineControl"
control.Parent = ReplicatedStorage

local function root(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function promptOn(part: Instance, tag: string): ProximityPrompt?
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d:GetAttribute("Tag") == tag then
			return d
		end
	end
	return nil
end

local hook = Instance.new("BindableFunction")
hook.Name = "GlasshouseEngineHook"
hook.OnInvoke = function(action, a, b, c)
	if action == "ready" then
		for _, p in ipairs(Players:GetPlayers()) do
			if not S.Data.get(p) or not S.Crew.crewOf(p) or not root(p) then
				return false
			end
		end
		return true
	elseif action == "move" then
		S.Movement.relocate(a, if typeof(b) == "CFrame" then b else CFrame.new(b))
		return true
	elseif action == "join" then
		local crew = S.Crew.crewOf(b)
		S.Crew.join(a, crew.code)
		return S.Crew.crewOf(a) == crew
	elseif action == "leave" then
		S.Crew.leave(a)
		return true
	elseif action == "crew" then
		local crew = S.Crew.crewOf(a)
		return crew and S.Crew.snapshot(crew) or nil
	elseif action == "startJob" then
		return S.Mission.startJob(a) ~= nil
	elseif action == "closeJob" then
		S.Mission.closeJobByPlayer(a)
		return true
	elseif action == "jobActive" then
		local crew = S.Crew.crewOf(a)
		return crew ~= nil and S.Mission.isJobActive(crew.id)
	elseif action == "trigger" then
		-- a = player, b = part (or prompt), c = tag
		local prompt = if typeof(b) == "Instance" and b:IsA("ProximityPrompt") then b else promptOn(b, c)
		if not prompt then
			return false, "no prompt " .. tostring(c)
		end
		return S.Interaction.dispatch(a, prompt)
	elseif action == "world" then
		local museum = ctx.world.museum
		return {
			frontDoor = museum.frontDoors[1],
			frontExit = museum.exits.front,
			dockRelease = museum.dockRelease,
			junctionBox = museum.junctionBox,
			cases = museum.cases,
			vaultDoor = museum.vaultDoor,
			corePedestal = museum.corePedestal.cframe,
			lootFolder = ctx.world.lootFolder,
			station = { cellDoor = ctx.world.island.station.cellDoor, releaseSwitch = ctx.world.island.station.releaseSwitch },
			substation = { cabinet = ctx.world.island.substation.cabinet, resetPanel = ctx.world.island.substation.resetPanel },
		}
	elseif action == "unit" then
		local crew = S.Crew.crewOf(a)
		local u = crew and crew.unit
		if not u then
			return nil
		end
		return { id = u.id, label = u.label, spawn = u.spawn, vehicleSpawn = u.vehicleSpawn, board = u.board, deliveryTable = u.deliveryTable, model = u.model }
	elseif action == "freezeGuards" then
		S.Security.setFrozen(a ~= false)
		return true
	elseif action == "securityLevel" then
		return S.Security.level()
	elseif action == "carried" then
		return S.Loot.carriedLabels(a)
	elseif action == "lootItems" then
		local out = {}
		for id, item in pairs(S.Loot.ledger.items) do
			out[id] = { kind = item.kind, state = item.state, holder = item.holder, value = item.value, weight = item.weight }
		end
		return out
	elseif action == "lootVisual" then
		return ctx.world.lootFolder:FindFirstChild("Loot_" .. a)
	elseif action == "drop" then
		return S.Loot.drop(a, "engine test")
	elseif action == "spawnVehicle" then
		local crew = S.Crew.crewOf(a)
		S.Vehicle.spawnCrewVehicle(crew, b or "Kestrel", crew.unit.vehicleSpawn, a)
		for _, rec in pairs(S.Vehicle.all()) do
			if rec.crewId == crew.id and rec.kind == (b or "Kestrel") then
				return rec.model
			end
		end
		return nil
	elseif action == "stash" then
		local rec = S.HideoutStore.load(a.UserId)
		return { stash = rec.stash, tier = rec.tier, reports = rec.reports, unread = rec.unread, raid = rec.raid }
	elseif action == "profile" then
		local p = S.Data.get(a)
		return p and p.data or nil
	elseif action == "raid" then
		S.Raid.startRaid(a, b)
		local crew = S.Crew.crewOf(a)
		return S.Raid.raidOfCrew(crew.id) ~= nil
	elseif action == "raidState" then
		local crew = S.Crew.crewOf(a)
		local raid = S.Raid.raidOfCrew(crew.id)
		if not raid then
			return nil
		end
		local state = S.Raid.unitState(raid.unitId)
		return { active = raid.active, cracked = raid.cracked, stolen = raid.stolen, retained = raid.retained, unitId = raid.unitId, safe = state and state.refs.safe or nil, pierDoor = state and state.refs.pierDoor or nil, breaker = state and state.refs.breaker or nil, unitModel = raid.unit.model, bundles = raid.bundles }
	elseif action == "takedown" then
		-- a = hunter, b = target root part: runs the server-timed hold exactly as PromptButtonHoldBegan/hold would
		local prompt = b:FindFirstChild("TakedownPrompt")
		if not prompt then
			return false, "no prompt"
		end
		S.Bounty.onTakedownHoldBegin(a, prompt)
		local t0 = os.clock()
		while os.clock() - t0 < 3 do
			task.wait(0.25)
			S.Bounty.onTakedownHold(a, prompt, 0.25)
		end
		return true
	elseif action == "grantStash" then
		return S.Hideout.depositStash(a, b, "engine test grant")
	elseif action == "placeBounty" then
		S.Bounty.place(a, b, c)
		return S.Bounty.totalOn(b)
	elseif action == "bounty" then
		return S.Bounty.totalOn(a.UserId)
	elseif action == "fake" then
		return S.Loot.mintFake(a, b or "Jewel")
	elseif action == "recover" then
		S.Raid.startRecovery(a, b)
		local crew = S.Crew.crewOf(a)
		return S.Raid.raidOfCrew(crew.id) ~= nil
	elseif action == "crackNow" then
		return S.Raid.testSetCrack(a, 0.999)
	elseif action == "arrest" then
		S.Police.arrest(a, "Engine test", "the test")
		return a:GetAttribute("Jailed") == true
	elseif action == "release" then
		S.Police.release(a, "engine test")
		return a:GetAttribute("Jailed") ~= true
	elseif action == "heat" then
		return S.Police.heatLevel(a)
	elseif action == "clearHeat" then
		S.Police.clearHeat(a, "engine test")
		return S.Police.heatLevel(a)
	elseif action == "sabotage" then
		return S.Blackout.testHold(a, "sabotage")
	elseif action == "gridReset" then
		return S.Blackout.testHold(a, "reset")
	elseif action == "worldEvent" then
		return S.WorldEvent.snapshot()
	elseif action == "convoyStart" then
		return S.Convoy.testStart(a)
	elseif action == "convoyState" then
		return S.Convoy.snapshot()
	elseif action == "convoyHalt" then
		S.Convoy.testHalt(a == true)
		return true
	elseif action == "convoyDoors" then
		for _, rec in pairs(S.Vehicle.all()) do
			if rec.kind == "Armored" then
				return rec.model:FindFirstChild("CargoDoors")
			end
		end
		return nil
	elseif action == "breach" then
		return S.Convoy.testHold(a)
	elseif action == "convoyCrates" then
		return S.Convoy.testCrates()
	elseif action == "convoyVehicles" then
		return S.Convoy.testVehicles()
	elseif action == "talk" then
		return S.Contact.talk(a, b)
	elseif action == "crewRename" then
		return S.Crew.rename(a, b)
	elseif action == "crewRecord" then
		local crew = S.Crew.crewOf(a)
		return crew and crew.record or nil
	elseif action == "museumVariant" then
		return S.Security.variant()
	elseif action == "restock" then
		S.Security.restock()
		return S.Security.variant()
	elseif action == "accomplishments" then
		return S.Accomplishment.list(a)
	elseif action == "grantAccomplishment" then
		return S.Accomplishment.grant(a, b)
	elseif action == "convoyStartVariant" then
		return S.Convoy.testStart(a, b)
	elseif action == "standing" then
		return S.Progression.rankInfo(a)
	elseif action == "onboarding" then
		return S.Onboarding.state(a)
	elseif action == "hideoutRequest" then
		S.Hideout.handleRequest(a, b)
		return true
	elseif action == "telemetry" then
		return S.Telemetry.counts()
	elseif action == "weather" then
		S.Environment.setState(a)
		return S.Environment.state()
	elseif action == "perfServer" then
		local Stats = game:GetService("Stats")
		local out = { players = #Players:GetPlayers() }
		for _, name in ipairs({ "InstanceCount", "PrimitivesCount", "MovingPrimitivesCount", "ContactsCount", "PhysicsStepTimeMs", "HeartbeatTimeMs", "DataSendKbps", "DataReceiveKbps" }) do
			local okProp, v = pcall(function()
				return (Stats :: any)[name]
			end)
			out[name] = if okProp and type(v) == "number" then math.floor(v * 100) / 100 else "n/a"
		end
		local okMem, mem = pcall(function()
			return Stats:GetTotalMemoryUsageMb()
		end)
		out.serverMemoryMb = if okMem then math.floor(mem) else "n/a"
		local emitters, lights = 0, 0
		for _, d in ipairs(ctx.world.root:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Enabled then
				emitters += 1
			elseif d:IsA("Light") and d.Enabled and d.Brightness > 0 then
				lights += 1
			end
		end
		out.activeEmitters = emitters
		out.litLights = lights
		out.worldParts = #ctx.world.root:GetDescendants()
		return out
	elseif action == "convoyEnd" then
		S.Convoy.testEnd()
		return S.Convoy.isActive() == false
	elseif action == "gridLights" then
		return S.Blackout.lightReport()
	elseif action == "gridState" then
		return { down = S.Blackout.isGridDown(), guardView = S.Security.guardVisionScale(), copView = S.Police.visionScale(), cameras = S.Security.camerasActive(), raidGrid = S.Raid.isGridDown() }
	elseif action == "diagnostic" then
		local r = root(a)
		local h = a.Character and a.Character:FindFirstChildOfClass("Humanoid")
		return { root = r and tostring(r.Position) or "missing", health = h and h.Health or -1, seat = h and h.SeatPart and h.SeatPart.Name or "none", carrying = S.Loot.carriedLabels(a), heat = S.Police.heatLevel(a), security = S.Security.level() }
	end
	return nil
end
hook.Parent = ServerStorage
print("GLASSHOUSE_ENGINE_HOOK_READY")
