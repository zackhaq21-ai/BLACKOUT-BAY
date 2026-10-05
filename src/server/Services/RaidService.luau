--!nonstrict
-- Hideout raids. A raid is a crew job against one owner's hideout: claim the exclusive lock in the store,
-- get past the defences (shield breaker or pier door), crack the safe (server-timed, crew-assisted), carry
-- the minted bundles home. Defences retain bags left inside. The owner gets a report either live or on return.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Palette = require(ReplicatedStorage.Shared.Palette)
local StashRules = require(ReplicatedStorage.Shared.Core.StashRules)
local HideoutRecord = require(ReplicatedStorage.Shared.Core.HideoutRecord)
local Builder = require(script.Parent.Parent.Builders.Builder)
local DefenseBuilder = require(script.Parent.Parent.Builders.DefenseBuilder)
local Comms = require(script.Parent.Comms)

local RaidService = { ctx = nil :: any }

local raids = {} -- crewId -> raid
local units = {} -- unitId -> unit state { unit, ownerUserId, ownerName, tier, refs, shieldDown, doorOpen, alarmed, safeLockedUntil, cracked, cracking, retainTimers }
local laserDebounce = {} -- player -> time
local serverId = (game.JobId ~= "" and game.JobId) or "studio"
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)

local function now()
	return os.clock()
end

local function unix()
	return os.time()
end

local HC = Config.Hideout

-- Unit binding ---------------------------------------------------------------------------------
local function inBounds(unit, pos: Vector3): boolean
	local b = unit.bounds
	return pos.X >= b.minX and pos.X <= b.maxX and pos.Z >= b.minZ and pos.Z <= b.maxZ - 32 -- living space + bay, not the pier
end

local function setShield(state, down: boolean)
	state.shieldDown = down
	for _, name in ipairs({ "shield", "shieldSide" }) do
		local p = state.refs[name]
		if p then
			p.CanCollide = not down
			p.Transparency = if down then 1 else 0.2
		end
	end
end

local function setDoor(state, open: boolean)
	state.doorOpen = open
	local d = state.refs.pierDoor
	if d then
		d.CanCollide = not open
		d.Transparency = if open then 0.8 else 0
	end
end

local function setAlarmVisual(state, on: boolean)
	local l = state.refs.alarmLight
	if not l then
		return
	end
	if on and not state.alarmLoop then
		state.alarmLoop = task.spawn(function()
			local phase = false
			while true do
				phase = not phase
				l.Color = if phase then Palette.SecurityRed else Palette.Night
				state.refs.alarmPoint.Brightness = if phase then 3 else 0
				task.wait(0.5)
			end
		end)
	elseif not on and state.alarmLoop then
		task.cancel(state.alarmLoop)
		state.alarmLoop = nil
		l.Color = Palette.Night
		state.refs.alarmPoint.Brightness = 0
	end
end

-- Harbour blackout: powered shields drop and lasers die on every unit; restored when the grid returns
-- unless the raid already cut the breaker. Idempotent.
local gridDown = false
local function setLasers(state, on: boolean)
	if not state.refs.lasers then
		return
	end
	for _, beam in ipairs(state.refs.lasers) do
		beam.Transparency = if on then 0 else 1
	end
end

function RaidService.setGridDown(down: boolean)
	if gridDown == down then
		return
	end
	gridDown = down
	for _, state in pairs(units) do
		if down then
			if not state.shieldDown then
				state.gridShield = true
				setShield(state, true)
			end
			setLasers(state, false)
		else
			if state.gridShield then
				state.gridShield = nil
				setShield(state, false)
			end
			setLasers(state, true)
		end
	end
end

function RaidService.isGridDown(): boolean
	return gridDown
end

local function resetUnit(state)
	state.gridShield = if gridDown then true else nil
	setShield(state, gridDown)
	setDoor(state, false)
	setAlarmVisual(state, false)
	state.alarmed = false
	state.cracked = false
	state.cracking = {}
	state.safeLockedUntil = 0
	if state.refs.safe then
		local gui = state.refs.safe:FindFirstChild("Label")
		local tl = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
		if tl then
			tl.Text = string.format("%s\nTIER %d", state.ownerName, state.tier)
		end
	end
