-- EXPERIMENTAL: pure, single-authority ledger. No Roblox services or live integration.
-- Commands are validated SERVER domain events, never raw client RemoteEvent payloads.
local Economy = {}
local WEEK = 7 * 24 * 60 * 60
local MAX_INTEGER = 9007199254740991

local function need(condition, message)
	if not condition then error(message, 0) end
end
local function integer(value, minimum)
	return type(value) == "number" and value == value and value % 1 == 0 and value >= (minimum or 0) and value <= MAX_INTEGER
end
local function key(value)
	return type(value) == "string" and #value > 0 and #value <= 160
end
local function clone(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = clone(v) end
	return out
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function player(s, id)
	need(key(id) and s.players[id] ~= nil, "unknown player")
	return s.players[id]
end
local function location(s, value)
	need(type(value) == "table" and key(value.id), "invalid container")
	need(value.kind == "Carry" or value.kind == "Stash" or value.kind == "Vehicle" or value.kind == "World", "invalid container kind")
	if value.kind == "Carry" or value.kind == "Stash" then player(s, value.id) end
	if value.kind == "Vehicle" then need(s.vehicles[value.id] ~= nil, "unknown vehicle") end
	return {kind = value.kind, id = value.id}
end
local function sameLocation(a, b)
	return a.kind == b.kind and a.id == b.id
end
local function unlocked(s, loc)
	if loc.kind == "Stash" then need(s.activeRaids[loc.id] == nil, "stash reserved by raid") end
end
local function bumpStash(s, loc)
	if loc.kind == "Stash" then s.players[loc.id].stashRevision += 1 end
end
local function ownedContainer(s, actor, loc)
	return ((loc.kind == "Carry" or loc.kind == "Stash") and loc.id == actor)
		or (loc.kind == "Vehicle" and s.vehicles[loc.id].owner == actor)
end
local function distinctList(values, name)
	need(type(values) == "table", name .. " must be an array")
	local seen, count = {}, 0
	for i, id in pairs(values) do
		need(integer(i, 1) and i <= #values and key(id) and not seen[id], "invalid or duplicate " .. name)
		seen[id] = true; count += 1
	end
	need(count == #values, "sparse " .. name)
	return seen
end
local function lootAt(s, id, loc)
	local item = s.loot[id]
	need(item ~= nil and not item.retired, "loot missing or already consumed")
	need(sameLocation(item.location, loc), "loot ownership changed")
	return item
end
local function evidence(op, field)
	-- The game server must create this identifier AFTER validating physics/eligibility.
	-- It is an audit reference, not an authentication token or cryptographic proof.
	need(key(op[field]), "missing server adjudication: " .. field)
end
local function currentCar(s, now)
	need(now < s.car.cycleEnd, "weekly reset required")
	return s.car
end
local function validTheft(s, op)
	local car = currentCar(s, op.now)
	local theft = s.carThefts[op.theftId]
	need(theft ~= nil and theft.status == "Active" and theft.actor == op.actor, "invalid theft")
	need(player(s, op.actor).online, "thief disconnected")
	need(theft.cycle == car.cycle and theft.carRevision == car.revision and theft.owner == car.owner, "car changed during theft")
	need(car.location.kind == "Stash" and car.location.id == theft.owner, "car left hideout")
	need(op.now - theft.validatedThrough <= s.policy.theftValidationGap, "theft validation interrupted")
	return theft, car
end

local function audit(s)
	need(type(s) == "table" and s.version == 1 and key(s.worldId), "invalid state")
	need(integer(s.revision) and integer(s.time), "invalid revision or clock")
	local money = s.spentEarned
	need(integer(money), "invalid earned sink")
	for id, p in pairs(s.players) do
		need(key(id) and integer(p.earned) and integer(p.stashRevision), "invalid profile")
		need(same(p.paidCosmetics, s.paidBaseline[id]), "paid cosmetics changed")
		need(type(p.online) == "boolean", "invalid presence")
		for _, kind in ipairs({"Shield", "Laser"}) do need(integer(p.defenses[kind]) and p.defenses[kind] <= 6, "invalid defense tier") end
		money += p.earned
	end
	for target, bounty in pairs(s.bounties) do
		player(s, target); need(integer(bounty.amount) and integer(bounty.revision, 1), "invalid bounty")
		local contributed = 0
		for id, amount in pairs(bounty.contributions) do player(s, id); need(integer(amount, 1), "invalid contribution"); contributed += amount end
		need(contributed == bounty.amount, "escrow contributions mismatch")
		if bounty.claimId then
			local claim = s.defeats[bounty.claimId]
			need(claim and claim.status == "Pending" and claim.target == target and claim.amount == bounty.amount, "invalid escrow reservation")
		end
		money += bounty.amount
	end
	need(integer(money) and money == s.issuedEarned, "earned currency conservation failed")
	local lootValue = 0
	for id, item in pairs(s.loot) do
		need(key(id) and item.id == id and integer(item.value, 1), "invalid loot")
		if not item.retired then location(s, item.location); lootValue += item.value end
	end
	need(integer(lootValue) and lootValue == s.issuedLoot, "physical loot conservation failed")
	for owner, raidId in pairs(s.activeRaids) do
		local raid = s.raids[raidId]
		need(raid and raid.owner == owner and raid.status == "Active", "invalid raid reservation")
		need(player(s, owner).stashRevision == raid.stashRevision, "raid snapshot changed")
	end
	local car = s.car
	need(car.id == s.worldId .. ":rare-car" and car.seats == 2 and car.fastestCar == true, "invalid unique car")
	need(integer(car.cycle, 1) and integer(car.revision) and car.cycleEnd - car.cycleStart == WEEK, "invalid car cycle")
	need(car.heistCompleted == (car.owner ~= nil), "invalid original heist state")
	if car.owner then
		player(s, car.owner)
		need((car.location.kind == "Stash" or car.location.kind == "Driven") and car.location.id == car.owner, "car location/owner mismatch")
	else need(car.location.kind == "Heist" and car.location.id == s.carOrigin, "car missing from original heist") end
	return {earned = money, physicalLoot = lootValue, revision = s.revision}
end

function Economy.audit(s)
	local ok, value = pcall(audit, s)
	if not ok then return false, value end
	return true, value
end

-- Explicit initial balances/loot represent already earned assets imported by a server.
-- Defense prices are supplied policy, not accepted game-balance claims.
function Economy.new(seed)
	need(type(seed) == "table" and key(seed.worldId), "worldId required")
	need(integer(seed.now) and integer(seed.cycleStart) and seed.now >= seed.cycleStart and seed.now < seed.cycleStart + WEEK, "invalid initial cycle")
	need(type(seed.defenseCosts) == "table" and #seed.defenseCosts == 6, "six supplied defense costs required")
	for _, cost in ipairs(seed.defenseCosts) do need(integer(cost, 1), "invalid defense cost") end
	local gap = seed.theftValidationGap or 2
	need(integer(gap, 1) and gap <= 10, "invalid theft validation interval")
	local s = {
		version = 1, worldId = seed.worldId, revision = 0, time = seed.now,
		players = {}, paidBaseline = {}, vehicles = {}, loot = {}, bounties = {}, defeats = {}, defeatDecisions = {},
		raids = {}, activeRaids = {}, raidLogs = {}, carThefts = {}, operations = {},
		issuedEarned = 0, issuedLoot = 0, spentEarned = 0,
		policy = {defenseCosts = clone(seed.defenseCosts), theftValidationGap = gap, raidLogLimit = 64},
		carOrigin = seed.carOrigin or "original-car-heist",
	}
	need(key(s.carOrigin), "invalid car origin")
	for id, p in pairs(seed.players or {}) do
		need(key(id) and integer(p.earned), "invalid initial player")
		local cosmetics = {}
		for cosmetic, owned in pairs(p.paidCosmetics or {}) do need(key(cosmetic) and owned == true, "invalid cosmetic entitlement"); cosmetics[cosmetic] = true end
		s.players[id] = {earned = p.earned, online = p.online == true, paidCosmetics = cosmetics, stashRevision = 0, defenses = {Shield = 0, Laser = 0}}
		s.paidBaseline[id] = clone(cosmetics); s.raidLogs[id] = {}; s.issuedEarned += p.earned
	end
	for id, owner in pairs(seed.vehicles or {}) do
		need(key(id) and id ~= seed.worldId .. ":rare-car", "invalid vehicle ID")
		player(s, owner); s.vehicles[id] = {owner = owner}
	end
	for _, item in ipairs(seed.loot or {}) do
		need(key(item.id) and not s.loot[item.id] and integer(item.value, 1), "invalid initial loot")
		s.loot[item.id] = {id = item.id, value = item.value, location = location(s, item.location), retired = false}
		s.issuedLoot += item.value
	end
	s.car = {id = seed.worldId .. ":rare-car", seats = 2, fastestCar = true, owner = nil, heistCompleted = false,
		cycle = 1, cycleStart = seed.cycleStart, cycleEnd = seed.cycleStart + WEEK, revision = 0,
		location = {kind = "Heist", id = s.carOrigin}}
	audit(s)
	return s
end

local handlers = {}

handlers.SetPresence = function(s, op)
	need(type(op.online) == "boolean", "online must be boolean")
	player(s, op.actor).online = op.online
	if not op.online then
		for _, theft in pairs(s.carThefts) do
			if theft.actor == op.actor and theft.status == "Active" then theft.status = "Interrupted" end
		end
	end
	return {online = op.online}
end

handlers.ContributeBounty = function(s, op)
	local donor = player(s, op.actor); player(s, op.target)
	need(integer(op.amount, 1) and donor.earned >= op.amount, "insufficient earned currency")
	local bounty = s.bounties[op.target] or {amount = 0, revision = 1, contributions = {}}
	need(bounty.claimId == nil, "bounty frozen for pending claim")
	need(op.bountyRevision == bounty.revision, "stale bounty revision")
	donor.earned -= op.amount; bounty.amount += op.amount
	bounty.contributions[op.actor] = (bounty.contributions[op.actor] or 0) + op.amount
	s.bounties[op.target] = bounty
	return {escrow = bounty.amount, bountyRevision = bounty.revision}
end

handlers.RecordDefeat = function(s, op)
	player(s, op.actor); player(s, op.target); evidence(op, "eligibilityDecision")
	need(not s.defeatDecisions[op.eligibilityDecision], "defeat already recorded")
	-- Attribution, disconnects, self/crew exclusions and anti-collusion remain external policy.
	local bounty = s.bounties[op.target] or {amount = 0, revision = 1, contributions = {}}
	need(not bounty.claimId, "target already has a pending defeat claim")
	need(op.bountyRevision == bounty.revision, "stale bounty revision")
	distinctList(op.droppedLootIds, "dropped loot")
	local from = {kind = "Carry", id = op.target}
	for _, id in ipairs(op.droppedLootIds) do lootAt(s, id, from).location = {kind = "World", id = op.id} end
	bounty.claimId = op.id; s.bounties[op.target] = bounty
	s.defeats[op.id] = {target = op.target, claimant = op.actor, amount = bounty.amount, status = "Pending", bountyRevision = bounty.revision, eligibilityDecision = op.eligibilityDecision}
	s.defeatDecisions[op.eligibilityDecision] = op.id
	return {claimId = op.id, escrow = bounty.amount, droppedLootIds = clone(op.droppedLootIds)}
end

handlers.ClaimBounty = function(s, op)
	local claimant = player(s, op.actor); local claim = s.defeats[op.claimId]
	need(claim and claim.status == "Pending" and claim.claimant == op.actor, "claim unavailable or wrong claimant")
	local bounty = s.bounties[claim.target]
	need(bounty.claimId == op.claimId and bounty.revision == claim.bountyRevision and bounty.amount == claim.amount, "escrow changed")
	claimant.earned += claim.amount; claim.status = "Claimed"
	s.bounties[claim.target] = {amount = 0, revision = bounty.revision + 1, contributions = {}}
	return {paidEarned = claim.amount, target = claim.target}
end

handlers.MoveLoot = function(s, op)
	player(s, op.actor)
	local from, to = location(s, op.from), location(s, op.to)
	need(not sameLocation(from, to), "loot already in destination")
	unlocked(s, from); unlocked(s, to)
	if not ownedContainer(s, op.actor, from) then evidence(op, "transferDecision") end
	distinctList(op.lootIds, "loot IDs"); need(#op.lootIds > 0, "no loot supplied")
	for _, id in ipairs(op.lootIds) do lootAt(s, id, from).location = clone(to) end
	bumpStash(s, from); bumpStash(s, to)
	return {moved = clone(op.lootIds), destination = clone(to)}
end

handlers.SplitLoot = function(s, op)
	player(s, op.actor)
	local original = s.loot[op.lootId]
	need(original and not original.retired and ownedContainer(s, op.actor, original.location), "split source not owned")
	unlocked(s, original.location)
	need(type(op.parts) == "table" and #op.parts >= 2, "at least two split portions required")
	local total, ids = 0, {}
	for _, portion in ipairs(op.parts) do
		need(key(portion.id) and not s.loot[portion.id] and not ids[portion.id] and integer(portion.value, 1), "invalid split portion")
		ids[portion.id] = true; total += portion.value
		local to = location(s, portion.location); unlocked(s, to)
		-- Pre-agreed share destinations must be adjudicated by the server before this event.
		s.loot[portion.id] = {id = portion.id, value = portion.value, location = to, retired = false, parentId = original.id}
		bumpStash(s, to)
	end
	need(total == original.value, "split must conserve exact loot value")
	original.retired = true; bumpStash(s, original.location)
	return {retiredId = original.id, splitIds = ids}
end

handlers.UpgradeDefense = function(s, op)
	local p = player(s, op.actor)
	need(op.defense == "Shield" or op.defense == "Laser", "unknown defense")
	need(not s.activeRaids[op.actor], "defense reserved by raid")
	local tier = p.defenses[op.defense]
	need(tier < 6, "six-tier maximum reached")
	local cost = s.policy.defenseCosts[tier + 1]
	need(p.earned >= cost, "insufficient earned currency")
	p.earned -= cost; s.spentEarned += cost; p.defenses[op.defense] = tier + 1; p.stashRevision += 1
	return {defense = op.defense, tier = tier + 1, earnedSpent = cost}
end

handlers.BeginRaid = function(s, op)
	player(s, op.actor); local owner = player(s, op.owner); evidence(op, "accessDecision")
	need(op.actor ~= op.owner and not s.activeRaids[op.owner], "hideout unavailable")
	need(op.stashRevision == owner.stashRevision, "stale hideout snapshot")
	local lootIds = {}
	for id, item in pairs(s.loot) do
		if not item.retired and sameLocation(item.location, {kind = "Stash", id = op.owner}) then lootIds[id] = true end
	end
	s.raids[op.id] = {status = "Active", owner = op.owner, attacker = op.actor, began = op.now,
		stashRevision = owner.stashRevision, defenses = clone(owner.defenses), lootIds = lootIds, ownerWasOnline = owner.online, accessDecision = op.accessDecision}
	s.activeRaids[op.owner] = op.id
	return {raidId = op.id, defenses = clone(owner.defenses), snapshotLootIds = clone(lootIds), ownerWasOnline = owner.online}
end

handlers.ResolveRaid = function(s, op)
	local raid = s.raids[op.raidId]; evidence(op, "outcomeDecision")
	need(raid and raid.status == "Active" and raid.attacker == op.actor, "raid unavailable")
	need(s.activeRaids[raid.owner] == op.raidId and player(s, raid.owner).stashRevision == raid.stashRevision, "stale raid snapshot")
	need(op.outcome == "RaiderEscaped" or op.outcome == "DefensesWon" or op.outcome == "Aborted", "invalid raid outcome")
	local stolen = distinctList(op.stolenLootIds, "stolen loot")
	distinctList(op.retainedLootIds, "retained loot")
	if op.outcome ~= "RaiderEscaped" then need(#op.stolenLootIds == 0, "unsuccessful raider cannot steal stash") end
	if op.outcome ~= "DefensesWon" then need(#op.retainedLootIds == 0, "only defeated raiders drop retained loot") end
	local stash = {kind = "Stash", id = raid.owner}
	local carry = {kind = "Carry", id = raid.attacker}
	local stolenValue, retainedValue = 0, 0
	for _, id in ipairs(op.stolenLootIds) do
		need(raid.lootIds[id] == true, "loot was not in raid snapshot")
		local item = lootAt(s, id, stash); item.location = clone(carry); stolenValue += item.value
	end
	for _, id in ipairs(op.retainedLootIds) do
		need(not stolen[id], "same loot listed in both raid outcomes")
		local item = lootAt(s, id, carry); item.location = clone(stash); retainedValue += item.value
	end
	s.activeRaids[raid.owner] = nil; raid.status = "Resolved"; raid.outcome = op.outcome; raid.resolved = op.now
	player(s, raid.owner).stashRevision += 1
	local entry = {operationId = op.id, raidId = op.raidId, attacker = raid.attacker, owner = raid.owner, at = op.now,
		outcome = op.outcome, stolenLootIds = clone(op.stolenLootIds), retainedLootIds = clone(op.retainedLootIds),
		stolenValue = stolenValue, retainedValue = retainedValue, defenseSnapshot = clone(raid.defenses), ownerWasOnline = raid.ownerWasOnline}
	local logs = s.raidLogs[raid.owner]; table.insert(logs, entry)
	while #logs > s.policy.raidLogLimit do table.remove(logs, 1) end
	return clone(entry)
end

handlers.CompleteCarHeist = function(s, op)
	player(s, op.actor); evidence(op, "heistDecision")
	local car = currentCar(s, op.now)
	need(not car.heistCompleted and not car.owner, "original heist already completed this cycle")
	car.heistCompleted = true; car.owner = op.actor; car.location = {kind = "Driven", id = op.actor}; car.revision += 1
	return {carId = car.id, owner = car.owner, expiresAt = car.cycleEnd}
end

handlers.StoreCar = function(s, op)
	local car = currentCar(s, op.now); player(s, op.actor)
	need(car.owner == op.actor and car.location.kind ~= "Stash", "car is not driven by owner")
	car.location = {kind = "Stash", id = op.actor}; car.revision += 1
	return {owner = car.owner, carRevision = car.revision}
end

handlers.DriveCar = function(s, op)
	local car = currentCar(s, op.now); player(s, op.actor)
	need(car.owner == op.actor and car.location.kind == "Stash", "car is not stored by owner")
	car.location = {kind = "Driven", id = op.actor}; car.revision += 1
	return {owner = car.owner, carRevision = car.revision}
end

handlers.BeginCarTheft = function(s, op)
	player(s, op.actor); evidence(op, "proximityDecision")
	need(player(s, op.actor).online, "thief disconnected")
	local car = currentCar(s, op.now)
	need(car.owner ~= nil and car.owner ~= op.actor and car.location.kind == "Stash", "car unavailable for hideout theft")
	need(op.carRevision == car.revision, "stale car revision")
	s.carThefts[op.id] = {actor = op.actor, owner = car.owner, began = op.now, validatedThrough = op.now,
		carRevision = car.revision, cycle = car.cycle, status = "Active"}
	return {theftId = op.id, readyAt = op.now + 120, expiresAt = car.cycleEnd}
end

handlers.ValidateCarTheft = function(s, op)
	evidence(op, "proximityDecision"); local theft = validTheft(s, op)
	theft.validatedThrough = op.now
	return {validatedThrough = op.now, remaining = math.max(0, 120 - (op.now - theft.began))}
end

handlers.CancelCarTheft = function(s, op)
	local theft = s.carThefts[op.theftId]
	need(theft and theft.actor == op.actor and theft.status == "Active", "invalid theft")
	theft.status = "Canceled"
	return {theftId = op.theftId}
end

handlers.CompleteCarTheft = function(s, op)
	evidence(op, "proximityDecision"); local theft, car = validTheft(s, op)
	need(op.now - theft.began >= 120, "120-second break-in incomplete")
	theft.status = "Completed"; car.owner = op.actor; car.location = {kind = "Driven", id = op.actor}; car.revision += 1
	return {carId = car.id, owner = car.owner, expiresAt = car.cycleEnd}
end

handlers.ResetCarCycle = function(s, op)
	local car = s.car; need(op.now >= car.cycleEnd, "weekly reset not due")
	local skipped = math.floor((op.now - car.cycleEnd) / WEEK) + 1
	car.cycleStart += skipped * WEEK; car.cycleEnd = car.cycleStart + WEEK; car.cycle += skipped
	local previousOwner = car.owner
	car.owner = nil; car.heistCompleted = false; car.location = {kind = "Heist", id = s.carOrigin}; car.revision += 1
	for _, theft in pairs(s.carThefts) do if theft.status == "Active" then theft.status = "Expired" end end
	return {revokedOwner = previousOwner, carId = car.id, cycle = car.cycle, expiresAt = car.cycleEnd}
end

-- Success: newState, receipt, nil, replayed. Rejection: nil, nil, reason, false.
-- No yields, no mutation of input. Commit the returned state as ONE atomic record.
function Economy.apply(state, operation)
	local ok, nextState, result, replayed = pcall(function()
		need(type(operation) == "table" and key(operation.id) and key(operation.kind), "invalid operation")
		audit(state)
		need(operation.worldId == state.worldId, "wrong world authority")
		local saved = state.operations[operation.id]
		if saved then
			need(same(saved.command, operation), "operation ID reused with different payload")
			return state, clone(saved.receipt), true
		end
		need(integer(operation.expectedRevision) and operation.expectedRevision == state.revision, "stale world revision")
		need(integer(operation.now) and operation.now >= state.time, "clock moved backwards")
		local handler = handlers[operation.kind]; need(handler ~= nil, "unknown operation kind")
		local draft = clone(state)
		local details = handler(draft, operation)
		draft.revision += 1; draft.time = operation.now
		local receipt = {operationId = operation.id, kind = operation.kind, revision = draft.revision, at = operation.now, details = details}
		draft.operations[operation.id] = {command = clone(operation), receipt = clone(receipt)}
		audit(draft)
		return draft, receipt, false
	end)
	if not ok then return nil, nil, tostring(nextState), false end
	return nextState, result, nil, replayed
end

Economy.WEEK_SECONDS = WEEK
Economy.THEFT_SECONDS = 120
return Economy
