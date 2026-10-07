--!nonstrict
-- Armored convoy world event: anticipation → tracking → interception → escalation → extraction → escape →
-- cooldown. Server-authoritative throughout: route choice, spawn validity, vehicle driving, escort perception,
-- threat escalation, cargo (claimed exactly once, minted as ledger items), police response through heat,
-- cleanup. The client only receives ConvoyState/WorldEvent payloads. Blackout state is read from BlackoutService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local ConvoyRules = require(ReplicatedStorage.Shared.Core.ConvoyRules)
local Builder = require(script.Parent.Parent.Builders.Builder)
local ConvoyDriver = require(script.Parent.Parent.NPC.ConvoyDriver)
local Comms = require(script.Parent.Comms)

local ConvoyService = {}
ConvoyService.ctx = nil :: any

local CC = Config.WorldEvents.Convoy
local EVENT = "convoy"
local ROAD_Y = 1 -- spawn frame height for ground-level roads (chassis sits at +1.3, wheels touch at -0.5)

local ev = nil -- the single active convoy, or nil
local lastRouteIndex = nil
local nextAutoAt = 0
local eventCounter = 0
local holds: { [Player]: { prompt: ProximityPrompt, progress: number } } = {}
local loiter: { [Player]: number } = {}
local heatAt: { [Player]: number } = {}
local loop: thread?
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function landmarkOf(pos: Vector3): string
	return Blueprint.nearestLandmark(pos.X, pos.Z)
end

-- Vehicles ----------------------------------------------------------------------------------
local function spawnFrames(route, gap: number): { CFrame }
	local a, b = route.waypoints[1], route.waypoints[2]
	local dir = Vector3.new(b.x - a.x, 0, b.z - a.z).Unit
	local start = Vector3.new(a.x, ROAD_Y, a.z)
	local frames = {}
	for i, offset in ipairs({ 2 * gap + 12, gap + 12, 12 }) do
		local p = start + dir * offset
		-- Do not drop a vehicle onto a player: slide the whole formation forward (bounded) if anyone is close
		for _ = 1, 3 do
			local clash = false
			for _, player in ipairs(Players:GetPlayers()) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < 24 then
					clash = true
				end
			end
			if not clash then
				break
			end
			p += dir * 30
		end
		frames[i] = CFrame.lookAt(p, p + dir)
	end
	return frames
end

local function setStrobes(on: boolean)
	if not ev then
		return
	end
	for _, v in ipairs(ev.vehicles) do
		for _, d in ipairs(v.rec.model:GetChildren()) do
			if d.Name == "SecurityLight" or d.Name == "LightBar" then
				local pl = d:FindFirstChildOfClass("PointLight")
				if on then
					ev.strobePhase = not ev.strobePhase
					d.Color = if ev.strobePhase then Palette.SecurityAmber else Palette.SecurityRed
					if pl then
						pl.Brightness = 2
						pl.Color = d.Color
					end
				else
					d.Color = Palette.SecurityAmber
					if pl then
						pl.Brightness = 0
					end
				end
			end
		end
	end
end

local function setCargoLight(color: Color3)
	local lamp = ev and ev.transport.rec.model:FindFirstChild("CargoLight")
	if lamp then
		lamp.Color = color
	end
end

-- Replication -----------------------------------------------------------------------------------
local function snapshot()
	if not ev then
		return { active = false }
	end
	local pos = if ev.transport then ev.transport.rec.chassis.Position else Vector3.new(ev.route.waypoints[1].x, 0, ev.route.waypoints[1].z)
	local pub = ConvoyRules.publicState(ev.phase, ev.cargo, ev.alert, ev.looseCount or 0)
	return {
		active = true,
		phase = pub.phase,
		cargo = pub.cargo,
		crates = pub.crates,
		variant = ev.variant,
		alert = pub.alert,
		landmark = landmarkOf(pos),
		secondsLeft = ConvoyService.ctx.services.WorldEvent.secondsLeft(EVENT),
		x = math.floor(pos.X),
		z = math.floor(pos.Z),
	}
end

local function pushState()
	Net.event("ConvoyState"):FireAllClients(snapshot())
end

