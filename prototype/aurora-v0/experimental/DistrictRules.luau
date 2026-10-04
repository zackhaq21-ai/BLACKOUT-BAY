-- Server-owned next-milestone model. Not wired to the first-heist place yet.
-- Time/distance/evidence inputs MUST come from trusted server simulation, never remotes.
local District = {}
local defaults = {npcCount = 10, blackoutDuration = 90, blackoutCooldown = 240, playerEscapeSteps = 2, npcEscapeSteps = 3}
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for k,v in pairs(value) do result[k] = copy(v) end; return result
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
local function key(value)
	return type(value) == "string" and #value > 0 and #value < 160
end
local function actor(s, id)
	assert(type(id) == "string" and s.actors[id], "Unknown actor")
	return s.actors[id]
end
local function number(value)
	return type(value) == "number" and value == value and value >= 0 and value < 1e12
end
function District.new(now)
	assert(number(now))
	return {
		version = 1, clock = now, actors = {}, crews = {}, npcs = defaults.npcCount, humanCops = 0,
		blackout = {untilTime = 0, nextAllowed = 0, initiator = nil},
		circuits = {cameras = true, poweredDoors = true, windows = true, auxiliaryObjective = false},
		convoys = {}, decoys = {}, events = {}, applied = {},
	}
end
local function population(s)
	local cops = 0
	for _, a in pairs(s.actors) do if a.online and a.faction == "Police" then cops += 1 end end
	s.npcs = cops == 0 and defaults.npcCount or 0
	s.humanCops = cops
	-- Existing jail origin stays unchanged when fallback NPCs retire.
end
local function event(s, kind, who)
	table.insert(s.events, {kind = kind, actor = who, time = s.clock})
	if #s.events > 100 then table.remove(s.events, 1) end
end
local function refreshLeader(s, crewId)
	local crew = crewId and s.crews[crewId]
	if not crew then return end
	local current = crew.leader and s.actors[crew.leader]
	if current and current.online and current.faction == "Crew" and current.crew == crewId and crew.members[crew.leader] then return end
	local candidates = {}
	for id in pairs(crew.members) do
		local a = s.actors[id]
		if a and a.online and a.faction == "Crew" and a.crew == crewId then table.insert(candidates, id) end
	end
	table.sort(candidates); crew.leader = candidates[1] -- No online members => no acting leader.
end
local function releaseCrew(s, id)
	local a = actor(s, id)
	local oldCrew = a.crew
	if a.crew and s.crews[a.crew] then
		s.crews[a.crew].members[id] = nil
		if next(s.crews[a.crew].members) == nil then s.crews[a.crew] = nil end
	end
	a.crew = nil
	refreshLeader(s, oldCrew)
end
local function requireFree(a)
	assert(a.online and not a.jail, "Actor is unavailable or detained")
end
local function requireSession(a, session)
	assert(type(session) == "number" and session == a.session, "Stale actor session")
end
local function freeActor(s, op)
	local a = actor(s, op.actor); requireFree(a); requireSession(a, op.session)
	return a
