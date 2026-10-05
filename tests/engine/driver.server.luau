--!nonstrict
-- Native Studio master scenario for Blackout Bay, built only into the engine-test place. Runs under
-- StudioTestService with args {glasshouse = true, count = N}. It positions characters and freezes guards to
-- isolate rules; prompt handlers, ledgers, payouts, raids, world events and the cars run through the real services.
--
-- Structure: independent SECTIONS, each tagged with a SYSTEM. A failing section prints one line
--   GLASSHOUSE_ENGINE_FAIL system=<S> test=<T> expected=<E> actual=<A>
-- and the run continues with the next section unless the failed section is critical (crew, job start) or a
-- later section declares it as a dependency (then that section prints GLASSHOUSE_ENGINE_SKIP). Success markers
-- (GLASSHOUSE_ENGINE_*_SUCCESS) are unchanged. GLASSHOUSE_ENGINE_PERF lines carry objective measurements.
-- The run ends with GLASSHOUSE_ENGINE_SUMMARY passed=N failed=M skipped=K.
local StudioTest = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Config)
local args = StudioTest:GetTestArgs()
if type(args) ~= "table" or args.glasshouse ~= true then
	return
end

local function enc(v)
	local okJ, s = pcall(HttpService.JSONEncode, HttpService, v)
	return if okJ then s else tostring(v)
end

local function waitFor(predicate, timeout, message)
	local endAt = os.clock() + timeout
	repeat
		local okP, value = pcall(predicate)
		if okP and value then
			return value
		end
		task.wait(0.1)
	until os.clock() >= endAt
	error(message, 0)
end

-- Failure bookkeeping ---------------------------------------------------------------------------
local results = { passed = {}, failed = {}, skipped = {} }
local sectionOk = {}

local function fail(system, test, expected, actual)
	local line = string.format("GLASSHOUSE_ENGINE_FAIL system=%s test=%s expected=%s actual=%s", system, test, tostring(expected), tostring(actual))
	warn(line)
	table.insert(results.failed, { system = system, test = test, expected = tostring(expected), actual = tostring(actual) })
end

-- Expectation with explicit expected/actual. Raises so the section stops at its first broken invariant.
local function check(test, expected, actual, cond)
	if cond == nil then
		cond = expected == actual
	end
	if not cond then
		error("GLASSHOUSE_CHECK " .. enc({ test = test, expected = tostring(expected), actual = tostring(actual) }), 0)
	end
end

local function section(system, name, deps, fn)
	for _, d in ipairs(deps or {}) do
		if not sectionOk[d] then
			print("GLASSHOUSE_ENGINE_SKIP", system, name, "dependency", d)
			table.insert(results.skipped, { system = system, test = name, dependency = d })
			sectionOk[name] = false
			return false
		end
	end
	print("GLASSHOUSE_ENGINE_STEP", name)
	local okS, err = xpcall(fn, function(e)
		local msg = tostring(e)
		local payload = msg:match("GLASSHOUSE_CHECK (.*)$")
		if payload then
			local okD, decoded = pcall(HttpService.JSONDecode, HttpService, payload)
			if okD and type(decoded) == "table" then
				return decoded
			end
		end
		return { test = name, expected = "no error", actual = (msg .. " " .. tostring(debug.traceback(nil, 2))):gsub("\n", " | ") }
	end)
	if okS then
		sectionOk[name] = true
		table.insert(results.passed, { system = system, test = name })
		print("GLASSHOUSE_ENGINE_SECTION_OK", system, name)
	else
		sectionOk[name] = false
		fail(system, err.test or name, err.expected, err.actual)
	end
	return okS
end

-- Shared state between sections -----------------------------------------------------------------------
local S = {}
local hook, control, list, leader, unit, world, crew
local perfClient = {} -- player -> last sample
local tierAck = {}

local function move(p, where)
	hook:Invoke("move", p, where)
	task.wait(0.35)
end

local function trigger(p, part, tag)
	local okT, err = hook:Invoke("trigger", p, part, tag)
	check("trigger " .. tag, "accepted", tostring(err) .. " " .. enc(hook:Invoke("diagnostic", p)), okT == true)
	task.wait(0.3)
end

local function crewStash()
	local sum = 0
	for _, p in ipairs(list) do
		if p.Parent then
			sum += hook:Invoke("stash", p).stash
		end
	end
	return sum
end