-- Escalation -----------------------------------------------------------------------------------
local function escalate(threat: string, source: Player?)
	if not ev then
		return
	end
	local S = ConvoyService.ctx.services
	local rose = ConvoyRules.escalate(ev.alert, threat, now())
	if source and (threat == "ram" or threat == "breachBegin" or threat == "breached" or threat == "blockade") then
		local t = now()
		if (heatAt[source] or 0) + 5 <= t then
			heatAt[source] = t
			S.Police.addHeat(source, CC.AttackHeat, "attacked a security convoy")
		end
	end
	if rose then
		local where = landmarkOf(ev.transport.rec.chassis.Position)
		if ev.alert.level == 1 then
			Comms.toastAll(string.format("Convoy security is alert near %s.", where), "warn")
		elseif ev.alert.level == 2 then
			Comms.cueAll("ConvoyAlert")
			Comms.toastAll(string.format("The convoy is under attack near %s. Harbour Security has called the police.", where), "alarm")
		end
		pushState()
	end
end

-- Cargo ---------------------------------------------------------------------------------------------
local function actorOf(player: Player, doors: BasePart)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return {
		alive = humanoid ~= nil and humanoid.Health > 0,
		jailed = player:GetAttribute("Jailed") == true,
		seated = humanoid ~= nil and humanoid.SeatPart ~= nil,
		distance = if root then (root.Position - doors.Position).Magnitude else math.huge,
	}
end

local function breachRefusal(player: Player): string?
	if not ev or not ev.transport then
		return "no convoy"
	end
	local doors = ev.transport.rec.model:FindFirstChild("CargoDoors")
	if not doors then
		return "no convoy"
	end
	return ConvoyRules.breachRefusal(CC, ev.cargo, actorOf(player, doors), ev.transport:speed(), now())
end

local function breachSeconds(): number
	return ConvoyRules.breachSeconds(CC, ConvoyService.ctx.services.Blackout.isGridDown())
end

local function escortsCanSee(root: BasePart): boolean
	if not ev then
		return false
	end
	local S = ConvoyService.ctx.services
	local range = CC.EscortViewRange * S.Police.visionScale()
	for _, v in ipairs(ev.vehicles) do
		local chassis = v.rec.chassis
		if chassis and chassis.Parent then
			local eye = CFrame.lookAt(chassis.Position + Vector3.new(0, 3.5, 0), root.Position)
			if S.Security.vision.canSee(eye, root, range, 360, v.rec.model) then
				return true
			end
		end
	end
	return false
end