end

function RaidService.bindUnit(unit, ownerUserId: number, ownerName: string, tier: number)
	local existing = units[unit.id]
	if existing and existing.alarmLoop then
		task.cancel(existing.alarmLoop)
	end
	local refs = DefenseBuilder.build(unit, tier, ownerName)
	local state = { unit = unit, ownerUserId = ownerUserId, ownerName = ownerName, tier = tier, refs = refs, shieldDown = false, doorOpen = false, alarmed = false, safeLockedUntil = 0, cracked = false, cracking = {}, retainTimers = {} }
	units[unit.id] = state
	if gridDown then
		state.gridShield = true
		setShield(state, true)
		setLasers(state, false)
	end
	if refs.breaker then
		Builder.prompt(refs.breaker, "Cut the breaker", string.format("Shield breaker (%d s)", StashRules.breakerSeconds(HC, tier) or 18), StashRules.breakerSeconds(HC, tier) or 18, "RaidBreaker", { UnitId = unit.id })
	end
	Builder.prompt(refs.pierDoor, "Cut through", if refs.defences.Shield2 then "Pier door (barred)" else string.format("Pier door (%d s)", HC.PierDoorSeconds), HC.PierDoorSeconds, "RaidPierDoor", { UnitId = unit.id })
	Builder.prompt(refs.safe, "Crack the safe", "Safe", 0, "RaidSafe", { UnitId = unit.id })
	if refs.lasers then
		for _, beam in ipairs(refs.lasers) do
			beam.Touched:Connect(function(hit)
				RaidService.onLaserTouched(unit.id, hit)
			end)
		end
	end
	return state
end

function RaidService.unbindUnit(unitId: string)
	local state = units[unitId]
	if state then
		if state.alarmLoop then
			task.cancel(state.alarmLoop)
		end
		DefenseBuilder.clear(state.unit)
		units[unitId] = nil
	end
end

function RaidService.unitState(unitId: string)
	return units[unitId]
end

function RaidService.ownerOfUnit(unitId: string): number?
	local s = units[unitId]
	return s and s.ownerUserId or nil
end

-- Helpers ----------------------------------------------------------------------------------------
local function crewOf(player: Player)
	return RaidService.ctx.services.Crew.crewOf(player)
end

local function raidOfPlayer(player: Player)
	local crew = crewOf(player)
	return crew and raids[crew.id] or nil
end

local function isRaiderAt(player: Player, unitId: string)
	local raid = raidOfPlayer(player)
	return raid ~= nil and raid.unitId == unitId and raid.active
end

local function isOwnerCrew(player: Player, state): boolean
	local crew = crewOf(player)
	return crew ~= nil and crew.leader.UserId == state.ownerUserId
end

local function ownerPlayer(state): Player?
	return Players:GetPlayerByUserId(state.ownerUserId)
end

local function raidSnapshot(raid)
	local state = units[raid.unitId]
	return {
		active = raid.active,
		targetName = raid.targetName,
		unitLabel = raid.unit.label,
		tier = state and state.tier or 0,
		shieldDown = state and (state.shieldDown or not state.refs.shield) or false,
		doorOpen = state and state.doorOpen or false,
		alarmed = state and state.alarmed or false,
		cracked = state and state.cracked or false,
		stolen = raid.stolen,
		retained = raid.retained,
		secondsLeft = math.max(0, math.floor(raid.expiresAt - now())),
		entry = raid.entry,
		recovery = raid.recovery ~= nil,
		owed = raid.recovery and raid.recovery.remaining or nil,
	}
end

local function pushRaidState(raid)
	local snap = raidSnapshot(raid)
	for _, p in ipairs(raid.crew.members) do
		Net.event("RaidState"):FireClient(p, snap)
	end
	local state = units[raid.unitId]
	local owner = state and ownerPlayer(state)
	if owner then
		local defender = table.clone(snap)
		defender.defending = true
		defender.raiderName = raid.raiderName
		defender.crewSize = #raid.crew.members
		Net.event("RaidState"):FireClient(owner, defender)
	end
end

