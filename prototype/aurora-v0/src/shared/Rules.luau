-- Pure deterministic gameplay model: also runs in the standalone Luau test runner.
local Rules = {}
local roles = {"Coordinator", "Signal specialist", "Courier", "Lookout", "Pathfinder"}
local entrances = {"Exhibit", "Service", "Skybridge"}
local vaults = {"West", "North", "East"}

function Rules.random(seed)
	local value = math.floor(math.abs(seed)) % 2147483646 + 1
	return function(maximum)
		value = (value * 16807) % 2147483647
		return (value % maximum) + 1
	end
end

function Rules.required(count)
	return math.min(4, 1 + math.ceil(math.clamp(count, 1, 5) / 2))
end

function Rules.roles(members)
	local ids = {}
	for id in pairs(members) do table.insert(ids, id) end
	table.sort(ids)
	for i, id in ipairs(ids) do members[id].role = #ids == 1 and "Solo / all tools" or roles[i] end
	return ids
end

function Rules.new(ids, seed, mode, day)
	assert(#ids >= 1 and #ids <= 5, "Crew must have 1 to 5 players")
	local rng = Rules.random(seed)
	local s = {
		status = "Active", seed = seed, mode = mode, day = day,
		members = {}, needed = Rules.required(#ids), signals = {}, signalCount = 0,
		vault = vaults[rng(3)], watchedEntrance = entrances[rng(3)], patrolOffset = rng(4),
		heat = 0, alarmed = false, timeLeft = 480, elapsed = 0,
		powerOff = false, vaultOpen = false, vaultForced = false,
		curator = "Waiting", core = "Vault", carrier = nil, bonus = 0,
		entrancesUsed = {}, captures = 0, result = nil, credited = false,
	}
	for _, id in ipairs(ids) do
		assert(s.members[id] == nil, "Duplicate crew member")
		s.members[id] = {role = "", entered = false, captured = false, escaped = false, bonus = 0, stasis = 3}
	end
	Rules.roles(s.members)
	return s
end

function Rules.addHeat(s, amount)
	if s.status ~= "Active" then return end
	s.heat = math.clamp(s.heat + amount, 0, 100)
	if s.heat >= 100 and not s.alarmed then
		s.alarmed = true
		s.timeLeft = math.min(s.timeLeft, 60)
	end
end

function Rules.remove(s, id)
	if not s.members[id] then return false end
	local dropped = s.carrier == id
	if dropped then s.carrier = nil; s.core = "Dropped" end
	s.members[id] = nil
	local ids = Rules.roles(s.members)
	s.needed = math.min(s.needed, Rules.required(#ids))
	if #ids == 0 and s.status == "Active" then
		s.status = "Failed"; s.result = "Crew disconnected"
	end
	return dropped
end

function Rules.enter(s, id, entrance)
	local m = s.members[id]
	if s.status ~= "Active" or not m or m.captured or m.entered then return false end
	if not table.find(entrances, entrance) then return false end
	m.entered = true; s.entrancesUsed[entrance] = true
	if entrance == s.watchedEntrance then Rules.addHeat(s, 12) end
	return true
end

function Rules.available(s, id)
	local m = s.members[id]
	return s.status == "Active" and m ~= nil and m.entered and not m.captured and not m.escaped
end

function Rules.signal(s, id, index)
	if not Rules.available(s, id) or index < 1 or index > 4 or index % 1 ~= 0 then return false end
	if s.signals[index] or s.signalCount >= s.needed then return false end
	s.signals[index] = true; s.signalCount += 1
	return true
end

function Rules.power(s, id)
	if not Rules.available(s, id) or s.powerOff then return false end
	s.powerOff = true
	return true
end

function Rules.curator(s, id, choice)
	if not Rules.available(s, id) then return false end
	if choice == "Release" and s.curator ~= "Released" then
		s.curator = "Released"; Rules.addHeat(s, -15); return true
	elseif choice == "Capture" and s.curator == "Waiting" then
		s.curator = "Captured"
		if s.signalCount < s.needed then
			for i = 1, 4 do
				if not s.signals[i] then s.signals[i] = true; s.signalCount += 1; break end
			end
		end
		Rules.addHeat(s, 25); return true
	end
	return false
end

function Rules.vault(s, id, forced)
	if not Rules.available(s, id) or s.vaultOpen then return false end
	if not forced and (s.signalCount < s.needed or not s.powerOff) then return false end
	s.vaultOpen = true; s.vaultForced = forced
	if forced then Rules.addHeat(s, 65) end
	return true
end

function Rules.takeCore(s, id)
	if not Rules.available(s, id) or not s.vaultOpen then return false end
	if s.core ~= "Vault" and s.core ~= "Dropped" then return false end
	s.core = "Carried"; s.carrier = id
	Rules.addHeat(s, 8)
	return true
end

function Rules.capture(s, id)
	if not Rules.available(s, id) then return false end
	local m = s.members[id]
	m.captured = true; m.bonus = 0; s.captures += 1
	if s.carrier == id then s.carrier = nil; s.core = "Dropped" end
	Rules.addHeat(s, 10)
	return true
end

function Rules.recover(s, id)
	local m = s.members[id]
	if s.status ~= "Active" or not m or not m.captured then return false end
	m.captured = false; m.entered = false
	s.timeLeft = math.max(0, s.timeLeft - 15)
	return true
end

function Rules.canExit(s, route)
	if route == "Tram" then return s.heat < 75 end
	if route == "Canal" then return s.curator == "Released" end
	return route == "Tunnel" -- Always available, including solo and full lockdown.
end

function Rules.extract(s, id, route, nearby)
	if not Rules.available(s, id) or s.carrier ~= id or not Rules.canExit(s, route) then return false end
	s.status = "Success"; s.exit = route
	local count = 0
	for memberId, m in pairs(s.members) do
		m.escaped = nearby[memberId] == true and m.entered and not m.captured
		if m.escaped then count += 1 end
	end
	s.result = s.alarmed and "LAST LIGHT" or (s.vaultForced and "SMASH & DASH" or (s.captures == 0 and s.heat < 35 and "GHOST CREW" or "NARROW ESCAPE"))
	s.escapedCount = count
	return true
end

function Rules.tick(s, dt)
	if s.status ~= "Active" then return end
	s.elapsed += dt; s.timeLeft = math.max(0, s.timeLeft - dt)
	if s.timeLeft <= 0 then s.status = "Failed"; s.result = "THE LIGHTS WENT OUT" end
end

function Rules.reward(s, id)
	local m = s.members[id]
	if not m or s.status == "Active" then return 0 end
	if s.status == "Failed" or not m.escaped then return 25 end
	return 100 + m.bonus * 20 + (s.result == "GHOST CREW" and 50 or 0) + (s.curator == "Released" and 25 or 0)
end

return Rules
