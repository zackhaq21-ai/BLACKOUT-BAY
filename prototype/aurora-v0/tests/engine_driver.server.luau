-- Injected only into an isolated Studio test document. Never part of the shipped place.
local StudioTest = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local args = StudioTest:GetTestArgs()
if type(args) ~= "table" or args.glasshouse ~= true then return end
local function waitFor(predicate, timeout, message)
	local endAt = os.clock() + timeout
	repeat
		if predicate() then return end
		task.wait(0.1)
	until os.clock() >= endAt
	error(message, 0)
end
local hook, lastInteraction
local ok, result = xpcall(function()
	hook = game.ServerStorage:WaitForChild("GlasshouseEngineHook", 20)
	assert(hook, "Server test hook missing")
	waitFor(function()
		if #Players:GetPlayers() ~= args.count then return false end
		for _, p in ipairs(Players:GetPlayers()) do
			if not p.Character or not p.Character:FindFirstChild("HumanoidRootPart") then return false end
		end
		return hook:Invoke("profilesReady")
	end, 45, "Expected loaded local test players")
	local list = Players:GetPlayers(); table.sort(list, function(a,b) return a.UserId < b.UserId end)
	local leader = list[1]
	local function state() return hook:Invoke("state") end
	local function world() return hook:Invoke("world") end
	local function member(p)
		local members = state().members
		return members[p.UserId] or members[tostring(p.UserId)]
	end
	local function interact(p, target, name, duration)
		lastInteraction = {player=p,target=target,name=name}
		local prompt = target:FindFirstChild(name)
		assert(prompt and prompt:IsA("ProximityPrompt"), "Missing prompt " .. name)
		hook:Invoke("move", p, target.Position + Vector3.new(0, 3, 5))
		task.wait(0.3)
		hook:Invoke("trigger", p, prompt)
		if hook:Invoke("job", p) == nil then print("GLASSHOUSE_ENGINE_CHANNEL_DIAG", game.HttpService:JSONEncode(hook:Invoke("diagnostic", p, target))) end
		waitFor(function() return hook:Invoke("job", p) ~= nil end, 2, "Channel did not start: " .. name .. " at " .. tostring(target.Position))
		waitFor(function() return hook:Invoke("job", p) == nil end, duration + 4, "Channel did not finish: " .. name)
		task.wait(0.2)
	end
	hook:Invoke("start")
	assert(state().status == "Active", "Start failed")
	hook:Invoke("freezePatrols")
	for _, p in ipairs(list) do
		interact(p, world().entrances.Service.part, "Enter", 1)
		assert(member(p) and member(p).entered, "Crew entry failed")
	end
	assert(state().needed == math.min(4, 1 + math.ceil(args.count/2)))
	if args.count == 2 then
		StudioTest:AddPlayers(1)
		waitFor(function() return #Players:GetPlayers() == 3 end, 30, "Late local client did not join")
		for _, p in ipairs(Players:GetPlayers()) do
			if not table.find(list, p) then assert(member(p) == nil, "Late joiner incorrectly entered active crew") end
		end
		print("GLASSHOUSE_ENGINE_LATE_JOIN_OK")
	end
	for i = 1, state().needed do
		interact(leader, world().nodes[i], "Sync signal", 3)
		assert(state().signals[i], "Signal did not count")
	end
	interact(leader, world().power, "Cut light grid", 4)
	assert(state().powerOff)
	interact(leader, world().vaults[state().vault], "Open quietly", 5)
	assert(state().vaultOpen)
	interact(leader, world().core, "Take core", 1.5)
	assert(state().carrier == leader.UserId)
	interact(leader, world().returnGate, "Leave gallery", 1)

	-- Test real client vehicle input -> server car simulation, rather than moving the car by test code.
	local car = world().cars[1]
	hook:Invoke("move", leader, car.seat.Position + Vector3.new(0, 3, 0))
	task.wait(0.3)
	car.seat:Sit(leader.Character:FindFirstChildOfClass("Humanoid"))
	waitFor(function() return car.seat.Occupant ~= nil end, 4, "Driver never seated")
	local initial = car.chassis.Position
	game.ReplicatedStorage.Glasshouse.EngineControl:FireClient(leader, "Drive", car.seat)
	task.wait(2)
	local traveled = (car.chassis.Position - initial).Magnitude
	game.ReplicatedStorage.Glasshouse.EngineControl:FireClient(leader, "Stop")
	print("GLASSHOUSE_ENGINE_CAR", args.count, "travel", traveled, "throttle", car.seat.ThrottleFloat)
	assert(traveled > 20, "Client drive input did not move car >20 studs")
	waitFor(function() return car.seat.Occupant == nil end, 5, "Client could not dismount car")
	task.wait(0.8) -- let the ordinary jump land before starting a stay-nearby channel
	for _, p in ipairs(list) do hook:Invoke("move", p, world().exits.Tunnel.Position + Vector3.new(0, 4, 5)) end
	interact(leader, world().exits.Tunnel, "Extract crew", 8)
	assert(state().status == "Success" and state().escapedCount == args.count, "Crew extraction failed")
	waitFor(function() return state().credited end, 2, "Result never credited")
	for _, p in ipairs(list) do assert(hook:Invoke("profile", p).wins == 1, "Win not credited") end
	print("GLASSHOUSE_ENGINE_QUIET_SUCCESS", args.count, state().result)

	-- Retry through the normal five-second cooldown; forced branch and recovery.
	task.wait(5.2)
	hook:Invoke("start"); hook:Invoke("freezePatrols")
	assert(state().status == "Active" and state().signalCount == 0)
	interact(leader, world().entrances.Exhibit.part, "Enter", 1)
	interact(leader, world().vaults[state().vault], "Force vault", 9)
	interact(leader, world().core, "Take core", 1.5)
	hook:Invoke("capture", leader)
	assert(member(leader).captured and state().core == "Dropped")
	interact(leader, world().recoveryPad, "Recover", 4)
	assert(not member(leader).captured and not member(leader).entered, "Recovery channel canceled or did not reset entry")
	interact(leader, world().entrances.Exhibit.part, "Enter", 1)
	interact(leader, world().core, "Take core", 1.5)
	interact(leader, world().exits.Tunnel, "Extract crew", 8)
	assert(state().status == "Success", "Forced/capture/recovery extraction failed")
	print("GLASSHOUSE_ENGINE_RECOVERY_SUCCESS", args.count)
	if args.count == 1 then
		task.wait(5.5)
		hook:Invoke("start"); hook:Invoke("freezePatrols")
		interact(leader, world().entrances.Service.part, "Enter", 1)
		interact(leader, world().curator, "Capture", 2)
		assert(state().curator == "Captured" and state().signalCount == 1, "Curator capture blocked")
		interact(leader, world().curator, "Release", 2)
		assert(state().curator == "Released", "Curator release blocked")
		interact(leader, world().vaults[state().vault], "Force vault", 9)
		interact(leader, world().core, "Take core", 1.5)
		interact(leader, world().exits.Canal, "Extract crew", 4)
		assert(state().status == "Success" and state().exit == "Canal", "Curator canal route failed")
		print("GLASSHOUSE_ENGINE_CURATOR_CANAL_SUCCESS")
	end
	if args.count > 1 then
		task.wait(5.5)
		hook:Invoke("start"); hook:Invoke("freezePatrols")
		local partner = list[2]
		interact(leader, world().entrances.Service.part, "Enter", 1)
		interact(partner, world().entrances.Service.part, "Enter", 1)
		interact(leader, world().vaults[state().vault], "Force vault", 9)
		interact(leader, world().core, "Take core", 1.5)
		local removedId = leader.UserId
		leader:Kick("Glasshouse isolated local disconnect test")
		waitFor(function() local m=state().members; return m[removedId] == nil and m[tostring(removedId)] == nil end, 10, "Departed carrier retained")
		assert(state().core == "Dropped" and world().core, "Disconnect lost core")
		local remaining = Players:GetPlayers()
		table.sort(remaining, function(a,b) return a.UserId < b.UserId end)
		local expectedRoles = {"Coordinator", "Signal specialist", "Courier", "Lookout", "Pathfinder"}
		for i, p in ipairs(remaining) do
			assert(member(p).role == (#remaining == 1 and "Solo / all tools" or expectedRoles[i]), "Role did not reassign")
		end
		interact(partner, world().core, "Take core", 1.5)
		interact(partner, world().exits.Tunnel, "Extract crew", 8)
		assert(state().status == "Success", "Partner could not finish after disconnect")
		print("GLASSHOUSE_ENGINE_DISCONNECT_SUCCESS", args.count)
	end
	return {ok = true, count = args.count, carDistance = traveled, quiet = true, forcedRecovery = true, disconnect = args.count > 1, lateJoin = args.count == 2}
end, debug.traceback)
if not ok then
	warn("GLASSHOUSE_ENGINE_FAILURE", result)
	if hook and lastInteraction and lastInteraction.target.Parent then
		print("GLASSHOUSE_ENGINE_END_DIAG", lastInteraction.name, game.HttpService:JSONEncode(hook:Invoke("diagnostic", lastInteraction.player,lastInteraction.target)))
	end
end
StudioTest:EndTest(ok and result or {ok = false, error = tostring(result), count = args.count})