local function triggerAlarm(raid, how: string)
	local state = units[raid.unitId]
	if not state or state.alarmed or not state.refs.defences.Alarm then
		return
	end
	state.alarmed = true
	table.insert(raid.triggered, "alarm (" .. how .. ")")
	setAlarmVisual(state, true)
	local Police = RaidService.ctx.services.Police
	for _, p in ipairs(raid.crew.members) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and inBounds(raid.unit, root.Position) then
			Police.addHeat(p, HC.AlarmHeat, "hideout alarm at " .. raid.unit.label)
		end
	end
	Comms.toastMany(raid.crew.members, "ALARM — the owner and the police know. Move.", "alarm")
	Comms.cueMany(raid.crew.members, "Alarm")
	local owner = ownerPlayer(state)
	if owner then
		Comms.toast(owner, string.format("YOUR HIDEOUT IS BEING RAIDED by %s's crew (%d) at %s. Bags left inside for %d s go back in your safe.", raid.raiderName, #raid.crew.members, raid.unit.label, HC.RetainSeconds), "alarm")
		Comms.cue(owner, "Alarm")
		RaidService.ctx.services.EventLog.crew(crewOf(owner).id, raid.raiderName .. "'s crew tripped the alarm at " .. raid.unit.label, "alarm")
	end
	pushRaidState(raid)
end

-- Raid lifecycle -------------------------------------------------------------------------------
local function beginRaid(player: Player, targetUserId: number, recovery)
	local S = RaidService.ctx.services
	local crew = crewOf(player)
	if not crew then
		return
	end
	if type(targetUserId) ~= "number" then
		return
	end
	if targetUserId == player.UserId then
		Comms.toast(player, "You can't raid your own hideout.", "warn")
		return
	end
	local verb = if recovery then "recover from" else "raid"
	for _, m in ipairs(crew.members) do
		if m.UserId == targetUserId then
			Comms.toast(player, "That's your crewmate's hideout. Leave the crew first if you mean it.", "warn")
			return
		end
	end
	if S.Mission.isJobActive(crew.id) then
		Comms.toast(player, "Close your current job first.", "warn")
		return
	end
	if player:GetAttribute("Jailed") then
		Comms.toast(player, "Get out of the cell first.", "warn")
		return
	end
	local targetName = S.HideoutStore.nameOf(targetUserId)
	local ok, err, record = S.HideoutStore.apply(targetUserId, function(r)
		return HideoutRecord.claimRaid(r, serverId, Comms.key(player), Comms.name(player), unix(), HC.RaidMaxSeconds, HC.RaidCooldownSeconds)
	end)
	if not ok then
		Comms.toast(player, "Can't " .. verb .. " " .. targetName .. ": " .. tostring(err), "warn")
		return
	end
	-- Where: the owner's live unit if they lead a crew on this server, else the Breakwater Lockup
	local unit = S.Hideout.unitOfLeader(targetUserId)
	local usingLockup = false
	if not unit then
		unit = RaidService.ctx.world.lockup
		usingLockup = true
		if units[unit.id] then
			-- Lockup busy with another raid: release our claim and refuse
			S.HideoutStore.apply(targetUserId, function(r)
				return HideoutRecord.releaseRaid(r, serverId, Comms.key(player), nil, HC.MaxReports, unix())
			end)
			Comms.toast(player, "The Breakwater Lockup is busy with another raid. Try again in a minute.", "warn")
			return
		end
		RaidService.bindUnit(unit, targetUserId, targetName, record.tier)
	end
	local state = units[unit.id]
	resetUnit(state)
	local raid = {
		id = string.format("raid_%d_%d", targetUserId, unix()),
		crewId = crew.id,
		crew = crew,
		targetUserId = targetUserId,
		targetName = targetName,
		raiderName = Comms.name(player),
		raiderKey = Comms.key(player),
		unitId = unit.id,
		unit = unit,
		usingLockup = usingLockup,
		startedAt = now(),
		expiresAt = now() + HC.RaidMaxSeconds,
		entry = nil,
		triggered = {},
		bundles = {},
		stolen = 0,
		retained = 0,
		cracked = false,
		active = true,
		recovery = recovery, -- { raidId, victimUserId, victimName, remaining } for a recovery mission
	}
	raids[crew.id] = raid
	-- Provisional report so the clue trail has a home from the first bundle move
	do
		local crewNames = {}
		for _, m in ipairs(crew.members) do
			table.insert(crewNames, Comms.name(m))
		end
		S.HideoutStore.apply(targetUserId, function(r)
			return HideoutRecord.openReport(r, { t = unix(), raidId = raid.id, raider = raid.raiderKey, raiderName = raid.raiderName, crewNames = crewNames, entry = "in progress", defences = {}, lost = 0, retained = 0, recovered = 0, recovery = recovery ~= nil, clues = {} }, HC.MaxReports), nil
		end)
	end
	local job = S.Mission.startRaidJob(player, raid)
	if not job then
		raids[crew.id] = nil
		S.HideoutStore.apply(targetUserId, function(r)
			return HideoutRecord.releaseRaid(r, serverId, Comms.key(player), nil, HC.MaxReports, unix())
		end)
		if usingLockup then
			RaidService.unbindUnit(unit.id)
		end
		Comms.toast(player, "Could not start the raid job.", "warn")
		return
	end
	if recovery then
		S.EventLog.crew(crew.id, string.format("%s started a recovery mission: %d owed by %s (tier %d) at %s", Comms.name(player), recovery.remaining, targetName, record.tier, unit.label))
		Comms.toastMany(crew.members, string.format("RECOVERY: %s owes %d. Crack their safe at %s; it gives up only what they took. %d min.", targetName, recovery.remaining, unit.label, math.floor(HC.RaidMaxSeconds / 60)), "good")
	else
		S.EventLog.crew(crew.id, string.format("%s started a raid on %s's hideout (tier %d) at %s", Comms.name(player), targetName, record.tier, unit.label))
		Comms.toastMany(crew.members, string.format("Raid on %s (tier %d) at %s. Shield breaker on the outside wall, or the pier door at the back. %d min.", targetName, record.tier, unit.label, math.floor(HC.RaidMaxSeconds / 60)), "good")
	end
	local owner = ownerPlayer(state)
	if owner then
		Comms.toast(owner, string.format("%s's crew is moving on your hideout at %s%s.", Comms.name(player), unit.label, if recovery then " to take back what you stole" else ""), "alarm")
	end
	pushRaidState(raid)
end

function RaidService.startRaid(player: Player, targetUserId: number)
	beginRaid(player, targetUserId, nil)
end

-- Victim starts a time-limited recovery mission against the raider named in one of their reports.
function RaidService.startRecovery(player: Player, raidId: string)
	local S = RaidService.ctx.services
	if type(raidId) ~= "string" then
		return
	end
	local record = S.HideoutStore.load(player.UserId)
	local rep = HideoutRecord.reportFor(record, raidId)
	if not rep or not rep.recoveryRaider then
		Comms.toast(player, "No recovery is open for that raid.", "warn")
		return
	end
	local remaining = HideoutRecord.recoverable(record, raidId, unix())
	if remaining <= 0 then
		Comms.toast(player, if rep.recoveryUntil and unix() >= rep.recoveryUntil then "The trail has gone cold. The recovery window closed." else "Everything from that raid is already back.", "warn")
		return
	end
	local raiderId = tonumber(rep.recoveryRaider)
	if not raiderId then
		return
	end
	beginRaid(player, raiderId, { raidId = raidId, victimUserId = player.UserId, victimName = Comms.name(player), remaining = remaining })
end

local function finishRaid(raid, reason: string)
	if not raid.active then
		return
	end
	raid.active = false
	local S = RaidService.ctx.services
	local state = units[raid.unitId]
	local crewNames = {}
	for _, m in ipairs(raid.crew.members) do
		table.insert(crewNames, Comms.name(m))
	end
	local lost = math.max(0, raid.stolen - raid.retained)
	local report = {
		t = unix(),
		raidId = raid.id,
		raider = raid.raiderKey,
		raiderName = raid.raiderName,
		crewNames = crewNames,
		entry = raid.entry or "never got in",
		defences = raid.triggered,
		lost = lost,
		retained = raid.retained,
		recovered = 0,
		recovery = raid.recovery ~= nil,
		-- a recovery mission does not open another recovery window (no endless chains)
		recoveryUntil = if lost > 0 and not raid.recovery then unix() + HC.RecoveryWindowSeconds else nil,
		recoveryRaider = if lost > 0 and not raid.recovery then raid.raiderKey else nil,
		clues = {},
	}
	S.HideoutStore.apply(raid.targetUserId, function(r)
		return HideoutRecord.releaseRaid(r, serverId, raid.raiderKey, report, HC.MaxReports, unix())
	end)
	S.EventLog.crew(raid.crewId, string.format("Raid on %s ended (%s): took %d, defences kept %d", raid.targetName, reason, lost, raid.retained), if lost > 0 then "good" else "warn")
	if state then
		local owner = ownerPlayer(state)
		if owner then
			Comms.toast(owner, string.format("Raid over: %s's crew took %d; your defences kept %d.", raid.raiderName, lost, raid.retained), if lost > 0 then "alarm" else "good")
			S.Hideout.pushState(owner)
		end
		if raid.usingLockup then
			RaidService.unbindUnit(raid.unitId)
		else
			resetUnit(state)
			S.Hideout.rebindUnit(raid.unit)
		end
	end
	raids[raid.crewId] = nil
	for _, p in ipairs(raid.crew.members) do
		Net.event("RaidState"):FireClient(p, { active = false })
	end
end

-- Called by MissionService when a raid job closes for any reason.
function RaidService.onJobClosed(crewId: string, reason: string)
	local raid = raids[crewId]
	if raid then
		finishRaid(raid, reason)
	end
end

function RaidService.raidOfCrew(crewId: string)
	return raids[crewId]
end

function RaidService.raidOnUnit(unitId: string)
	for _, raid in pairs(raids) do
		if raid.active and raid.unitId == unitId then
			return raid
		end
	end
	return nil
end

-- Interactions --------------------------------------------------------------------------------
function RaidService.onBreaker(player: Player, prompt: ProximityPrompt)
	local unitId = tostring(prompt:GetAttribute("UnitId"))
	local state = units[unitId]
	if not state then
		return
	end
	if not isRaiderAt(player, unitId) then
		Comms.toast(player, "Start a raid on this hideout from your job board first.", "warn")
		return
	end
	local raid = raidOfPlayer(player)
	if state.shieldDown then
		return
	end
	state.gridShield = nil
	setShield(state, true)
	raid.entry = raid.entry or "cut the shield breaker"
	table.insert(raid.triggered, "shield breaker cut")
	Comms.toastMany(raid.crew.members, "Shield down. The bay is open.", "good")
	Comms.cueAt("PowerCut", (prompt.Parent :: BasePart).Position)
	triggerAlarm(raid, "breaker")
	pushRaidState(raid)
end

function RaidService.onPierDoor(player: Player, prompt: ProximityPrompt)
	local unitId = tostring(prompt:GetAttribute("UnitId"))
	local state = units[unitId]
	if not state then
		return
	end
	if not isRaiderAt(player, unitId) then
		Comms.toast(player, "Start a raid on this hideout from your job board first.", "warn")
		return
	end
	local raid = raidOfPlayer(player)
	if state.refs.defences.Shield2 then
		Comms.toast(player, "The pier door is barred at this tier. Cut the shield breaker on the outside wall.", "warn")
		return
	end
	if state.doorOpen then
		return
	end
	setDoor(state, true)
	raid.entry = raid.entry or "cut through the pier door"
	table.insert(raid.triggered, "pier door cut")
	Comms.cueAt("Unlock", state.refs.pierDoor.Position)
	triggerAlarm(raid, "pier door")
	pushRaidState(raid)
end

function RaidService.onSafe(player: Player, prompt: ProximityPrompt)
	local unitId = tostring(prompt:GetAttribute("UnitId"))
	local state = units[unitId]
	if not state then
		return
	end
	if isOwnerCrew(player, state) then
		Comms.toast(player, "This is your safe. Manage it from the job board (Hideout tab).", "info")
		return
	end
	if not isRaiderAt(player, unitId) then
		Comms.toast(player, "Start a raid on this hideout from your job board first.", "warn")
		return
	end
	local raid = raidOfPlayer(player)
	if state.cracked then
		Comms.toast(player, "Already cracked. Grab the bundles.", "info")
		return
	end
	if now() < state.safeLockedUntil then
		Comms.toast(player, string.format("Safe locked by the laser trip: %d s.", math.ceil(state.safeLockedUntil - now())), "warn")
		return
	end
	if state.cracking[player] then
		return
	end
	state.cracking[player] = 0
	raid.entry = raid.entry or "walked in"
	triggerAlarm(raid, "safe")
	Comms.toast(player, "Cracking. Stay on the safe; a crewmate beside you speeds it up.", "info")
end

-- Laser trip: stun, drop the bag, lock the safe at the top tier
function RaidService.onLaserTouched(unitId: string, hit: BasePart)
	local state = units[unitId]
	if not state then
		return
	end
	if gridDown then
		return -- lasers are unpowered during a blackout
	end
	local char = hit:FindFirstAncestorOfClass("Model")
	local player = char and Players:GetPlayerFromCharacter(char)
	if not player or isOwnerCrew(player, state) then
		return
	end
	local t = now()
	if (laserDebounce[player] or 0) + HC.LaserStunSeconds > t then
		return
	end
	laserDebounce[player] = t
	Comms.cueAt("LaserTrip", hit.Position)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		task.delay(HC.LaserStunSeconds, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
			end
		end)
	end
	local dropped = RaidService.ctx.services.Loot.dropAll(player, "zapped by a laser")
	state.cracking[player] = nil
	Comms.cue(player, "Arrest")
	Comms.toast(player, "Laser trip: stunned " .. HC.LaserStunSeconds .. " s" .. (if #dropped > 0 then ", dropped " .. table.concat(dropped, ", ") else "") .. ".", "alarm")
	local raid = raidOfPlayer(player)
	if raid and raid.unitId == unitId then
		table.insert(raid.triggered, "laser trip")
		if state.refs.defences.Lasers2 then
			state.safeLockedUntil = t + HC.LaserSafeLockSeconds
			Comms.toastMany(raid.crew.members, string.format("The safe locked down for %d s.", HC.LaserSafeLockSeconds), "warn")
		end
		triggerAlarm(raid, "laser")
		pushRaidState(raid)
	end
end

-- Ticks ----------------------------------------------------------------------------------------
local function tickCracking(dt: number)
	local S = RaidService.ctx.services
	for _, raid in pairs(raids) do
		local state = units[raid.unitId]
		if raid.active and state and not state.cracked then
			local safePos = state.refs.safe.Position
			local nearby = 0
			for _, m in ipairs(raid.crew.members) do
				local root = m.Character and m.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - safePos).Magnitude <= 8 then
					nearby += 1
				end
			end
			for player, progress in pairs(state.cracking) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if not root or not humanoid or humanoid.Health <= 0 or humanoid.PlatformStand or (root.Position - safePos).Magnitude > 6 or now() < state.safeLockedUntil then
					state.cracking[player] = nil
					Comms.hud(player, { crackProgress = 0 })
					Comms.toast(player, "Cracking interrupted. Get back on the safe.", "warn")
				else
					local seconds = StashRules.safeCrackSeconds(HC, state.tier, nearby)
					local np = progress + dt / seconds
					state.cracking[player] = np
					Comms.hud(player, { crackProgress = math.clamp(np, 0, 1), crackAssist = nearby >= 2 })
					if np >= 1 then
						state.cracked = true
						raid.cracked = true
						state.cracking = {}
						Comms.hud(player, { crackProgress = 0 })
						local ok, amount
						if raid.recovery then
							ok, amount = S.HideoutStore.apply(raid.targetUserId, function(r)
								return HideoutRecord.recover(r, serverId, raid.raiderKey, raid.recovery.raidId, raid.recovery.remaining, unix())
							end)
						else
							ok, amount = S.HideoutStore.apply(raid.targetUserId, function(r)
								return HideoutRecord.crack(r, serverId, raid.raiderKey, function(stash)
									return StashRules.exposed(HC, stash)
								end, unix())
							end)
						end
						if not ok then
							state.cracked = false
							Comms.toastMany(raid.crew.members, "The safe jammed (store unavailable). Try again.", "warn")
							break
						end
						raid.stolen = amount or 0
						local gui = state.refs.safe:FindFirstChild("Label")
						local tl = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
						if tl then
							tl.Text = "CRACKED"
						end
						if raid.stolen > 0 then
							local values = StashRules.bundles(HC, raid.stolen)
							local origin = if raid.recovery then "raid:" .. raid.recovery.raidId else "raid:" .. raid.id
							local label = if raid.recovery then "Stash of " .. raid.recovery.victimName else "Stash of " .. raid.targetName
							local ids = S.Loot.mintBundles(values, safePos + Vector3.new(0, 1, 4), origin, label)
							for _, id in ipairs(ids) do
								raid.bundles[id] = true
							end
							S.Mission.minted(raid.crewId, ids, "Stash Bundle")
							Comms.toastMany(raid.crew.members, string.format("Safe open: %d in %d bundle(s). Get them home.%s", raid.stolen, #values, if raid.recovery then " Only what they took came out." else ""), "good")
						else
							Comms.toastMany(raid.crew.members, "Safe open... and nearly empty. Nothing above the protected floor.", "warn")
						end
						Comms.cueMany(raid.crew.members, "Unlock")
						local owner = ownerPlayer(state)
						if owner then
							Comms.toast(owner, string.format("Your safe was cracked: %d is on the floor at %s.", raid.stolen, raid.unit.label), "alarm")
							S.Hideout.pushState(owner)
						end
						pushRaidState(raid)
						break
					end
				end
			end
		end
	end
end

-- Bags left unattended inside a bound unit are absorbed into the owner's safe.
local function tickRetention(dt: number)
	local S = RaidService.ctx.services
	local dropped = S.Loot.droppedItems()
	for unitId, state in pairs(units) do
		local seen = {}
		for _, entry in ipairs(dropped) do
			if inBounds(state.unit, entry.position) then
				local attended = false
				for _, p in ipairs(Players:GetPlayers()) do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if root and (root.Position - entry.position).Magnitude <= 4 then
						attended = true
						break
					end
				end
				seen[entry.item.id] = true
				if attended then
					state.retainTimers[entry.item.id] = 0
				else
					local tt = (state.retainTimers[entry.item.id] or 0) + dt
					state.retainTimers[entry.item.id] = tt
					if tt >= HC.RetainSeconds then
						state.retainTimers[entry.item.id] = nil
						local value = entry.item.value
						local ok = true
						if value > 0 then
							ok = S.HideoutStore.apply(state.ownerUserId, function(r)
								return HideoutRecord.retain(r, value)
							end)
						end
						if ok then
							S.Loot.absorb(entry.item.id, "retained by " .. state.ownerName .. "'s defences")
							for _, raid in pairs(raids) do
								if raid.unitId == unitId and raid.active then
									if raid.bundles[entry.item.id] then
										raid.retained += value
									end
									Comms.toastMany(raid.crew.members, entry.item.label .. " was pulled back into the safe.", "warn")
									pushRaidState(raid)
								end
							end
							local owner = ownerPlayer(state)
							if owner then
								Comms.toast(owner, string.format("Your defences kept %s (%d).", entry.item.label, value), "good")
								S.Hideout.pushState(owner)
							end
						end
					end
				end
			end
		end
		for id in pairs(state.retainTimers) do
			if not seen[id] then
				state.retainTimers[id] = nil
			end
		end
	end
end

local function tickLasers(t: number)
	for _, state in pairs(units) do
		if state.refs.lasers and state.refs.defences.Lasers2 then
			for i, beam in ipairs(state.refs.lasers) do
				local baseZ = beam:GetAttribute("BaseZ")
				local baseY = beam:GetAttribute("BaseY")
				beam.CFrame = CFrame.new(beam.Position.X, baseY + math.sin(t * 1.2 + i) * 0.5, baseZ + math.sin(t * 0.7 + i * 1.7) * 3.5)
			end
		end
	end
end

-- Engine-test helper: jump a cracker's progress (the normal tick completes and mints on the next step).
function RaidService.testSetCrack(player: Player, progress: number)
	for _, state in pairs(units) do
		if state.cracking[player] ~= nil then
			state.cracking[player] = progress
			return true
		end
	end
	return false
end

-- Clue trail and recovery credit: every move of a "raid:<id>" bundle leaves a clue on the victim's report;
-- a delivery by the victim's crew credits the report (the same bundle, never a copy).
local function victimOfOrigin(origin: string?): (string?, number?)
	if type(origin) ~= "string" then
		return nil, nil
	end
	local raidId = origin:match("^raid:(.+)$")
	if not raidId then
		return nil, nil
	end
	local victim = tonumber(raidId:match("^raid_(%d+)_") or "")
	return raidId, victim
end

local function leaderOf(player: Player): number?
	local crew = RaidService.ctx.services.Crew.crewOf(player)
	return crew and crew.leader.UserId or nil
end

local function addClue(victimUserId: number, raidId: string, text: string)
	local S = RaidService.ctx.services
	S.HideoutStore.apply(victimUserId, function(r)
		local rec = HideoutRecord.addClue(r, raidId, { t = unix(), text = text }, HC.MaxClues)
		return rec, nil
	end)
	local victim = Players:GetPlayerByUserId(victimUserId)
	if victim then
		Comms.toast(victim, "Clue: " .. text, "warn")
		S.Hideout.pushState(victim)
	end
end

local function onLootEvent(kind: string, data)
	local item = data.item
	local raidId, victimUserId = victimOfOrigin(item and item.origin)
	if not raidId or not victimUserId then
		return
	end
	local S = RaidService.ctx.services
	local who = data.player and Comms.name(data.player) or "someone"
	local pos = data.position or (data.player and data.player.Character and data.player.Character:GetPivot().Position) or nil
	local where = if pos then Blueprint.nearestLandmark(pos.X, pos.Z) else "the island"
	if kind == "pickup" then
		addClue(victimUserId, raidId, string.format("%s picked up %s near %s", who, item.label, where))
	elseif kind == "drop" then
		addClue(victimUserId, raidId, string.format("%s left on the ground near %s (%s)", item.label, where, data.note or "dropped"))
	elseif kind == "stow" then
		local vlabel = data.vehicle and data.vehicle:GetAttribute("Label") or "a vehicle"
		addClue(victimUserId, raidId, string.format("%s stowed %s in a %s near %s", who, item.label, tostring(vlabel), where))
	elseif kind == "deliver" and data.player then
		local crew = S.Crew.crewOf(data.player)
		local unitLabel = crew and crew.unit and crew.unit.label or "a hideout"
		if leaderOf(data.player) == victimUserId then
			-- the victim's crew got it back: credit the report, bounded by what was lost
			S.HideoutStore.apply(victimUserId, function(r)
				return HideoutRecord.noteRecovered(r, raidId, data.value)
			end)
			addClue(victimUserId, raidId, string.format("RECOVERED %d: %s brought %s home", data.value, who, item.label))
		else
			addClue(victimUserId, raidId, string.format("%s delivered %s to %s", who, item.label, unitLabel))
		end
	elseif kind == "absorbed" then
		addClue(victimUserId, raidId, string.format("%s: %s", item.label, data.note or "gone"))
	end
end

function RaidService.init(ctx)
	RaidService.ctx = ctx
end

function RaidService.start()
	local S = RaidService.ctx.services
	S.Loot.onEvent(onLootEvent)
	task.spawn(function()
		local last = now()
		while true do
			task.wait(0.25)
			local t = now()
			local dt = t - last
			last = t
			tickCracking(dt)
			tickLasers(t)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tickRetention(1)
			for crewId, raid in pairs(raids) do
				if raid.active and now() >= raid.expiresAt then
					S.Mission.closeJobOfCrew(crewId, "Raid window expired")
				end
			end
			for _, raid in pairs(raids) do
				if raid.active then
					pushRaidState(raid)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		laserDebounce[player] = nil
		for _, state in pairs(units) do
			state.cracking[player] = nil
		end
	end)
end

return RaidService
