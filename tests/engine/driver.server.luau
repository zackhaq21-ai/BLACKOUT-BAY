--!nonstrict
-- Native Studio scenario for Blackout Bay, built only into the engine-test place. Runs under
-- StudioTestService with args {glasshouse = true, count = N}. It positions characters and freezes guards to
-- isolate rules; prompt handlers, ledgers, payouts, raids and the car still run through the real services.
local StudioTest = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local args = StudioTest:GetTestArgs()
if type(args) ~= "table" or args.glasshouse ~= true then
	return
end

local function waitFor(predicate, timeout, message)
	local endAt = os.clock() + timeout
	repeat
		local ok, value = pcall(predicate)
		if ok and value then
			return value
		end
		task.wait(0.1)
	until os.clock() >= endAt
	error(message, 0)
end

local hook, lastStep
local ok, result = xpcall(function()
	hook = ServerStorage:WaitForChild("GlasshouseEngineHook", 60)
	assert(hook, "Engine hook missing")
	local control = ReplicatedStorage:WaitForChild("EngineControl", 10)
	waitFor(function()
		return #Players:GetPlayers() == args.count and hook:Invoke("ready")
	end, 60, "Expected " .. args.count .. " loaded players with profiles and crews")
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	local leader = list[1]
	local function step(name)
		lastStep = name
		print("GLASSHOUSE_ENGINE_STEP", name)
	end
	local function move(p, where)
		hook:Invoke("move", p, where)
		task.wait(0.35)
	end
	local function trigger(p, part, tag)
		local okTrigger, err = hook:Invoke("trigger", p, part, tag)
		assert(okTrigger, "Trigger failed: " .. tag .. " " .. tostring(err) .. " " .. HttpService:JSONEncode(hook:Invoke("diagnostic", p)))
		task.wait(0.3)
	end

	-- 1. Crew formation
	step("crew")
	for i = 2, #list do
		assert(hook:Invoke("join", list[i], leader), "Join by code failed for " .. list[i].Name)
	end
	local crew = hook:Invoke("crew", leader)
	assert(#crew.members == args.count, "Crew size mismatch")
	local unit = hook:Invoke("unit", leader)
	assert(unit, "Leader has no hideout unit")

	-- 2. Start the job from the board and go loud at the front
	step("startJob")
	move(leader, unit.board.Position + Vector3.new(0, 3, 4))
	assert(hook:Invoke("startJob", leader), "Start job failed")
	assert(hook:Invoke("jobActive", leader), "Job not active")
	hook:Invoke("freezeGuards", true)
	local world = hook:Invoke("world")
	step("frontSmash")
	move(leader, world.frontExit)
	trigger(leader, world.frontDoor, "FrontSmash")
	waitFor(function()
		return hook:Invoke("securityLevel") >= 2
	end, 5, "Front smash did not raise the alarm")
	assert(hook:Invoke("heat", leader) >= 1, "Smasher got no police heat")

	-- 3. Cut a stocked case and take the loot
	step("caseCut")
	local case
	for _, c in ipairs(world.cases) do
		if c.zone == "Hall" and c.glass:FindFirstChildOfClass("ProximityPrompt") then
			case = c
			break
		end
	end
	assert(case, "No stocked hall case")
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
	assert(#hook:Invoke("carried", leader) == 1, "Leader is not carrying the loot")

	-- 4. Leave the building (phase Escaping), roll out the car, drive with REAL client input
	step("drive")
	move(leader, world.frontExit + Vector3.new(0, 0, 30))
	move(leader, unit.vehicleSpawn.Position + Vector3.new(6, 2, 12))
	local car = hook:Invoke("spawnVehicle", leader, "Kestrel")
	assert(car, "Kestrel did not spawn")
	local seat = car:WaitForChild("DriverSeat")
	move(leader, seat.Position + Vector3.new(0, 4, 0))
	seat:Sit(leader.Character:FindFirstChildOfClass("Humanoid"))
	waitFor(function()
		return seat.Occupant ~= nil
	end, 5, "Driver never seated")
	local start = car.PrimaryPart.Position
	control:FireClient(leader, "Drive", seat)
	task.wait(2.5)
	local traveled = (car.PrimaryPart.Position - start).Magnitude
	control:FireClient(leader, "Stop")
	print("GLASSHOUSE_ENGINE_CAR", args.count, "travel", traveled)
	assert(traveled > 20, "Client drive input moved the car only " .. traveled .. " studs")
	waitFor(function()
		return seat.Occupant == nil
	end, 6, "Client could not dismount")
	task.wait(0.8)

	-- 5. Trunk stow / take, then deliver and close the job
	step("trunk")
	local trunk = car:FindFirstChild("Trunk")
	move(leader, trunk.Position + Vector3.new(0, 2, 4))
	trigger(leader, trunk, "Trunk")
	assert(#hook:Invoke("carried", leader) == 0, "Stow failed")
	trigger(leader, trunk, "Trunk")
	assert(#hook:Invoke("carried", leader) == 1, "Take from trunk failed")
	step("deliver")
	local stashBefore = hook:Invoke("stash", leader).stash
	move(leader, unit.deliveryTable.Position + Vector3.new(0, 3, 4))
	trigger(leader, unit.deliveryTable, "Deliver")
	assert(#hook:Invoke("carried", leader) == 0, "Delivery did not take the bag")
	hook:Invoke("closeJob", leader)
	waitFor(function()
		return not hook:Invoke("jobActive", leader)
	end, 5, "Job did not close")
	local stashAfter = waitFor(function()
		local s = hook:Invoke("stash", leader).stash
		return s > stashBefore and s or nil
	end, 8, "Payout never reached the stash")
	local profile = hook:Invoke("profile", leader)
	assert(profile.xp > 0 and profile.wins >= 1, "XP / win not credited")
	print("GLASSHOUSE_ENGINE_HEIST_SUCCESS", args.count, "stash", stashAfter, "xp", profile.xp)
	-- a second run can start immediately (free retry)
	move(leader, unit.board.Position + Vector3.new(0, 3, 4))
	assert(hook:Invoke("startJob", leader), "Retry start failed")
	hook:Invoke("closeJob", leader)

	-- 5b. Fake bag: looks like a Jewel, carried as such, worth nothing on delivery, never counted as job loot
	step("fake")
	assert(hook:Invoke("fake", leader, "Jewel"), "Fake bag did not mint")
	local carriedFake = hook:Invoke("carried", leader)
	assert(#carriedFake == 1 and carriedFake[1] == "Aurora Jewel", "Fake is not carried under its mimic label")
	local stashBeforeFake = hook:Invoke("stash", leader).stash
	move(leader, unit.board.Position + Vector3.new(0, 3, 4))
	assert(hook:Invoke("startJob", leader), "Start job (fake run) failed")
	move(leader, unit.deliveryTable.Position + Vector3.new(0, 3, 4))
	trigger(leader, unit.deliveryTable, "Deliver")
	assert(#hook:Invoke("carried", leader) == 0, "Fake was not consumed on delivery")
	hook:Invoke("closeJob", leader)
	waitFor(function()
		return not hook:Invoke("jobActive", leader)
	end, 5, "Fake run did not close")
	task.wait(1)
	assert(hook:Invoke("stash", leader).stash == stashBeforeFake, "A fake bag changed the stash")
	print("GLASSHOUSE_ENGINE_FAKE_OK", args.count)

	-- 6. Arrest and release
	step("jail")
	assert(hook:Invoke("arrest", leader), "Arrest failed")
	assert(hook:Invoke("release", leader), "Release failed")

	local raidResult = nil
	if args.count >= 2 then
		-- 7. Partner leaves, raids the leader's live pier: full stash exposed, bundles minted once, lock + cooldown
		step("raid")
		local raider = list[2]
		hook:Invoke("leave", raider)
		assert(hook:Invoke("crew", raider).id ~= crew.id, "Raider still in the crew")
		assert(hook:Invoke("raid", raider, leader.UserId), "Raid did not start")
		local rs = hook:Invoke("raidState", raider)
		assert(rs and rs.active and rs.safe, "Raid state missing")
		move(raider, rs.safe.Position + Vector3.new(0, 3, 4))
		trigger(raider, rs.safe, "RaidSafe")
		assert(hook:Invoke("crackNow", raider), "Cracking did not start")
		local cracked = waitFor(function()
			local st = hook:Invoke("raidState", raider)
			return st and st.cracked and st or nil
		end, 6, "Safe never cracked")
		assert(cracked.stolen == stashAfter, "Full exposure violated: stolen " .. tostring(cracked.stolen) .. " of " .. tostring(stashAfter))
		assert(hook:Invoke("stash", leader).stash == 0, "Owner stash not emptied")
		-- pick up every bundle once and deliver to the raider's own pier
		local bundleIds = {}
		for id in pairs(cracked.bundles) do
			table.insert(bundleIds, id)
		end
		table.sort(bundleIds)
		assert(#bundleIds >= 1, "No bundles minted")
		local raiderUnit = hook:Invoke("unit", raider)
		local delivered = 0
		for _, id in ipairs(bundleIds) do
			local visual = hook:Invoke("lootVisual", id)
			assert(visual, "Bundle visual missing " .. id)
			move(raider, visual.PrimaryPart.Position + Vector3.new(0, 2, 3))
			trigger(raider, visual.PrimaryPart, "LootPickup")
			assert(#hook:Invoke("carried", raider) == 1, "Raider could not pick up " .. id)
			move(raider, raiderUnit.deliveryTable.Position + Vector3.new(0, 3, 4))
			trigger(raider, raiderUnit.deliveryTable, "Deliver")
			delivered += 1
		end
		hook:Invoke("closeJob", raider)
		waitFor(function()
			return not hook:Invoke("jobActive", raider)
		end, 5, "Raid job did not close")
		local raiderStash = waitFor(function()
			local s = hook:Invoke("stash", raider).stash
			return s >= stashAfter and s or nil
		end, 8, "Raider stash did not receive the bundles")
		local report = waitFor(function()
			local st = hook:Invoke("stash", leader)
			return st.unread >= 1 and st.reports[1] or nil
		end, 8, "Owner got no raid report")
		assert(report.lost == stashAfter, "Report lost mismatch")
		-- cooldown: an immediate second raid on the same hideout must fail
		assert(not hook:Invoke("raid", raider, leader.UserId), "Second raid should be blocked by cooldown")
		raidResult = { stolen = cracked.stolen, bundles = #bundleIds, delivered = delivered, raiderStash = raiderStash }
		print("GLASSHOUSE_ENGINE_RAID_SUCCESS", args.count, "stolen", cracked.stolen, "bundles", #bundleIds)

		-- 7b. Recovery: the victim tracks the clues and takes back exactly what was stolen, no more, once
		step("recovery")
		assert(report.clues and #report.clues >= 1, "No clue trail on the victim's report")
		assert(hook:Invoke("recover", leader, report.raidId), "Recovery mission did not start")
		local rrs = hook:Invoke("raidState", leader)
		assert(rrs and rrs.active and rrs.safe, "Recovery raid state missing")
		move(leader, rrs.safe.Position + Vector3.new(0, 3, 4))
		trigger(leader, rrs.safe, "RaidSafe")
		assert(hook:Invoke("crackNow", leader), "Recovery cracking did not start")
		local rcracked = waitFor(function()
			local st = hook:Invoke("raidState", leader)
			return st and st.cracked and st or nil
		end, 6, "Recovery safe never cracked")
		assert(rcracked.stolen == stashAfter, "Recovery took " .. tostring(rcracked.stolen) .. ", expected exactly " .. tostring(stashAfter))
		assert(hook:Invoke("stash", raider).stash == raiderStash - stashAfter, "Raider stash not debited by exactly the stolen amount")
		local rIds = {}
		for id in pairs(rcracked.bundles) do
			table.insert(rIds, id)
		end
		table.sort(rIds)
		for _, id in ipairs(rIds) do
			local visual = hook:Invoke("lootVisual", id)
			assert(visual, "Recovery bundle visual missing " .. id)
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
			return hook:Invoke("stash", leader).stash == stashAfter
		end, 8, "Victim stash not restored to exactly the stolen amount")
		local victimReport = waitFor(function()
			local st = hook:Invoke("stash", leader)
			for _, rep in ipairs(st.reports) do
				if rep.raidId == report.raidId and (rep.recovered or 0) == stashAfter then
					return rep
				end
			end
			return nil
		end, 8, "Victim report not credited with the recovery")
		assert(not hook:Invoke("recover", leader, report.raidId), "A second recovery for the same raid must be refused")
		raidResult.recovered = victimReport.recovered
		print("GLASSHOUSE_ENGINE_RECOVERY_SUCCESS", args.count, "recovered", victimReport.recovered)

		-- 7c. Bounties (3+ players): the raider funds a bounty on the leader; a third player leaves the crew and
		-- collects it with an on-foot takedown; the raider (contributor) could not; a second claim is refused.
		if args.count >= 3 then
			step("bounty")
			local hunter = list[3]
			hook:Invoke("leave", hunter)
			assert(hook:Invoke("grantStash", raider, 1000), "Test grant failed")
			local hunterBefore = hook:Invoke("stash", hunter).stash
			local total = hook:Invoke("placeBounty", raider, leader.UserId, 400)
			assert(total == 400, "Bounty not placed: " .. tostring(total))
			waitFor(function()
				return (leader:GetAttribute("Bounty") or 0) == 400 and leader.Character and leader.Character.HumanoidRootPart:FindFirstChild("TakedownPrompt") ~= nil
			end, 6, "Takedown prompt missing on the target")
			move(leader, unit.spawn.Position + Vector3.new(4, 0, 0))
			-- contributor cannot claim
			move(raider, unit.spawn.Position + Vector3.new(4, 0, 3))
			hook:Invoke("trigger", raider, leader.Character.HumanoidRootPart, "Takedown")
			assert(hook:Invoke("bounty", leader) == 400, "Contributor managed to claim")
			move(hunter, unit.spawn.Position + Vector3.new(4, 0, -3))
			trigger(hunter, leader.Character.HumanoidRootPart, "Takedown")
			waitFor(function()
				return hook:Invoke("bounty", leader) == 0
			end, 5, "Bounty not cleared by the takedown")
			waitFor(function()
				return hook:Invoke("stash", hunter).stash == hunterBefore + 400
			end, 8, "Hunter not paid exactly the bounty")
			assert(not hook:Invoke("trigger", hunter, leader.Character.HumanoidRootPart, "Takedown") or hook:Invoke("stash", hunter).stash == hunterBefore + 400, "Second claim paid again")
			print("GLASSHOUSE_ENGINE_BOUNTY_SUCCESS", args.count)
		end

		-- 8. Disconnect: a carrier who leaves drops the bag where they stood
		step("disconnect")
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
	end
	return { ok = true, count = args.count, carDistance = traveled, stash = stashAfter, raid = raidResult }
end, debug.traceback)

if not ok then
	warn("GLASSHOUSE_ENGINE_FAILURE at step " .. tostring(lastStep) .. ": " .. tostring(result))
end
StudioTest:EndTest(if ok then result else { ok = false, error = tostring(result), step = lastStep, count = args.count })