end
local function apply(s, op)
	if op.kind == "Join" then
		assert(type(op.actor) == "string" and #op.actor > 0 and #op.actor < 80)
		if not s.actors[op.actor] then
			s.actors[op.actor] = {faction = "Crew", online = true, session = 1, heat = 0, recognized = {}, jail = nil}
		else
			local a = s.actors[op.actor]
			if not a.online then a.session += 1 end
			a.online = true
		end
		refreshLeader(s, s.actors[op.actor].crew)
		population(s)
	elseif op.kind == "Leave" then
		local a = actor(s, op.actor); requireSession(a, op.session)
		a.online = false; refreshLeader(s, a.crew); population(s)
	elseif op.kind == "Faction" then
		local a = freeActor(s, op)
		assert(op.faction == "Crew" or op.faction == "Police")
		if a.faction ~= op.faction then
			-- No evade-heat faction switch during an active pursuit.
			assert(a.heat == 0, "Clear heat before switching faction")
			releaseCrew(s, op.actor); a.faction = op.faction; population(s)
			event(s, "Faction", op.actor)
		end
	elseif op.kind == "Crew" then
		local a = freeActor(s, op); assert(a.faction == "Crew")
		assert(type(op.crew) == "string" and #op.crew > 0 and #op.crew < 80)
		local c = s.crews[op.crew] or {members = {}, leader = op.actor}
		if not c.members[op.actor] then
			local count = 0; for _ in pairs(c.members) do count += 1 end
			assert(count < 5, "A crew holds at most five people")
				releaseCrew(s, op.actor); c.members[op.actor] = true; s.crews[op.crew] = c; a.crew = op.crew
		end
		refreshLeader(s, op.crew)
	elseif op.kind == "Heat" then
		local a = actor(s, op.actor); assert(a.faction == "Crew")
		assert(type(op.delta) == "number" and op.delta == op.delta and math.abs(op.delta) <= 5)
		a.heat = math.clamp(a.heat + op.delta, 0, 5)
		if op.vehicle then
			assert(type(op.vehicle) == "string" and #op.vehicle < 100)
			a.recognized[op.vehicle] = s.clock + 180
		end
	elseif op.kind == "Arrest" then
		local target = actor(s, op.target); requireFree(target); requireSession(target, op.targetSession)
		assert(target.faction == "Crew" and target.heat > 0, "No arrest without eligible heat")
		assert(op.evidence and op.evidence.lineOfSight == true and op.evidence.stunned == true)
		assert(number(op.evidence.distance) and op.evidence.distance <= 6, "Arrest out of range")
		local origin
		assert(op.npc == nil or type(op.npc) == "boolean", "Invalid arrest origin")
		if op.npc == true then
			assert(s.npcs > 0, "NPC fallback not active"); origin = "NPC"
		else
			local cop = freeActor(s, op); assert(cop.faction == "Police"); origin = "Player"
		end
		target.jail = {id = op.id, origin = origin, steps = {}, needed = origin == "NPC" and defaults.npcEscapeSteps or defaults.playerEscapeSteps, revision = 1}
		target.heat = 0; event(s, "Arrest" .. origin, op.target)
	elseif op.kind == "EscapeStep" then
		local prisoner = actor(s, op.target)
		assert(prisoner.jail and prisoner.online)
		requireSession(prisoner, op.targetSession)
		assert(op.jailId == prisoner.jail.id and op.revision == prisoner.jail.revision, "Stale detention interaction")
		local helper = actor(s, op.actor); assert(helper.online and helper.faction == "Crew")
		requireSession(helper, op.session)
		assert(op.actor == op.target or (helper.crew ~= nil and helper.crew == prisoner.crew), "Only prisoner or teammate can help")
		if op.actor ~= op.target then assert(not helper.jail, "Detained helper cannot act outside") end
		assert(op.evidence and op.evidence.channelComplete == true and op.evidence.inRange == true, "Unverified escape interaction")
		assert(number(op.step) and op.step % 1 == 0 and op.step >= 1 and op.step <= prisoner.jail.needed)
		assert(not prisoner.jail.steps[op.step], "Escape step already completed")
		if op.step > 1 then assert(prisoner.jail.steps[op.step-1], "Previous escape step required") end
		prisoner.jail.steps[op.step] = true; prisoner.jail.revision += 1
		if op.step == prisoner.jail.needed then
			prisoner.jail = nil; prisoner.heat = 1; event(s, "PrisonBreak", op.target)
		end
	elseif op.kind == "Blackout" then
		local a = freeActor(s, op); assert(a.faction == "Crew")
		assert(op.evidence and op.evidence.channelComplete == true and op.evidence.atGrid == true, "Unverified blackout interaction")
		assert(s.clock >= s.blackout.nextAllowed, "Blackout cooling down")
		s.blackout = {untilTime = s.clock + defaults.blackoutDuration, nextAllowed = s.clock + defaults.blackoutCooldown, initiator = op.actor}
		s.circuits = {cameras = false, poweredDoors = false, windows = false, auxiliaryObjective = true}
		a.heat = math.min(5, a.heat + 1); event(s, "Blackout", op.actor)
	elseif op.kind == "Decoy" then
		local a = freeActor(s, op); assert(a.faction == "Crew")
		assert(key(op.decoy) and not s.decoys[op.decoy])
		assert(op.appearance == "Car" or op.appearance == "Bag")
		-- Deliberately no value, loot IDs, wallet, or entitlement in a decoy.
		s.decoys[op.decoy] = {owner = op.actor, appearance = op.appearance, fake = true, created = s.clock}
	elseif op.kind == "ConvoySpawn" then
		assert(key(op.convoy) and not s.convoys[op.convoy])
		assert(key(op.lootId))
		for _, c in pairs(s.convoys) do assert(c.lootId ~= op.lootId, "Loot already assigned to convoy") end
		s.convoys[op.convoy] = {state = "Moving", routeIndex = 1, lootId = op.lootId, claimedBy = nil, revision = 1}
	elseif op.kind == "ConvoyAdvance" then
		local c = s.convoys[op.convoy]; assert(c and c.state == "Moving")
		assert(op.revision == c.revision, "Stale convoy revision")
		c.routeIndex += 1; c.revision += 1
	elseif op.kind == "ConvoyIntercept" then
		local a = freeActor(s, op); assert(a.faction == "Crew")
		local c = s.convoys[op.convoy]; assert(c and c.state == "Moving")
		assert(op.revision == c.revision)
		assert(op.evidence and op.evidence.inRange == true and op.evidence.channelComplete == true)
		c.state = "Stopped"; c.revision += 1; a.heat = math.min(5, a.heat + 2)
	elseif op.kind == "ConvoyClaim" then
		local a = freeActor(s, op); assert(a.faction == "Crew")
		local c = s.convoys[op.convoy]; assert(c and c.state == "Stopped" and op.revision == c.revision)
		assert(op.evidence and op.evidence.inRange == true and op.evidence.channelComplete == true)
		c.state = "Claimed"; c.claimedBy = op.actor; c.revision += 1
		-- Integration must transfer c.lootId through the same authoritative economy transaction.
		event(s, "ConvoyClaim", op.actor)
	else error("Unknown district operation") end
end
function District.apply(old, op)
	assert(type(op) == "table" and key(op.id))
	if old.applied[op.id] then
		assert(same(old.applied[op.id], op), "Operation ID reused with different payload")
		return old, false
	end
	local nextState = copy(old)
	apply(nextState, op)
	nextState.applied[op.id] = copy(op)
	return nextState, true
end
function District.tick(old, now)
	assert(number(now) and now >= old.clock, "Time cannot move backward")
	local s = copy(old); s.clock = now
	if s.blackout.untilTime > 0 and now >= s.blackout.untilTime then
		s.blackout.untilTime = 0
		s.circuits = {cameras = true, poweredDoors = true, windows = true, auxiliaryObjective = false}
		event(s, "PowerRestored", s.blackout.initiator)
	end
	for _, a in pairs(s.actors) do
		for id, expiry in pairs(a.recognized) do if expiry <= now then a.recognized[id] = nil end end
	end
	return s
end
function District.vehicleRecognized(s, actorId, vehicle)
	local expiry = actor(s, actorId).recognized[vehicle]
	return expiry ~= nil and expiry > s.clock
end
return District