-- Performance capture: server Stats plus each client's own frame timing, printed as one line per sample
local function perf(phase, tier)
	local server = hook:Invoke("perfServer")
	for _, p in ipairs(list) do
		if p.Parent then
			perfClient[p] = nil
			control:FireClient(p, "Perf", 2)
		end
	end
	local t0 = os.clock()
	repeat
		task.wait(0.1)
		local all = true
		for _, p in ipairs(list) do
			if p.Parent and not perfClient[p] then
				all = false
			end
		end
	until all or os.clock() - t0 > 6
	for _, p in ipairs(list) do
		local c = perfClient[p]
		if c then
			print(string.format("GLASSHOUSE_ENGINE_PERF phase=%s tier=%s players=%d client=%s fps=%s worstFrameMs=%s clientMemMb=%s sounds=%s emitters=%s fov=%s serverMemMb=%s instances=%s moving=%s physicsMs=%s heartbeatMs=%s sendKbps=%s recvKbps=%s worldParts=%s litLights=%s activeEmitters=%s",
				phase, tostring(tier or "default"), args.count, p.Name, tostring(c.fps), tostring(c.worstFrameMs), tostring(c.clientMemoryMb), tostring(c.playingSounds), tostring(c.enabledEmitters), tostring(c.fov),
				tostring(server.serverMemoryMb), tostring(server.InstanceCount), tostring(server.MovingPrimitivesCount), tostring(server.PhysicsStepTimeMs), tostring(server.HeartbeatTimeMs), tostring(server.DataSendKbps), tostring(server.DataReceiveKbps), tostring(server.worldParts), tostring(server.litLights), tostring(server.activeEmitters)))
		end
	end
	return server
end

local function setTier(p, name)
	tierAck[p] = nil
	control:FireClient(p, "SetTier", name)
	local t0 = os.clock()
	repeat
		task.wait(0.1)
	until tierAck[p] or os.clock() - t0 > 4
	return tierAck[p] or "no ack"
end

-- Setup -----------------------------------------------------------------------------------------------
local setupOk = section("setup", "setup", nil, function()
	hook = ServerStorage:WaitForChild("GlasshouseEngineHook", 60)
	check("engine hook", "present", hook and "present" or "missing", hook ~= nil)
	control = ReplicatedStorage:WaitForChild("EngineControl", 10)
	check("engine control remote", "present", control and "present" or "missing", control ~= nil)
	control.OnServerEvent:Connect(function(p, kind, value)
		if kind == "Perf" and type(value) == "table" then
			perfClient[p] = value
		elseif kind == "Tier" then
			tierAck[p] = tostring(value)
		end
	end)
	waitFor(function()
		return #Players:GetPlayers() == args.count and hook:Invoke("ready")
	end, 60, "Expected " .. args.count .. " loaded players with profiles and crews")
	list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	leader = list[1]
	world = hook:Invoke("world")
end)

