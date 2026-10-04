local Economy = require("./WorldEconomy")
local passed, failed, sequence = 0, 0, 0

local function eq(actual, expected, message)
	assert(actual == expected, (message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, fn)
	local ok, problem = pcall(fn)
	if ok then passed += 1; print("PASS", name)
	else failed += 1; print("FAIL", name, problem) end
end
local function new(world)
	return Economy.new({worldId = world or "coast-01", cycleStart = 1000, now = 1000,
		defenseCosts = {10, 20, 40, 80, 160, 320}, theftValidationGap = 2,
		players = {
			alice = {earned = 10000000, online = false, paidCosmetics = {goldCarPaint = true, laserAppearance = true}},
			bob = {earned = 3000000, online = true, paidCosmetics = {blueSuit = true}},
			cara = {earned = 3000000, online = true}, dan = {earned = 0, online = true},
		}, vehicles = {vanA = "alice", vanB = "bob"},
		loot = {
			{id = "stash-a", value = 80, location = {kind = "Stash", id = "alice"}},
			{id = "stash-b", value = 20, location = {kind = "Stash", id = "alice"}},
			{id = "bag-a", value = 120, location = {kind = "Carry", id = "alice"}},
			{id = "bag-b", value = 40, location = {kind = "Carry", id = "bob"}},
			{id = "road-bag", value = 10, location = {kind = "World", id = "road"}},
		},
	})
end
local function command(s, kind, values)
	sequence += 1
	local op = {id = "operation-" .. sequence, worldId = s.worldId, kind = kind, expectedRevision = s.revision, now = s.time, actor = "alice"}
	for k, v in pairs(values or {}) do op[k] = v end
	return op
end
local function commit(s, kind, values)
	local op = command(s, kind, values)
	local nextState, receipt, problem = Economy.apply(s, op)
	assert(nextState, problem)
	local valid, issue = Economy.audit(nextState); assert(valid, issue)
	return nextState, receipt, op
end
local function reject(s, kind, values, expected)
	local before = s.revision
	local nextState, _, problem = Economy.apply(s, command(s, kind, values))
	eq(nextState, nil, "request must reject")
	assert(string.find(problem, expected, 1, true), "unexpected rejection: " .. tostring(problem))
	eq(s.revision, before, "rejection must not mutate input")
	local valid, issue = Economy.audit(s); assert(valid, issue)
end
local function raid(s, attacker)
	return commit(s, "BeginRaid", {actor = attacker or "bob", owner = "alice", stashRevision = s.players.alice.stashRevision, accessDecision = "server-hideout-access"})
end
local function ownedCar(s)
	s = commit(s, "CompleteCarHeist", {actor = "alice", heistDecision = "server-car-heist-success"})
	return commit(s, "StoreCar", {actor = "alice"})
end
local function maintainTheft(s, theftId, actor, finishAt)
	while s.time < finishAt do
		s = commit(s, "ValidateCarTheft", {actor = actor, theftId = theftId, now = math.min(finishAt, s.time + 2), proximityDecision = "server-continuous-check"})
	end
	return s
end

test("initial money, loot, permanent cosmetics and two-seat car invariants", function()
	local s = new(); local ok, report = Economy.audit(s)
	assert(ok); eq(report.earned, 16000000); eq(report.physicalLoot, 270)
	eq(s.car.seats, 2); eq(s.car.heistCompleted, false); eq(s.car.location.kind, "Heist")
	eq(s.players.alice.paidCosmetics.goldCarPaint, true)
end)

test("2m plus 2m contributions debit earned wallets into 4m escrow", function()
	local original = new()
	local s = commit(original, "ContributeBounty", {actor = "bob", target = "alice", amount = 2000000, bountyRevision = 1})
	s = commit(s, "ContributeBounty", {actor = "cara", target = "alice", amount = 2000000, bountyRevision = 1})
	eq(s.bounties.alice.amount, 4000000); eq(s.players.bob.earned, 1000000); eq(s.players.cara.earned, 1000000)
	eq(original.players.bob.earned, 3000000, "input remains immutable")
	reject(s, "ContributeBounty", {actor = "bob", target = "alice", amount = 2000000, bountyRevision = 1}, "insufficient")
	reject(s, "ContributeBounty", {actor = "bob", target = "alice", amount = -1, bountyRevision = 1}, "insufficient")
end)

test("idempotent command replay and mismatched duplicate rejection", function()
	local s, receipt, op = commit(new(), "ContributeBounty", {actor = "bob", target = "alice", amount = 2000000, bountyRevision = 1})
	local replayState, replayReceipt, issue, replayed = Economy.apply(s, op)
	eq(issue, nil); eq(replayed, true); eq(replayState, s); eq(replayReceipt.revision, receipt.revision)
	eq(replayState.bounties.alice.amount, 2000000)
	op.amount = 1
	local bad, _, reason = Economy.apply(s, op); eq(bad, nil); assert(string.find(reason, "different payload", 1, true))
end)

test("optimistic revisions reject stale racing updates and wrong world", function()
	local s = new(); local op = command(s, "SetPresence", {actor = "alice", online = true})
	s = commit(s, "SetPresence", {actor = "bob", online = false})
	local updated, _, issue = Economy.apply(s, op); eq(updated, nil); eq(issue, "stale world revision")
	reject(s, "SetPresence", {actor = "alice", online = true, worldId = "other-world"}, "wrong world")
	reject(s, "SetPresence", {actor = "alice", online = true, now = 999}, "clock moved backwards")
end)

test("defeat freezes escrow; late contributions reject; payout occurs once", function()
	local s = commit(new(), "ContributeBounty", {actor = "bob", target = "alice", amount = 2000000, bountyRevision = 1})
	local result
	s, result = commit(s, "RecordDefeat", {actor = "dan", target = "alice", bountyRevision = 1, droppedLootIds = {"bag-a"}, eligibilityDecision = "server-eligible-defeat-01"})
	local claimId = result.details.claimId
	eq(s.loot["bag-a"].location.kind, "World"); eq(s.loot["bag-a"].location.id, claimId)
	reject(s, "ContributeBounty", {actor = "cara", target = "alice", amount = 10, bountyRevision = 1}, "frozen")
	reject(s, "ClaimBounty", {actor = "bob", claimId = claimId}, "wrong claimant")
	s = commit(s, "SetPresence", {actor = "alice", online = false})
	s = commit(s, "SetPresence", {actor = "dan", online = false})
	s = commit(s, "ClaimBounty", {actor = "dan", claimId = claimId})
	eq(s.players.dan.earned, 2000000); eq(s.bounties.alice.amount, 0); eq(s.bounties.alice.revision, 2)
	reject(s, "ClaimBounty", {actor = "dan", claimId = claimId}, "unavailable")
	reject(s, "ContributeBounty", {actor = "bob", target = "alice", amount = 10, bountyRevision = 1}, "stale bounty")
	s = commit(s, "ContributeBounty", {actor = "cara", target = "alice", amount = 10, bountyRevision = 2})
	eq(s.bounties.alice.amount, 10)
	reject(s, "RecordDefeat", {actor = "dan", target = "alice", bountyRevision = 2, droppedLootIds = {}, eligibilityDecision = "server-eligible-defeat-01"}, "already recorded")
end)

test("defeat requires adjudication and cannot drop another container's loot", function()
	local s = new()
	reject(s, "RecordDefeat", {actor = "dan", target = "alice", bountyRevision = 1, droppedLootIds = {}}, "missing server adjudication")
	reject(s, "RecordDefeat", {actor = "dan", target = "alice", bountyRevision = 1, droppedLootIds = {"stash-a"}, eligibilityDecision = "verified"}, "ownership changed")
	eq(s.bounties.alice, nil)
end)

test("physical split creates exact portions in separate vehicles; parent retires", function()
	local s = commit(new(), "SplitLoot", {lootId = "bag-a", parts = {
		{id = "portion-a", value = 70, location = {kind = "Vehicle", id = "vanA"}},
		{id = "portion-b", value = 50, location = {kind = "Vehicle", id = "vanB"}},
	}})
	eq(s.loot["bag-a"].retired, true); eq(s.loot["portion-a"].parentId, "bag-a")
	eq(s.loot["portion-b"].location.id, "vanB")
	reject(s, "MoveLoot", {from = {kind = "Carry", id = "alice"}, to = {kind = "Vehicle", id = "vanA"}, lootIds = {"bag-a"}}, "already consumed")
	s = commit(s, "MoveLoot", {actor = "bob", from = {kind = "Vehicle", id = "vanB"}, to = {kind = "Carry", id = "bob"}, lootIds = {"portion-b"}})
	eq(s.loot["portion-b"].location.kind, "Carry")
end)

test("invalid split never creates children; duplicate loot transfer rejects atomically", function()
	local s = new()
	reject(s, "SplitLoot", {lootId = "bag-a", parts = {
		{id = "bad-a", value = 80, location = {kind = "Carry", id = "alice"}},
		{id = "bad-b", value = 80, location = {kind = "Carry", id = "bob"}},
	}}, "conserve")
	eq(s.loot["bad-a"], nil); eq(s.loot["bag-a"].retired, false)
	reject(s, "MoveLoot", {from = {kind = "Carry", id = "alice"}, to = {kind = "Vehicle", id = "vanA"}, lootIds = {"bag-a", "bag-a"}}, "duplicate")
	reject(s, "MoveLoot", {from = {kind = "Carry", id = "alice"}, to = {kind = "Vehicle", id = "vanA"}, lootIds = {"bag-a", "missing"}}, "missing")
	eq(s.loot["bag-a"].location.kind, "Carry")
end)

test("taking unowned physical loot requires server transfer adjudication", function()
	local s = new()
	reject(s, "MoveLoot", {actor = "bob", from = {kind = "World", id = "road"}, to = {kind = "Carry", id = "bob"}, lootIds = {"road-bag"}}, "missing server adjudication")
	s = commit(s, "MoveLoot", {actor = "bob", from = {kind = "World", id = "road"}, to = {kind = "Carry", id = "bob"}, lootIds = {"road-bag"}, transferDecision = "verified-pickup"})
	eq(s.loot["road-bag"].location.id, "bob")
	reject(s, "MoveLoot", {actor = "cara", from = {kind = "World", id = "road"}, to = {kind = "Carry", id = "cara"}, lootIds = {"road-bag"}, transferDecision = "stale-pickup"}, "ownership changed")
end)

test("six shield and six laser tiers consume only earned balances", function()
	local s = new()
	for _, defense in ipairs({"Shield", "Laser"}) do
		for tier = 1, 6 do s = commit(s, "UpgradeDefense", {defense = defense}); eq(s.players.alice.defenses[defense], tier) end
		reject(s, "UpgradeDefense", {defense = defense}, "six-tier maximum")
	end
	eq(s.spentEarned, 1260); eq(s.players.alice.earned, 10000000 - 1260)
	eq(s.players.alice.paidCosmetics.laserAppearance, true)
	reject(s, "UpgradeDefense", {actor = "dan", defense = "Laser"}, "insufficient")
end)

test("offline raid snapshots defenses; reconnect cannot replace reserved stash", function()
	local s = commit(new(), "UpgradeDefense", {defense = "Shield"})
	local receipt; s, receipt = raid(s)
	eq(receipt.details.ownerWasOnline, false); eq(receipt.details.defenses.Shield, 1)
	reject(s, "BeginRaid", {actor = "cara", owner = "alice", stashRevision = s.players.alice.stashRevision, accessDecision = "verified"}, "unavailable")
	s = commit(s, "SetPresence", {online = true})
	reject(s, "UpgradeDefense", {defense = "Shield"}, "reserved")
	reject(s, "MoveLoot", {from = {kind = "Stash", id = "alice"}, to = {kind = "Carry", id = "alice"}, lootIds = {"stash-a"}}, "reserved")
	eq(s.raids[receipt.details.raidId].defenses.Shield, 1)
end)

test("raid transfers exactly supplied loot IDs; no implicit wipe", function()
	local s, receipt = raid(new()); local raidId = receipt.details.raidId
	s = commit(s, "ResolveRaid", {actor = "bob", raidId = raidId, outcome = "RaiderEscaped", stolenLootIds = {"stash-a"}, retainedLootIds = {}, outcomeDecision = "server-raid-result"})
	eq(s.loot["stash-a"].location.id, "bob"); eq(s.loot["stash-b"].location.kind, "Stash")
	eq(s.players.alice.earned, 10000000); eq(s.players.alice.paidCosmetics.goldCarPaint, true)
	eq(s.raidLogs.alice[1].attacker, "bob"); eq(s.raidLogs.alice[1].stolenValue, 80)
	reject(s, "ResolveRaid", {actor = "bob", raidId = raidId, outcome = "RaiderEscaped", stolenLootIds = {"stash-b"}, retainedLootIds = {}, outcomeDecision = "repeat"}, "unavailable")
end)

test("all supplied stash loot may be taken without invented protected fraction", function()
	local s, receipt = raid(new())
	s = commit(s, "ResolveRaid", {actor = "bob", raidId = receipt.details.raidId, outcome = "RaiderEscaped", stolenLootIds = {"stash-a", "stash-b"}, retainedLootIds = {}, outcomeDecision = "server-full-supplied-outcome"})
	eq(s.loot["stash-a"].location.id, "bob"); eq(s.loot["stash-b"].location.id, "bob")
	eq(s.raidLogs.alice[1].stolenValue, 100)
end)

test("defenses retain defeated intruder's explicit dropped earned loot", function()
	local s, receipt = raid(new())
	s = commit(s, "ResolveRaid", {actor = "bob", raidId = receipt.details.raidId, outcome = "DefensesWon", stolenLootIds = {}, retainedLootIds = {"bag-b"}, outcomeDecision = "server-trap-defeat"})
	eq(s.loot["bag-b"].location.kind, "Stash"); eq(s.loot["bag-b"].location.id, "alice")
	eq(s.raidLogs.alice[1].retainedValue, 40); eq(s.players.bob.paidCosmetics.blueSuit, true)
end)

test("invalid raid outcome leaves lease and every item intact", function()
	local s, receipt = raid(new()); local id = receipt.details.raidId
	reject(s, "ResolveRaid", {actor = "bob", raidId = id, outcome = "DefensesWon", stolenLootIds = {"stash-a"}, retainedLootIds = {}, outcomeDecision = "invalid"}, "cannot steal")
	reject(s, "ResolveRaid", {actor = "bob", raidId = id, outcome = "DefensesWon", stolenLootIds = {}, retainedLootIds = {"bag-b", "bag-a"}, outcomeDecision = "invalid"}, "ownership changed")
	eq(s.loot["bag-b"].location.id, "bob"); eq(s.activeRaids.alice, id); eq(#s.raidLogs.alice, 0)
	s = commit(s, "ResolveRaid", {actor = "bob", raidId = id, outcome = "Aborted", stolenLootIds = {}, retainedLootIds = {}, outcomeDecision = "server-abort"})
	eq(s.activeRaids.alice, nil); eq(s.loot["stash-a"].location.kind, "Stash")
end)

test("rare original car heist completes once per world cycle, owned individually", function()
	local s = ownedCar(new())
	eq(s.car.owner, "alice"); eq(s.car.seats, 2)
	reject(s, "CompleteCarHeist", {actor = "bob", heistDecision = "second-heist"}, "already completed")
	s = commit(s, "SetPresence", {actor = "alice", online = false}); eq(s.car.owner, "alice")
	local other = ownedCar(new("coast-02")); eq(other.car.owner, "alice"); assert(other.car.id ~= s.car.id)
end)

test("car break-in requires continuous validation and full 120 seconds", function()
	local s = ownedCar(new()); local receipt
	s, receipt = commit(s, "BeginCarTheft", {actor = "bob", carRevision = s.car.revision, proximityDecision = "near-car"})
	local id = receipt.details.theftId; local began = s.time
	reject(s, "CompleteCarTheft", {actor = "bob", theftId = id, proximityDecision = "near-car"}, "120-second")
	reject(s, "CompleteCarTheft", {actor = "bob", theftId = id, now = began + 120, proximityDecision = "near-car"}, "interrupted")
	s = maintainTheft(s, id, "bob", began + 118)
	reject(s, "CompleteCarTheft", {actor = "bob", theftId = id, now = began + 119, proximityDecision = "near-car"}, "120-second")
	s = commit(s, "CompleteCarTheft", {actor = "bob", theftId = id, now = began + 120, proximityDecision = "near-car"})
	eq(s.car.owner, "bob"); eq(s.car.heistCompleted, true)
	reject(s, "CompleteCarHeist", {actor = "cara", heistDecision = "try-original-again"}, "already completed")
	eq(s.players.alice.paidCosmetics.goldCarPaint, true)
end)

test("same car may be re-stolen without creating another original heist", function()
	local s = ownedCar(new()); local originalId = s.car.id
	for _, thief in ipairs({"bob", "cara", "alice"}) do
		if not s.players[thief].online then s = commit(s, "SetPresence", {actor = thief, online = true}) end
		local receipt; s, receipt = commit(s, "BeginCarTheft", {actor = thief, carRevision = s.car.revision, proximityDecision = "server-near"})
		s = maintainTheft(s, receipt.details.theftId, thief, s.time + 120)
		s = commit(s, "CompleteCarTheft", {actor = thief, theftId = receipt.details.theftId, proximityDecision = "server-near"})
		eq(s.car.id, originalId); eq(s.car.owner, thief); eq(s.car.heistCompleted, true)
		s = commit(s, "StoreCar", {actor = thief})
	end
end)

test("simultaneous thieves cannot both win; drive-away invalidates theft", function()
	local s = ownedCar(new()); local bob, cara
	s, bob = commit(s, "BeginCarTheft", {actor = "bob", carRevision = s.car.revision, proximityDecision = "near"})
	s, cara = commit(s, "BeginCarTheft", {actor = "cara", carRevision = s.car.revision, proximityDecision = "near"})
	for _ = 1, 60 do
		s = commit(s, "ValidateCarTheft", {actor = "bob", theftId = bob.details.theftId, now = s.time + 2, proximityDecision = "near"})
		s = commit(s, "ValidateCarTheft", {actor = "cara", theftId = cara.details.theftId, proximityDecision = "near"})
	end
	s = commit(s, "CompleteCarTheft", {actor = "bob", theftId = bob.details.theftId, proximityDecision = "near"})
	reject(s, "CompleteCarTheft", {actor = "cara", theftId = cara.details.theftId, proximityDecision = "near"}, "changed during theft")
	s = commit(s, "StoreCar", {actor = "bob"})
	s = commit(s, "SetPresence", {actor = "alice", online = true})
	local nextTheft; s, nextTheft = commit(s, "BeginCarTheft", {actor = "alice", carRevision = s.car.revision, proximityDecision = "near"})
	s = commit(s, "DriveCar", {actor = "bob"})
	reject(s, "ValidateCarTheft", {actor = "alice", theftId = nextTheft.details.theftId, proximityDecision = "near"}, "changed during theft")
end)

test("weekly reset revokes owner, expires theft, returns same car and reopens once", function()
	local s = ownedCar(new()); local originalId = s.car.id; local receipt
	s, receipt = commit(s, "BeginCarTheft", {actor = "bob", carRevision = s.car.revision, proximityDecision = "near"})
	local expires = s.car.cycleEnd
	reject(s, "ResetCarCycle", {now = expires - 1}, "not due")
	reject(s, "CompleteCarTheft", {actor = "bob", theftId = receipt.details.theftId, now = expires, proximityDecision = "near"}, "reset required")
	s = commit(s, "ResetCarCycle", {now = expires})
	eq(s.car.owner, nil); eq(s.car.id, originalId); eq(s.car.location.kind, "Heist"); eq(s.car.heistCompleted, false)
	eq(s.car.cycle, 2); eq(s.carThefts[receipt.details.theftId].status, "Expired")
	eq(s.players.alice.paidCosmetics.goldCarPaint, true)
	reject(s, "ResetCarCycle", {}, "not due")
	s = commit(s, "CompleteCarHeist", {actor = "cara", heistDecision = "new-week-heist"})
	eq(s.car.owner, "cara"); eq(s.car.id, originalId)
end)

test("server downtime skips elapsed cycles without accumulating rare cars", function()
	local s = ownedCar(new()); local originalId = s.car.id
	s = commit(s, "ResetCarCycle", {now = s.car.cycleEnd + 3 * Economy.WEEK_SECONDS + 10})
	eq(s.car.cycle, 5); eq(s.car.id, originalId); eq(s.car.owner, nil)
	assert(s.car.cycleEnd > s.time); eq(s.car.cycleEnd - s.car.cycleStart, Economy.WEEK_SECONDS)
end)

test("thief disconnect interrupts break-in; personal owner remains unchanged", function()
	local s = ownedCar(new()); local receipt
	s, receipt = commit(s, "BeginCarTheft", {actor = "bob", carRevision = s.car.revision, proximityDecision = "near"})
	s = commit(s, "SetPresence", {actor = "bob", online = false})
	eq(s.carThefts[receipt.details.theftId].status, "Interrupted"); eq(s.car.owner, "alice")
	reject(s, "BeginCarTheft", {actor = "bob", carRevision = s.car.revision, proximityDecision = "near"}, "disconnected")
	s = commit(s, "SetPresence", {actor = "bob", online = true})
	reject(s, "ValidateCarTheft", {actor = "bob", theftId = receipt.details.theftId, proximityDecision = "near"}, "invalid theft")
	s = commit(s, "BeginCarTheft", {actor = "bob", carRevision = s.car.revision, proximityDecision = "near"})
	eq(s.car.owner, "alice")
end)

test("stolen-loot recovery transfers the exact original ID without duplication", function()
	local s, receipt = raid(new())
	s = commit(s, "ResolveRaid", {actor = "bob", raidId = receipt.details.raidId, outcome = "RaiderEscaped", stolenLootIds = {"stash-a"}, retainedLootIds = {}, outcomeDecision = "server-result"})
	s = commit(s, "MoveLoot", {actor = "alice", from = {kind = "Carry", id = "bob"}, to = {kind = "Stash", id = "alice"}, lootIds = {"stash-a"}, transferDecision = "server-recovery-intercept"})
	eq(s.loot["stash-a"].id, "stash-a"); eq(s.loot["stash-a"].location.id, "alice")
	local valid, report = Economy.audit(s); assert(valid); eq(report.physicalLoot, 270)
end)

test("owner return log is bounded and contains each retained recent result", function()
	local s = new()
	for _ = 1, 65 do
		local receipt; s, receipt = raid(s)
		s = commit(s, "ResolveRaid", {actor = "bob", raidId = receipt.details.raidId, outcome = "Aborted", stolenLootIds = {}, retainedLootIds = {}, outcomeDecision = "server-abort"})
	end
	eq(#s.raidLogs.alice, 64); eq(s.activeRaids.alice, nil)
	for _, entry in ipairs(s.raidLogs.alice) do eq(entry.attacker, "bob"); eq(entry.outcome, "Aborted") end
end)

test("audit detects lost paid cosmetics and currency/loot duplication", function()
	local s = new(); s.players.alice.paidCosmetics.goldCarPaint = nil
	local ok, reason = Economy.audit(s); eq(ok, false); eq(reason, "paid cosmetics changed")
	s = new(); s.players.bob.earned += 1
	ok, reason = Economy.audit(s); eq(ok, false); eq(reason, "earned currency conservation failed")
	s = new(); s.loot["bag-a"].value += 1
	ok, reason = Economy.audit(s); eq(ok, false); eq(reason, "physical loot conservation failed")
end)

test("100 alternating physical transfers conserve loot and reject stale pickup replay", function()
	local s = new(); local from = {kind = "Carry", id = "alice"}; local to = {kind = "Vehicle", id = "vanA"}
	for i = 1, 100 do
		local receipt, op; s, receipt, op = commit(s, "MoveLoot", {from = from, to = to, lootIds = {"bag-a"}})
		local replay, sameReceipt, issue, replayed = Economy.apply(s, op)
		eq(replay, s); eq(issue, nil); eq(replayed, true); eq(sameReceipt.revision, receipt.revision)
		from, to = to, from
	end
	local ok, report = Economy.audit(s); assert(ok); eq(report.physicalLoot, 270); eq(report.earned, 16000000)
end)

print(string.format("WORLD_ECONOMY_TESTS: %d passed, %d failed", passed, failed))
assert(failed == 0, "experimental economy tests failed")