local function completeBreach(player: Player)
	if not ev then
		return
	end
	local S = ConvoyService.ctx.services
	holds[player] = nil
	Comms.hud(player, { holdProgress = 0 })
	local why = breachRefusal(player)
	if why then
		Comms.toast(player, "Breach failed: " .. why .. ".", "warn")
		return
	end
	local values, weight = ConvoyRules.cargoFor(CC, CC.Storm, ev.variant)
	if not values then
		warn("[Convoy] cargo configuration rejected")
		return
	end
	if not ConvoyRules.claimCargo(ev.cargo, Comms.key(player), now()) then
		Comms.toast(player, "Breach failed: cargo already taken.", "warn")
		return
	end
	local doors = ev.transport.rec.model:FindFirstChild("CargoDoors")
	local behind = doors.Position - doors.CFrame.LookVector * 4 - Vector3.new(0, doors.Size.Y / 2 - 1, 0) -- LookVector points to the cab; crates land behind the truck
	ev.breachBlackout = S.Blackout.isGridDown()
	local ids = S.Loot.mintBundles(values, behind, "convoy:" .. ev.id, if ev.variant == "storm" then CC.Storm.CargoLabel else CC.CargoLabel, weight)
	ev.cargo.crates = ids
	local t = now()
	for _, id in ipairs(ids) do
		ev.crates[id] = { droppedSince = t, live = true }
	end
	ev.looseCount = #ids
	local crew = S.Crew.crewOf(player)
	if crew then
		S.Mission.minted(crew.id, ids, CC.CargoLabel)
		S.EventLog.crew(crew.id, string.format("%s breached the convoy near %s: %d crates", Comms.name(player), landmarkOf(doors.Position), #ids), "good")
	end
	ev.phase = "Breached"
	S.Telemetry.track("convoy_breach", { crates = #ids, blackout = S.Blackout.isGridDown() })
	escalate("breached", player)
	setCargoLight(Palette.SecurityRed)
	Comms.cueAt("ConvoyBreach", doors.Position, 3000)
	Comms.toastAll(string.format("The convoy has been breached near %s. %d crates are loose. Harbour Security will recover anything left behind.", landmarkOf(doors.Position), #ids), "alarm")
	Comms.toast(player, string.format("Doors open: %d crates. Get them to your pier. Police heat +%d.", #ids, CC.AttackHeat), "good")
	pushState()
end

local function onBreachBegin(player: Player, prompt: ProximityPrompt)
	local why = breachRefusal(player)
	if why then
		Comms.toast(player, "Can't breach: " .. why .. ".", "warn")
		return
	end
	holds[player] = { prompt = prompt, progress = 0 }
end

local function sealAfterInterrupt(player: Player)
	if not ev then
		return
	end
	ConvoyRules.sealDoors(CC, ev.cargo, now())
	if ev.cargo.state == "secured" then
		Comms.toast(player, string.format("The doors sealed for %d s.", CC.LockSeconds), "warn")
		pushState()
	end
end

local function onBreachHold(player: Player, prompt: ProximityPrompt, dt: number)
	local h = holds[player]
	if not h or h.prompt ~= prompt then
		return
	end
	if breachRefusal(player) then
		holds[player] = nil
		Comms.hud(player, { holdProgress = 0 })
		if h.progress > 0.5 then
			sealAfterInterrupt(player)
		end
		return
	end
	h.progress += math.clamp(dt, 0, 1)
	local need = breachSeconds()
	Comms.hud(player, { holdProgress = math.clamp(h.progress / need, 0, 1), holdText = "Breaching the cargo doors" })
	-- Observable threat: an escort that can see the breacher raises the alarm (heat follows)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and escortsCanSee(root) then
		escalate("breachBegin", player)
	end
	if h.progress >= need then
		completeBreach(player)
	end
end

local function onBreachEnded(player: Player)
	local h = holds[player]
	if h then
		holds[player] = nil
		Comms.hud(player, { holdProgress = 0 })
		if h.progress > 0.5 then
			sealAfterInterrupt(player)
		end
	end
end

-- PromptTriggered: only the server's own timer counts.
local function onBreachTriggered(player: Player, prompt: ProximityPrompt)
	local h = holds[player]
	if not h or h.prompt ~= prompt or h.progress < breachSeconds() - 0.35 then
		return
	end
	completeBreach(player)
end

-- Ramming -----------------------------------------------------------------------------------------
local function onTransportTouched(hit: BasePart)
	if not ev or not ev.transport then
		return
	end
	local t = now()
	if (ev.lastRamAt or 0) + 1.2 > t then
		return
	end
	local model = hit:FindFirstAncestorWhichIsA("Model")
	local vid = model and model:GetAttribute("VehicleId")
	if not vid or vid == ev.transport.rec.id then
		return
	end
	local Vehicle = ConvoyService.ctx.services.Vehicle
	local other = Vehicle.get(vid)
	if not other or other.npc then
		return
	end
	local rel = (ev.transport.rec.chassis.AssemblyLinearVelocity - other.chassis.AssemblyLinearVelocity).Magnitude
	if rel < CC.RamSpeed then
		return
	end
	ev.lastRamAt = t
	Vehicle.damage(ev.transport.rec.id, CC.RamDamage, "rammed")
	Vehicle.damage(vid, Config.Vehicles.RamDamage, "hit an armored transport")
	escalate("ram", other.driver)
end

-- Lifecycle -------------------------------------------------------------------------------------------
local function teardown(reason: string)
	if not ev then
		return
	end
	local S = ConvoyService.ctx.services
	local closing = ev
	ev = nil
	holds = {}
	loiter = {}
	for _, v in ipairs(closing.vehicles) do
		if v.touchConn then
			v.touchConn:Disconnect()
		end
		S.Vehicle.destroy(v.rec.id)
	end
	-- Loose crates nobody is carrying go back to Harbour Security; carried or stowed crates stay in play
	local recovered = 0
	for id, c in pairs(closing.crates) do
		local item = S.Loot.get(id)
		if c.live and item and item.state == "Dropped" then
			S.Loot.absorb(id, "recovered by Harbour Security")
			recovered += 1
		end
	end
	for p in pairs(heatAt) do
		heatAt[p] = nil
	end
	local msg
	if reason == "delivered" then
		msg = "The convoy reached its depot. The cargo is gone."
	elseif reason == "extracted" then
		msg = "Every crate from the convoy has been fenced or recovered."
	elseif reason == "expired" then
		msg = if recovered > 0 then string.format("Harbour Security recovered %d crate%s from the convoy.", recovered, if recovered == 1 then "" else "s") else "The convoy event is over."
	else
		msg = "The convoy was called off."
	end
	Comms.cueAll(if reason == "delivered" then "ConvoyDelivered" else "ConvoyLost")
	Comms.toastAll(msg, "info")
	Net.event("ConvoyState"):FireAllClients({ active = false, reason = reason })
	nextAutoAt = now() + CC.CooldownSeconds + CC.AutoScheduleSeconds + rng:NextNumber(0, CC.AutoScheduleJitterSeconds)
end

local function spawnVehicles()
	local S = ConvoyService.ctx.services
	local frames = spawnFrames(ev.route, CC.FormationGap)
	local waypoints = {}
	for _, wp in ipairs(ev.route.waypoints) do
		table.insert(waypoints, Vector3.new(wp.x, ROAD_Y, wp.z))
	end
	local kinds = { "Escort", "Armored", "Escort" }
	local models = {}
	local recs = {}
	for i, kind in ipairs(kinds) do
		local rec = S.Vehicle.spawn(kind, frames[i], { npc = true })
		-- Nobody drives a convoy vehicle away: seats are disabled for players
		for _, d in ipairs(rec.model:GetChildren()) do
			if d:IsA("VehicleSeat") or d:IsA("Seat") then
				d.Disabled = true
			end
		end
		table.insert(models, rec.model)
		table.insert(recs, rec)
	end
	ev.vehicles = {}
	for i, rec in ipairs(recs) do
		local driver = ConvoyDriver.new(ConvoyService.ctx, rec, Config.Vehicles[kinds[i]], waypoints, models)
		table.insert(ev.vehicles, driver)
	end
	ev.lead, ev.transport, ev.rear = ev.vehicles[1], ev.vehicles[2], ev.vehicles[3]
	local tr = ev.transport.rec
	ev.transport.touchConn = tr.chassis.Touched:Connect(onTransportTouched)
	local box = tr.model:FindFirstChild("CargoBox")
	if box then
		box.Touched:Connect(onTransportTouched)
	end
	local doors = tr.model:FindFirstChild("CargoDoors")
	if doors then
		Builder.prompt(doors, "Breach the doors", "Secured cargo · transport must be stopped", CC.BreachSeconds, "ConvoyBreach")
	end
	ev.phase = "Moving"
	Comms.toastAll(string.format("The armored convoy is rolling from %s.", landmarkOf(frames[2].Position)), "warn")
end

local pendingVariant = "standard"

local function begin(routeIndex: number?, skipAnticipation: boolean?, forceVariant: string?)
	local S = ConvoyService.ctx.services
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(players, { x = root.Position.X, z = root.Position.Z })
		end
	end
	-- Rare curated variant: a storm sends the convoy along the Seawall with one heavy sealed crate
	local variant = ConvoyRules.pickVariant(CC.Storm, S.Environment.state(), rng:NextNumber())
	if variant == "storm" and not routeIndex then
		routeIndex = ConvoyRules.routeIndexByName(Blueprint.ConvoyRoutes, CC.Storm.RouteName)
	end
	if forceVariant then
		variant = forceVariant
		if variant == "storm" and not routeIndex then
			routeIndex = ConvoyRules.routeIndexByName(Blueprint.ConvoyRoutes, CC.Storm.RouteName)
		end
	end
	pendingVariant = variant
	local idx = routeIndex or ConvoyRules.pickRoute(Blueprint.ConvoyRoutes, lastRouteIndex, players, CC.MinSpawnDistanceFromPlayers, function(n)
		return rng:NextInteger(1, n)
	end)
	local route = idx and Blueprint.ConvoyRoutes[idx]
	if not route then
		return false, "no route"
	end
	local previous = lastRouteIndex
	lastRouteIndex = idx -- onStart reads it
	local active, err = S.WorldEvent.trigger(EVENT, nil, { route = route.name })
	if not active then
		lastRouteIndex = previous
		return false, err
	end
	-- onStart (below) has created `ev`; apply the test shortcut after it ran
	if ev and skipAnticipation then
		ev.departAt = now()
	end
	return true, nil
end

local function onStart(active)
	eventCounter += 1
	local route = Blueprint.ConvoyRoutes[lastRouteIndex] or Blueprint.ConvoyRoutes[1]
	local t = now()
	ev = {
		id = string.format("%d_%d", eventCounter, math.floor(t)),
		route = route,
		vehicles = {},
		cargo = ConvoyRules.newCargo(),
		alert = ConvoyRules.newAlert(t),
		phase = "Departing",
		startedAt = t,
		departAt = t + CC.AnticipationSeconds,
		endsAt = active.endsAt,
		halts = {}, -- waypoint index -> until
		haltedAt = {}, -- waypoint index -> true once done
		crates = {},
		looseCount = 0,
		blockedSince = nil,
		crippled = false,
		strobePhase = false,
		lastPush = 0,
		lastPerception = 0,
		variant = pendingVariant,
		breachBlackout = false,
	}
	local a, b = route.waypoints[1], route.waypoints[#route.waypoints]
	Comms.cueAll("ConvoyAnnounce")
	Comms.toastAll(string.format("Harbour Security convoy leaving %s for %s in %d s. Secured cargo aboard.", Blueprint.nearestLandmark(a.x, a.z), Blueprint.nearestLandmark(b.x, b.z), CC.AnticipationSeconds), "warn")
	pushState()
end

local function finishIfResolved()
	if not ev then
		return
	end
	local S = ConvoyService.ctx.services
	if ev.cargo.state == "minted" then
		local loose, inPlay = 0, 0
		for id, c in pairs(ev.crates) do
			if c.live then
				local item = S.Loot.get(id)
				if not item then
					c.live = false
				else
					inPlay += 1
					if item.state == "Dropped" then
						loose += 1
					end
				end
			end
		end
		ev.looseCount = loose
		if inPlay == 0 then
			S.WorldEvent.cancel(EVENT, "extracted")
		end
	end
end

local function tickAbandonment(t: number)
	local S = ConvoyService.ctx.services
	for id, c in pairs(ev.crates) do
		if c.live then
			local item = S.Loot.get(id)
			if item and item.state == "Dropped" and ConvoyRules.abandoned(CC, c.droppedSince, t) then
				c.live = false
				S.Loot.absorb(id, "recovered by Harbour Security")
				Comms.toastAll("Harbour Security recovered an abandoned cargo crate.", "info")
			end
		end
	end
end

local function tickPerception(t: number)
	local S = ConvoyService.ctx.services
	local tr = ev.transport.rec.chassis
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and not player:GetAttribute("Jailed") then
			local d = (root.Position - tr.Position).Magnitude
			if d < CC.EscortViewRange * 1.2 and escortsCanSee(root) then
				if ev.alert.level >= 2 then
					S.Police.seen(player, t)
					S.Police.addHeat(player, CC.SeenHeatPerSecond * 0.5, "seen near the convoy")
				elseif d < 16 and S.Vehicle.vehicleOfPlayer(player) == nil then
					-- loitering on foot right by a halted or moving transport
					loiter[player] = (loiter[player] or 0) + 0.5
					if loiter[player] >= 2 then
						escalate("seen", nil)
					end
				else
					loiter[player] = nil
				end
			else
				loiter[player] = nil
			end
		end
	end
end

local function tick(dt: number)
	if not ev then
		return
	end
	local S = ConvoyService.ctx.services
	local t = now()
	if ev.phase == "Departing" then
		if t >= ev.departAt then
			spawnVehicles()
			pushState()
		end
		return
	end
	local tr = ev.transport
	-- Crippled: the transport stops for good once its health drops to the threshold
	if not ev.crippled and tr.rec.health <= Config.Vehicles.Armored.health * CC.CrippleFraction then
		ev.crippled = true
		ev.phase = "Crippled"
		escalate("crippled", nil)
		Comms.toastAll(string.format("The armored transport is crippled near %s.", landmarkOf(tr.rec.chassis.Position)), "alarm")
	end
	-- Planned checkpoint halts (skipped once engaged)
	local idx = tr:target()
	local halting = false
	if ConvoyRules.haltsAtCheckpoints(ev.alert) and not ev.testHalt then
		for _, c in ipairs(ev.route.checkpoints) do
			if idx == c + 1 and not ev.haltedAt[c] then
				-- just passed checkpoint c: hold here for the window
				ev.halts[c] = ev.halts[c] or (t + CC.CheckpointSeconds)
				if t < ev.halts[c] then
					halting = true
					if ev.phase ~= "Checkpoint" then
						ev.phase = "Checkpoint"
						Comms.toastAll(string.format("The convoy stopped at %s for a security check.", landmarkOf(tr.rec.chassis.Position)), "info")
						pushState()
					end
				else
					ev.haltedAt[c] = true
				end
			end
		end
	end
	local cruise = ConvoyRules.cruiseSpeed(CC, ev.alert, ev.crippled or ev.testHalt == true)
	local wantTransport = if halting then 0 else cruise
	-- Formation: lead ahead, rear behind; followers scale by their gap
	local leadGap = (ev.lead:position() - tr:position()).Magnitude
	local rearGap = (tr:position() - ev.rear:position()).Magnitude
	local leadSpeed = if wantTransport == 0 then 0 else cruise * (if leadGap > CC.FormationGap * 2 then 0.6 else 1)
	local transportSpeed = wantTransport * ConvoyRules.followFactor(leadGap, CC.FormationGap)
	local rearSpeed = (if wantTransport == 0 then 0 else cruise) * ConvoyRules.followFactor(rearGap, CC.FormationGap)
	local arrived = ev.lead:tick(dt, t, leadSpeed)
	tr:tick(dt, t, transportSpeed)
	ev.rear:tick(dt, t, rearSpeed)
	if not halting and not ev.crippled then
		ev.phase = if ev.cargo.state == "minted" then "Breached" else (if tr.blocked or ev.lead.blocked then "Halted" else "Moving")
	end
	-- Blocking by players: patience, then alert, then engaged
	if (tr.blocked or ev.lead.blocked) and wantTransport > 0 then
		ev.blockedSince = ev.blockedSince or t
		local blockedFor = t - ev.blockedSince
		if blockedFor > CC.BlockPatienceSeconds then
			escalate("block", nil)
			if blockedFor > CC.BlockPatienceSeconds + 1 and t >= ev.lead.reverseUntil and (ev.lastBackOut or 0) + 8 < t then
				ev.lastBackOut = t
				ev.lead.reverseUntil = t + 1.5
			end
		end
		if blockedFor > 20 then
			escalate("blockade", nil)
		end
	else
		ev.blockedSince = nil
	end
	-- Stuck for too long with nobody blocking: the convoy gives up and holds (still breachable)
	if tr.stuckTotal > CC.StuckGiveUpSeconds and not ev.crippled then
		ev.crippled = true
		ev.phase = "Halted"
		escalate("crippled", nil)
	end
	-- Delivered: the transport made it to the depot with the cargo secured
	if (arrived or tr.arrived) and ev.cargo.state == "secured" then
		ev.phase = "Delivered"
		S.WorldEvent.cancel(EVENT, "delivered")
		return
	end
	if t - ev.lastPerception >= 0.5 then
		ev.lastPerception = t
		tickPerception(t)
		setStrobes(ev.alert.level >= 1)
	end
	if t - ev.lastPush >= 1 then
		ev.lastPush = t
		tickAbandonment(t)
		finishIfResolved()
		if ev then
			pushState()
		end
	end
end

-- Loot events keep the crate bookkeeping honest (drops restart the abandonment clock)
local function onLootEvent(kind: string, data)
	if not ev or not data.item or type(data.item.origin) ~= "string" or data.item.origin ~= "convoy:" .. ev.id then
		return
	end
	local c = ev.crates[data.item.id]
	if not c then
		return
	end
	if kind == "drop" then
		c.droppedSince = now()
	elseif kind == "deliver" then
		c.live = false
		local S = ConvoyService.ctx.services
		if data.player then
			local crew = S.Crew.crewOf(data.player)
			S.Progression.award(data.player, "convoyCrate", data.item.id, crew and #crew.members or 1)
			S.Accomplishment.check("crateFenced", { variant = ev.variant, breachedDuringBlackout = ev.breachBlackout }, { data.player })
			if crew then
				S.Crew.note(crew.id, "convoy", data.value or 0, Comms.name(data.player) .. " fenced a " .. (if ev.variant == "storm" then "sealed harbour crate" else "convoy crate") .. " for " .. tostring(data.value or 0))
			end
		end
		S.Telemetry.track("convoy_crate_fenced", { value = data.value or 0 })
		if data.crewId then
			S.EventLog.crew(data.crewId, string.format("%s fenced a convoy crate: +%d", Comms.name(data.player), data.value or 0), "good")
		end
	elseif kind == "absorbed" then
		c.live = false
	end
end

-- Public API -------------------------------------------------------------------------------------------
-- Partial intel for the deck mechanic: seconds until the next auto-scheduled convoy (nil while one runs)
function ConvoyService.secondsUntilNext(): number?
	if ev then
		return nil
	end
	return math.max(0, nextAutoAt - now())
end

function ConvoyService.isActive(): boolean
	return ev ~= nil
end

function ConvoyService.snapshot()
	return snapshot()
end

-- Engine-test helpers (same validation as live play) --------------------------------------------------
function ConvoyService.testStart(routeIndex: number?, variant: string?): boolean
	local ok = begin(routeIndex, true, variant)
	return ok == true
end

function ConvoyService.testHalt(on: boolean)
	if ev then
		ev.testHalt = on
	end
end

function ConvoyService.testHold(player: Player): boolean
	if not ev or not ev.transport then
		return false
	end
	local doors = ev.transport.rec.model:FindFirstChild("CargoDoors")
	local prompt = doors and doors:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return false
	end
	onBreachBegin(player, prompt)
	if not holds[player] then
		return false
	end
	local before = ev.cargo.state
	local t0 = os.clock()
	while holds[player] and os.clock() - t0 < breachSeconds() + 2 do
		task.wait(0.25)
		onBreachHold(player, prompt, 0.25)
	end
	return before == "secured" and ev ~= nil and ev.cargo.state == "minted" and ev.cargo.by == Comms.key(player)
end

function ConvoyService.testCrates()
	if not ev then
		return { ids = {}, total = 0 }
	end
	local S = ConvoyService.ctx.services
	local total = 0
	for _, id in ipairs(ev.cargo.crates) do
		local item = S.Loot.get(id)
		total += item and item.value or 0
	end
	return { ids = table.clone(ev.cargo.crates), total = total, phase = ev.phase, alert = ev.alert.level }
end

function ConvoyService.testVehicles(): number
	local n = 0
	for _, rec in pairs(ConvoyService.ctx.services.Vehicle.all()) do
		if rec.kind == "Armored" or rec.kind == "Escort" then
			n += 1
		end
	end
	return n
end

function ConvoyService.testEnd()
	ConvoyService.ctx.services.WorldEvent.cancel(EVENT, "cancelled")
end

function ConvoyService.init(ctx)
	ConvoyService.ctx = ctx
end

function ConvoyService.start()
	local S = ConvoyService.ctx.services
	S.WorldEvent.register(ConvoyRules.definition(CC), {
		label = "ARMORED CONVOY",
		onStart = onStart,
		onEnd = function(_active, reason)
			teardown(reason)
		end,
	})
	S.Interaction.register("ConvoyBreach", onBreachTriggered)
	S.Interaction.registerHold("ConvoyBreach", { begin = onBreachBegin, hold = onBreachHold, ended = onBreachEnded })
	S.Loot.onEvent(onLootEvent)
	nextAutoAt = now() + CC.AutoScheduleSeconds
	loop = task.spawn(function()
		local last = now()
		local sched = 0
		while true do
			task.wait(0.1)
			local t = now()
			local dt = math.clamp(t - last, 0, 0.5)
			last = t
			if ev then
				local ok, err = pcall(tick, dt)
				if not ok then
					warn("[Convoy] tick failed: " .. tostring(err))
				end
			elseif t - sched >= 10 then
				sched = t
				if t >= nextAutoAt and #Players:GetPlayers() >= CC.MinPlayersToSchedule and S.WorldEvent.canStart(EVENT) then
					begin(nil, false)
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		Net.event("ConvoyState"):FireClient(player, snapshot())
	end)
	Players.PlayerRemoving:Connect(function(player)
		holds[player] = nil
		loiter[player] = nil
		heatAt[player] = nil
	end)
	game:BindToClose(function()
		if loop then
			task.cancel(loop)
			loop = nil
		end
		if ev then
			S.WorldEvent.cancel(EVENT, "shutdown")
		end
	end)
end

return ConvoyService