-- CREW -------------------------------------------------------------------------------------------------
section("crew", "crew", { "setup" }, function()
	for i = 2, #list do
		check("join by code " .. list[i].Name, true, hook:Invoke("join", list[i], leader))
	end
	crew = hook:Invoke("crew", leader)
	check("crew size", args.count, #crew.members)
	unit = hook:Invoke("unit", leader)
	check("leader hideout unit", "assigned", unit and "assigned" or "none", unit ~= nil)
end)

-- HEIST: job, smash, case, drive, trunk --------------------------------------------------------------------
section("heist", "startJob", { "crew" }, function()
	move(leader, unit.board.Position + Vector3.new(0, 3, 4))
	check("start job", true, hook:Invoke("startJob", leader) ~= nil)
	check("job active", true, hook:Invoke("jobActive", leader))
	hook:Invoke("freezeGuards", true)
	perf("normal")
end)

section("heist", "frontSmash", { "startJob" }, function()
	move(leader, world.frontExit)
	trigger(leader, world.frontDoor, "FrontSmash")
	waitFor(function()
		return hook:Invoke("securityLevel") >= 2
	end, 5, "Front smash did not raise the alarm")
	check("smasher heat level", ">= 1", hook:Invoke("heat", leader), hook:Invoke("heat", leader) >= 1)
end)

section("heist", "caseCut", { "startJob" }, function()
	local case
	for _, c in ipairs(world.cases) do
		if c.zone == "Hall" and c.glass:FindFirstChildOfClass("ProximityPrompt") then
			case = c
			break
		end
	end
	check("stocked hall case", "present", case and "present" or "none", case ~= nil)
	move(leader, case.cframe.Position + Vector3.new(0, 0, 5))
	trigger(leader, case.glass, "CaseCut")
	local lootModel = waitFor(function()
		for _, m in ipairs(world.lootFolder:GetChildren()) do
			if m.PrimaryPart and (m.PrimaryPart.Position - case.cframe.Position).Magnitude < 3 and m.PrimaryPart:FindFirstChildOfClass("ProximityPrompt") then
				return m
			end
		end
		return nil
	end, 3, "Cut case did not expose a take prompt")
	trigger(leader, lootModel.PrimaryPart, "LootTake")
	check("leader carrying", 1, #hook:Invoke("carried", leader))
end)

section("vehicles", "drive", { "caseCut" }, function()
	move(leader, world.frontExit + Vector3.new(0, 0, 30))
	move(leader, unit.vehicleSpawn.Position + Vector3.new(6, 2, 12))
	local car = hook:Invoke("spawnVehicle", leader, "Kestrel")
	check("Kestrel spawned", "model", car and "model" or "nil", car ~= nil)
	S.car = car
	local seat = car:WaitForChild("DriverSeat")
	move(leader, seat.Position + Vector3.new(0, 4, 0))
	seat:Sit(leader.Character:FindFirstChildOfClass("Humanoid"))
	waitFor(function()
		return seat.Occupant ~= nil
	end, 5, "Driver never seated")
	local start = car.PrimaryPart.Position
	control:FireClient(leader, "Drive", seat)
	task.wait(1.2)
	-- headlights come on for everyone while driven (server light state)
	local head = car:FindFirstChild("Headlight")
	check("headlights while driven", "Neon", head and head.Material.Name or "none", head ~= nil and head.Material == Enum.Material.Neon)
	task.wait(1.3)
	local traveled = (car.PrimaryPart.Position - start).Magnitude
	control:FireClient(leader, "Stop")
	print("GLASSHOUSE_ENGINE_CAR", args.count, "travel", traveled)
	S.traveled = traveled
	check("client drive distance", "> 20 studs", traveled, traveled > 20)
	waitFor(function()
		return seat.Occupant == nil
	end, 6, "Client could not dismount")
	task.wait(0.8)
end)

section("heist", "trunk", { "drive" }, function()
	local trunk = S.car:FindFirstChild("Trunk")
	move(leader, trunk.Position + Vector3.new(0, 2, 4))
	trigger(leader, trunk, "Trunk")
	check("stow", 0, #hook:Invoke("carried", leader))
	trigger(leader, trunk, "Trunk")
	check("take from trunk", 1, #hook:Invoke("carried", leader))
end)

-- BLACKOUT ----------------------------------------------------------------------------------------------
local BC = Config.WorldEvents.Blackout
section("blackout", "blackout", { "startJob" }, function()
	local sub = world.substation
	local saboteur = list[#list]
	move(saboteur, sub.cabinet.Position + Vector3.new(0, 2, -4))
	hook:Invoke("trigger", saboteur, sub.cabinet, "GridSabotage")
	task.wait(0.3)
	check("forged trigger starts nothing", false, hook:Invoke("worldEvent").blackout.active)
	local heatBefore = hook:Invoke("heat", saboteur)
	check("sabotage hold cuts the grid", true, hook:Invoke("sabotage", saboteur))
	local ev = hook:Invoke("worldEvent").blackout
	check("blackout bounded", "active, 0 < secondsLeft <= " .. BC.DurationSeconds, enc(ev), ev.active and ev.secondsLeft > 0 and ev.secondsLeft <= BC.DurationSeconds)
	local lights = hook:Invoke("gridLights")
	check("grid lights dark", "dark == total > 0", enc(lights), lights.total > 0 and lights.dark == lights.total)
	check("emergency lights on", "> 0", lights.emergencyOn, lights.emergencyOn > 0)
	local gs = hook:Invoke("gridState")
	check("guard vision scaled", BC.GuardVisionScale, gs.guardView, math.abs(gs.guardView - BC.GuardVisionScale) < 0.01)
	check("cop vision scaled", BC.PoliceVisionScale, gs.copView, math.abs(gs.copView - BC.PoliceVisionScale) < 0.01)
	check("cameras dead", false, gs.cameras)
	check("pier shields down", true, gs.raidGrid)
	check("saboteur heat", "> " .. heatBefore, hook:Invoke("heat", saboteur), hook:Invoke("heat", saboteur) > heatBefore)
	check("second cut refused while active", false, hook:Invoke("sabotage", saboteur))
	perf("blackout")
	local resetter = list[math.max(1, #list - 1)]
	move(resetter, sub.resetPanel.Position + Vector3.new(0, 2, 4))
	check("reset hold restores power", true, hook:Invoke("gridReset", resetter))
	waitFor(function()
		local s = hook:Invoke("gridState")
		local l = hook:Invoke("gridLights")
		return not s.down and s.guardView == 1 and s.copView == 1 and s.cameras and not s.raidGrid and l.dark == 0 and l.emergencyOn == 0
	end, 5, "Grid restore left effects behind: " .. enc(hook:Invoke("gridState")))
	check("blackout inactive after reset", false, hook:Invoke("worldEvent").blackout.active)
	move(saboteur, sub.cabinet.Position + Vector3.new(0, 2, -4))
	check("cooldown refuses a re-cut", false, hook:Invoke("sabotage", saboteur))
	hook:Invoke("clearHeat", saboteur)
	for _, p in ipairs(list) do
		move(p, unit.spawn.Position + Vector3.new(0, 0, 4))
	end
	print("GLASSHOUSE_ENGINE_BLACKOUT_SUCCESS", args.count)
end)

-- WEATHER (server state + replicated; the look itself is visual QA) -------------------------------------
section("weather", "weather", { "setup" }, function()
	check("initial state known", true, hook:Invoke("weather", "Clear") == "Clear")
	for _, st in ipairs({ "Rain", "Storm", "Fog" }) do
		check("set " .. st, st, hook:Invoke("weather", st))
		task.wait(1)
		local gs = hook:Invoke("gridState")
		local expected = Config.Presentation.Weather.Vision[st]
		check("guard vision under " .. st, expected, gs.guardView, math.abs(gs.guardView - expected) < 0.01)
		check("cop vision under " .. st, expected, gs.copView, math.abs(gs.copView - expected) < 0.01)
		if st == "Storm" then
			perf("storm")
		elseif st == "Rain" then
			perf("rain")
		end
	end
	check("back to Clear", "Clear", hook:Invoke("weather", "Clear"))
	task.wait(0.5)
	check("vision restored", 1, hook:Invoke("gridState").guardView)
	print("GLASSHOUSE_ENGINE_WEATHER_SUCCESS", args.count)
end)

-- DELIVERY + RETRY -------------------------------------------------------------------------------------
section("heist", "deliver", { "trunk" }, function()
	local stashBefore = hook:Invoke("stash", leader).stash
	move(leader, unit.deliveryTable.Position + Vector3.new(0, 3, 4))
	trigger(leader, unit.deliveryTable, "Deliver")
	check("delivery took the bag", 0, #hook:Invoke("carried", leader))
	hook:Invoke("closeJob", leader)
	waitFor(function()
		return not hook:Invoke("jobActive", leader)
	end, 5, "Job did not close")
	S.stashAfter = waitFor(function()
		local s = hook:Invoke("stash", leader).stash
		return s > stashBefore and s or nil
	end, 8, "Payout never reached the stash")
	local profile = hook:Invoke("profile", leader)
	check("xp and win credited", "xp > 0, wins >= 1", enc({ xp = profile.xp, wins = profile.wins }), profile.xp > 0 and profile.wins >= 1)
	print("GLASSHOUSE_ENGINE_HEIST_SUCCESS", args.count, "stash", S.stashAfter, "xp", profile.xp)
	move(leader, unit.board.Position + Vector3.new(0, 3, 4))
	check("free retry start", true, hook:Invoke("startJob", leader) ~= nil)
	hook:Invoke("closeJob", leader)
end)

-- DECOYS -------------------------------------------------------------------------------------------------
section("decoys", "fake", { "deliver" }, function()
	check("fake minted", true, hook:Invoke("fake", leader, "Jewel"))
	local carriedFake = hook:Invoke("carried", leader)
	check("fake carried under mimic label", "Aurora Jewel", carriedFake[1], #carriedFake == 1 and carriedFake[1] == "Aurora Jewel")
	local stashBeforeFake = hook:Invoke("stash", leader).stash
	move(leader, unit.board.Position + Vector3.new(0, 3, 4))
	check("start fake run", true, hook:Invoke("startJob", leader) ~= nil)
	move(leader, unit.deliveryTable.Position + Vector3.new(0, 3, 4))
	trigger(leader, unit.deliveryTable, "Deliver")
	check("fake consumed on delivery", 0, #hook:Invoke("carried", leader))
	hook:Invoke("closeJob", leader)
	waitFor(function()
		return not hook:Invoke("jobActive", leader)
	end, 5, "Fake run did not close")
	task.wait(1)
	check("fake changed no stash", stashBeforeFake, hook:Invoke("stash", leader).stash)
	print("GLASSHOUSE_ENGINE_FAKE_OK", args.count)
end)

-- POLICE / JAIL ------------------------------------------------------------------------------------------
section("police", "jail", { "crew" }, function()
	check("arrest", true, hook:Invoke("arrest", leader))
	check("release", true, hook:Invoke("release", leader))
end)

-- CONVOY ---------------------------------------------------------------------------------------------------
local CC = Config.WorldEvents.Convoy
local function cargoTotal()
	local total = 0
	for _, v in ipairs(CC.CargoValues) do
		total += v
	end
	return total
end

section("convoy", "convoy", { "crew" }, function()
	check("convoy starts", true, hook:Invoke("convoyStart", 1))
	waitFor(function()
		return hook:Invoke("convoyVehicles") == 3
	end, 8, "Convoy vehicles did not spawn")
	local cs0 = hook:Invoke("convoyState")
	check("convoy state at start", "active, cargo secured, 0 crates", enc(cs0), cs0.active and cs0.cargo == "secured" and cs0.crates == 0)
	task.wait(4)
	local cs1 = hook:Invoke("convoyState")
	local travelled = math.abs(cs1.x - cs0.x) + math.abs(cs1.z - cs0.z)
	print("GLASSHOUSE_ENGINE_CONVOY_MOVE", args.count, "studs", travelled)
	check("convoy moved", "> 8 studs", travelled, travelled > 8)
	perf("convoy")
	local doors = hook:Invoke("convoyDoors")
	check("cargo doors", "present", doors and "present" or "nil", doors ~= nil)
	move(leader, doors.Position - doors.CFrame.LookVector * 3)
	check("breach refused while moving", false, hook:Invoke("breach", leader))
	hook:Invoke("convoyHalt", true)
	task.wait(2.5)
	move(leader, doors.Position - doors.CFrame.LookVector * 3)
	hook:Invoke("trigger", leader, doors, "ConvoyBreach")
	task.wait(0.3)
	check("forged trigger opens nothing", 0, #hook:Invoke("convoyCrates").ids)
	local heatBefore = hook:Invoke("heat", leader)
	check("breach hold opens the cargo", true, hook:Invoke("breach", leader))
	local crates = hook:Invoke("convoyCrates")
	check("crates minted", #CC.CargoValues .. " crates worth " .. cargoTotal(), enc(crates), #crates.ids == #CC.CargoValues and crates.total == cargoTotal())
	check("breacher heat", "> " .. heatBefore, hook:Invoke("heat", leader), hook:Invoke("heat", leader) > heatBefore)
	check("second breach refused", false, hook:Invoke("breach", leader))
	check("no duplicate crates", #CC.CargoValues, #hook:Invoke("convoyCrates").ids)
	local stashBeforeCrate = crewStash()
	local crateVisual = hook:Invoke("lootVisual", crates.ids[1])
	check("crate visual", "present", crateVisual and "present" or "nil", crateVisual ~= nil)
	move(leader, crateVisual.PrimaryPart.Position + Vector3.new(0, 2, 3))
	trigger(leader, crateVisual.PrimaryPart, "LootPickup")
	check("crate picked up", 1, #hook:Invoke("carried", leader))
	move(leader, unit.deliveryTable.Position + Vector3.new(0, 3, 4))
	trigger(leader, unit.deliveryTable, "Deliver")
	check("crate delivered", 0, #hook:Invoke("carried", leader))
	hook:Invoke("closeJob", leader)
	local crateValue = CC.CargoValues[1]
	waitFor(function()
		local gain = crewStash() - stashBeforeCrate
		return gain >= crateValue - #list and gain <= crateValue
	end, 10, "Crate payout wrong: " .. tostring(crewStash() - stashBeforeCrate) .. " expected " .. crateValue .. " (minus share rounding)")
	check("convoy ends", true, hook:Invoke("convoyEnd"))
	waitFor(function()
		return hook:Invoke("convoyVehicles") == 0
	end, 5, "Convoy vehicles left behind")
	check("loose crates recovered on cleanup", nil, hook:Invoke("lootVisual", crates.ids[2]))
	check("cooldown refuses a second convoy", false, hook:Invoke("convoyStart", 1))
	hook:Invoke("clearHeat", leader)
	print("GLASSHOUSE_ENGINE_CONVOY_SUCCESS", args.count)
end)

-- RAIDS / RECOVERY / BOUNTIES (2+ and 3+ players) ---------------------------------------------------------
local raider, report, raiderStash
if args.count >= 2 then
	section("raids", "raid", { "deliver" }, function()
		raider = list[2]
		hook:Invoke("leave", raider)
		check("raider left the crew", true, hook:Invoke("crew", raider).id ~= crew.id)
		check("raid starts", true, hook:Invoke("raid", raider, leader.UserId))
		local rs = hook:Invoke("raidState", raider)
		check("raid state", "active with safe", enc(rs), rs and rs.active and rs.safe)
		move(raider, rs.safe.Position + Vector3.new(0, 3, 4))
		trigger(raider, rs.safe, "RaidSafe")
		check("cracking starts", true, hook:Invoke("crackNow", raider))
		local cracked = waitFor(function()
			local st = hook:Invoke("raidState", raider)
			return st and st.cracked and st or nil
		end, 6, "Safe never cracked")
		check("full exposure", S.stashAfter, cracked.stolen)
		check("owner stash emptied", 0, hook:Invoke("stash", leader).stash)
		local bundleIds = {}
		for id in pairs(cracked.bundles) do
			table.insert(bundleIds, id)
		end
		table.sort(bundleIds)
		check("bundles minted", ">= 1", #bundleIds, #bundleIds >= 1)
		local raiderUnit = hook:Invoke("unit", raider)
		for _, id in ipairs(bundleIds) do
			local visual = hook:Invoke("lootVisual", id)
			check("bundle visual " .. id, "present", visual and "present" or "nil", visual ~= nil)
			move(raider, visual.PrimaryPart.Position + Vector3.new(0, 2, 3))
			trigger(raider, visual.PrimaryPart, "LootPickup")
			check("raider picked up " .. id, 1, #hook:Invoke("carried", raider))
			move(raider, raiderUnit.deliveryTable.Position + Vector3.new(0, 3, 4))
			trigger(raider, raiderUnit.deliveryTable, "Deliver")
		end
		hook:Invoke("closeJob", raider)
		waitFor(function()
			return not hook:Invoke("jobActive", raider)
		end, 5, "Raid job did not close")
		raiderStash = waitFor(function()
			local s = hook:Invoke("stash", raider).stash
			return s >= S.stashAfter and s or nil
		end, 8, "Raider stash did not receive the bundles")
		report = waitFor(function()
			local st = hook:Invoke("stash", leader)
			return st.unread >= 1 and st.reports[1] or nil
		end, 8, "Owner got no raid report")
		check("report lost", S.stashAfter, report.lost)
		check("second raid blocked by cooldown", false, hook:Invoke("raid", raider, leader.UserId))
		S.raid = { stolen = cracked.stolen, bundles = #bundleIds }
		print("GLASSHOUSE_ENGINE_RAID_SUCCESS", args.count, "stolen", cracked.stolen, "bundles", #bundleIds)
	end)

	section("raids", "recovery", { "raid" }, function()
		check("clue trail", ">= 1 clue", report.clues and #report.clues or 0, report.clues and #report.clues >= 1)
		check("recovery starts", true, hook:Invoke("recover", leader, report.raidId))
		local rrs = hook:Invoke("raidState", leader)
		check("recovery raid state", "active with safe", enc(rrs), rrs and rrs.active and rrs.safe)
		move(leader, rrs.safe.Position + Vector3.new(0, 3, 4))
		trigger(leader, rrs.safe, "RaidSafe")
		check("recovery cracking starts", true, hook:Invoke("crackNow", leader))
		local rcracked = waitFor(function()
			local st = hook:Invoke("raidState", leader)
			return st and st.cracked and st or nil
		end, 6, "Recovery safe never cracked")
		check("recovery takes exactly the stolen amount", S.stashAfter, rcracked.stolen)
		check("raider debited exactly", raiderStash - S.stashAfter, hook:Invoke("stash", raider).stash)
		local rIds = {}
		for id in pairs(rcracked.bundles) do
			table.insert(rIds, id)
		end
		table.sort(rIds)
		for _, id in ipairs(rIds) do
			local visual = hook:Invoke("lootVisual", id)
			check("recovery bundle visual " .. id, "present", visual and "present" or "nil", visual ~= nil)
			move(leader, visual.PrimaryPart.Position + Vector3.new(0, 2, 3))
			trigger(leader, visual.PrimaryPart, "LootPickup")
			move(leader, unit.deliveryTable.Position + Vector3.new(0, 3, 4))
			trigger(leader, unit.deliveryTable, "Deliver")
		end
		hook:Invoke("closeJob", leader)
		waitFor(function()
			return not hook:Invoke("jobActive", leader)
		end, 5, "Recovery job did not close")
		waitFor(function()
			return hook:Invoke("stash", leader).stash == S.stashAfter
		end, 8, "Victim stash not restored to exactly the stolen amount")
		local victimReport = waitFor(function()
			local st = hook:Invoke("stash", leader)
			for _, rep in ipairs(st.reports) do
				if rep.raidId == report.raidId and (rep.recovered or 0) == S.stashAfter then
					return rep
				end
			end
			return nil
		end, 8, "Victim report not credited with the recovery")
		check("second recovery refused", false, hook:Invoke("recover", leader, report.raidId))
		print("GLASSHOUSE_ENGINE_RECOVERY_SUCCESS", args.count, "recovered", victimReport.recovered)
	end)
end

local BCfg = Config.Bounty
if args.count >= 3 then
	section("bounties", "bounty", { "raid" }, function()
		local hunter = list[3]
		hook:Invoke("leave", hunter)
		check("test grant", true, hook:Invoke("grantStash", raider, 1000))
		local hunterBefore = hook:Invoke("stash", hunter).stash
		local total = hook:Invoke("placeBounty", raider, leader.UserId, 400)
		check("bounty placed", 400, total)
		waitFor(function()
			return (leader:GetAttribute("Bounty") or 0) == 400 and leader.Character and leader.Character.HumanoidRootPart:FindFirstChild("TakedownPrompt") ~= nil
		end, 6, "Takedown prompt missing on the target")
		local prompt = leader.Character.HumanoidRootPart:FindFirstChild("TakedownPrompt")
		check("takedown prompt range", BCfg.TakedownRange, prompt.MaxActivationDistance)
		move(leader, unit.spawn.Position + Vector3.new(4, 0, 0))
		move(raider, unit.spawn.Position + Vector3.new(4, 0, 3))
		hook:Invoke("takedown", raider, leader.Character.HumanoidRootPart)
		check("contributor cannot claim", 400, hook:Invoke("bounty", leader))
		hook:Invoke("trigger", hunter, leader.Character.HumanoidRootPart, "Takedown")
		check("forged trigger cannot claim", 400, hook:Invoke("bounty", leader))
		move(hunter, unit.spawn.Position + Vector3.new(4, 0, -(BCfg.TakedownRange + 2)))
		hook:Invoke("takedown", hunter, leader.Character.HumanoidRootPart)
		check("out of range cannot claim", 400, hook:Invoke("bounty", leader))
		move(hunter, unit.spawn.Position + Vector3.new(4, 0, -3))
		hook:Invoke("takedown", hunter, leader.Character.HumanoidRootPart)
		waitFor(function()
			return hook:Invoke("bounty", leader) == 0
		end, 5, "Bounty not cleared by the takedown")
		waitFor(function()
			return hook:Invoke("stash", hunter).stash == hunterBefore + 400
		end, 8, "Hunter not paid exactly the bounty")
		hook:Invoke("takedown", hunter, leader.Character.HumanoidRootPart)
		task.wait(0.5)
		check("second claim pays nothing", hunterBefore + 400, hook:Invoke("stash", hunter).stash)
		S.hunter = hunter
		print("GLASSHOUSE_ENGINE_BOUNTY_SUCCESS", args.count)
	end)

	-- CROSS-SYSTEM TORTURE: crew on a job + bounty + blackout + convoy + police + cargo + takedown + reset + cleanup
	section("cross", "torture", { "blackout", "convoy", "bounty" }, function()
		local hunter = S.hunter
		local stashStart = crewStash() + hook:Invoke("stash", raider).stash + hook:Invoke("stash", hunter).stash
		-- crew active
		move(leader, unit.board.Position + Vector3.new(0, 3, 4))
		check("torture job start", true, hook:Invoke("startJob", leader) ~= nil)
		-- bounty active on the leader (funded by the raider)
		check("torture bounty", 300, hook:Invoke("placeBounty", raider, leader.UserId, 300))
		-- wait out the blackout cooldown remainder if needed (bounded)
		local ok2 = waitFor(function()
			local ev = hook:Invoke("worldEvent").blackout
			return not ev.active
		end, 5, "blackout still active before torture")
		local _ = ok2
		-- blackout begins (saboteur is the leader: crew on a job)
		local sub = world.substation
		move(leader, sub.cabinet.Position + Vector3.new(0, 2, -4))
		local cut = hook:Invoke("sabotage", leader)
		if not cut then
			-- the earlier blackout's cooldown may still hold; wait for it (bounded by the config value)
			waitFor(function()
				move(leader, sub.cabinet.Position + Vector3.new(0, 2, -4))
				return hook:Invoke("sabotage", leader)
			end, BC.CooldownSeconds + 10, "Blackout could not start for the torture test within the cooldown")
		end
		check("torture blackout active", true, hook:Invoke("worldEvent").blackout.active)
		-- convoy enters the blackout (cooldown from the earlier convoy may hold: wait, bounded)
		local started = hook:Invoke("convoyStart", 2)
		if not started then
			waitFor(function()
				return hook:Invoke("convoyStart", 2)
			end, CC.CooldownSeconds + 10, "Convoy could not start for the torture test within the cooldown")
		end
		waitFor(function()
			return hook:Invoke("convoyVehicles") == 3
		end, 8, "Torture convoy vehicles did not spawn")
		perf("convoy+blackout")
		-- blackout halves the breach: the doors open faster; cargo stolen once
		hook:Invoke("convoyHalt", true)
		task.wait(2.5)
		local doors = hook:Invoke("convoyDoors")
		move(hunter, doors.Position - doors.CFrame.LookVector * 3)
		local t0 = os.clock()
		check("torture breach under blackout", true, hook:Invoke("breach", hunter))
		local breachSeconds = os.clock() - t0
		check("blackout shortens the breach", "< " .. CC.BreachSeconds .. " s", breachSeconds, breachSeconds < CC.BreachSeconds)
		local crates = hook:Invoke("convoyCrates")
		check("torture crates once", #CC.CargoValues, #crates.ids)
		-- police escalation registered through heat on the hunter
		check("hunter heat from the breach", "> 0", hook:Invoke("heat", hunter), hook:Invoke("heat", hunter) > 0)
		-- the leader picks up a crate, then is taken down by the hunter while carrying it: crate drops, bounty paid once
		local crateVisual = hook:Invoke("lootVisual", crates.ids[1])
		move(leader, crateVisual.PrimaryPart.Position + Vector3.new(0, 2, 3))
		trigger(leader, crateVisual.PrimaryPart, "LootPickup")
		check("leader carries a crate", 1, #hook:Invoke("carried", leader))
		local hunterBefore = hook:Invoke("stash", hunter).stash
		move(hunter, leader.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 3))
		hook:Invoke("takedown", hunter, leader.Character.HumanoidRootPart)
		waitFor(function()
			return hook:Invoke("bounty", leader) == 0
		end, 6, "Torture bounty not cleared")
		waitFor(function()
			return hook:Invoke("stash", hunter).stash == hunterBefore + 300
		end, 8, "Torture bounty not paid exactly once")
		check("takedown dropped the crate", 0, #hook:Invoke("carried", leader))
		-- blackout reset while the convoy is still active; vision returns to the weather factor only
		move(raider, sub.resetPanel.Position + Vector3.new(0, 2, 4))
		check("torture grid reset", true, hook:Invoke("gridReset", raider))
		waitFor(function()
			local gs = hook:Invoke("gridState")
			return not gs.down and gs.guardView == 1 and gs.copView == 1 and gs.cameras
		end, 5, "NPC vision or cameras did not restore after the torture reset")
		-- convoy cleanup with loose crates: crates recovered, vehicles gone, event inactive
		check("torture convoy end", true, hook:Invoke("convoyEnd"))
		waitFor(function()
			return hook:Invoke("convoyVehicles") == 0 and hook:Invoke("lootVisual", crates.ids[1]) == nil
		end, 6, "Torture cleanup left vehicles or crates")
		local snap = hook:Invoke("worldEvent")
		check("no stuck world events", "both inactive", enc({ blackout = snap.blackout.active, convoy = snap.convoy.active }), not snap.blackout.active and not snap.convoy.active)
		check("convoy state replicates inactive", false, hook:Invoke("convoyState").active)
		-- cooldowns intact
		check("blackout cooldown after torture", false, hook:Invoke("sabotage", leader))
		check("convoy cooldown after torture", false, hook:Invoke("convoyStart", 1))
		-- economy: only the bounty transfer moved money (raider -> hunter); no crate was delivered
		hook:Invoke("closeJob", leader)
		task.wait(1)
		local stashEnd = crewStash() + hook:Invoke("stash", raider).stash + hook:Invoke("stash", hunter).stash
		check("no money created or lost across the torture test", stashStart, stashEnd)
		-- client leftovers: no orphaned sounds or emitters beyond the pooled baseline (rain is off on Clear)
		local server = perf("after-torture")
		check("server emitters idle", "<= 1 active emitter", server.activeEmitters, type(server.activeEmitters) == "number" and server.activeEmitters <= 1)
		for _, p in ipairs(list) do
			local c = perfClient[p]
			if c then
				check("client emitters idle " .. p.Name, "<= 1 enabled emitter", c.enabledEmitters, c.enabledEmitters <= 1)
			end
		end
		hook:Invoke("clearHeat", leader)
		hook:Invoke("clearHeat", hunter)
		print("GLASSHOUSE_ENGINE_TORTURE_SUCCESS", args.count)
	end)
end

-- GRAPHICS TIERS: objective capture per tier on the leader (visual judgement is the human checklist) -----
section("performance", "tiers", { "setup" }, function()
	for _, tier in ipairs(Config.Presentation.Graphics.Tiers) do
		local ack = setTier(leader, tier)
		check("tier switch " .. tier, tier, ack)
		perf("normal", tier)
	end
	setTier(leader, "Auto (" .. "High" .. ")")
	print("GLASSHOUSE_ENGINE_TIERS_SUCCESS", args.count)
end)

-- DISCONNECT ---------------------------------------------------------------------------------------------
if args.count >= 2 then
	section("crew", "disconnect", { "raid" }, function()
		local ids = hook:Invoke("lootItems")
		local droppedBefore = 0
		for _, item in pairs(ids) do
			if item.state == "Dropped" then
				droppedBefore += 1
			end
		end
		raider:Kick("Blackout Bay engine disconnect test")
		waitFor(function()
			return Players:GetPlayerByUserId(raider.UserId) == nil
		end, 10, "Raider did not leave")
		print("GLASSHOUSE_ENGINE_DISCONNECT_OK", args.count, "droppedBefore", droppedBefore)
	end)
end

-- Summary ------------------------------------------------------------------------------------------------
local passed, failed, skipped = #results.passed, #results.failed, #results.skipped
print(string.format("GLASSHOUSE_ENGINE_SUMMARY count=%d passed=%d failed=%d skipped=%d", args.count, passed, failed, skipped))
for _, f in ipairs(results.failed) do
	print("GLASSHOUSE_ENGINE_FAILED_SECTION", f.system, f.test, "expected:", f.expected, "actual:", f.actual)
end
local allOk = setupOk and failed == 0
if allOk then
	print("GLASSHOUSE_ENGINE_RUN_PASSED", args.count)
else
	warn("GLASSHOUSE_ENGINE_RUN_FAILED " .. args.count .. " failed=" .. failed .. " skipped=" .. skipped)
end
StudioTest:EndTest({ ok = allOk, count = args.count, passed = passed, failed = failed, skipped = skipped, failures = results.failed, carDistance = S.traveled, stash = S.stashAfter, raid = S.raid })
