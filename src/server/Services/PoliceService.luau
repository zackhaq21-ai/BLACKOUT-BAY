--!nonstrict
-- Police attention (heat), NPC cruiser fallback, arrests, the jail and prison breaks.
-- Player-controlled police are planned (see docs/STATUS.md); this milestone runs the NPC fallback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Heat = require(ReplicatedStorage.Shared.Core.Heat)
local RoadGraph = require(ReplicatedStorage.Shared.Core.RoadGraph)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Rig = require(script.Parent.Parent.NPC.Rig)
local CopBrain = require(script.Parent.Parent.NPC.CopBrain)
local Comms = require(script.Parent.Comms)

local PoliceService = { ctx = nil :: any }

local heat
local cops = {}
local jailed = {} -- Player -> { until = number }
local station
local graph
local barricadeActive = false
local wantedSince = {} -- key -> time the player first became wanted
local doorOpenToken = 0

local function now()
	return os.clock()
end

function PoliceService.init(ctx)
	PoliceService.ctx = ctx
	station = ctx.world.island.station
	heat = Heat.new({
		heatPerLevel = Config.Police.HeatPerLevel,
		maxHeat = Config.Police.MaxHeat,
		decayPerSecond = Config.Police.HeatDecayPerSecond,
		unseenGrace = Config.Police.UnseenGraceSeconds,
		recognitionSeconds = Config.Police.VehicleRecognitionSeconds,
	})
	graph = RoadGraph.new(Blueprint.Roads)
	heat:onLevelChange(function(key, from, to, reason)
		local p = Players:GetPlayerByUserId(tonumber(key) or 0)
		if p then
			Net.event("Heat"):FireClient(p, { heat = heat:heatOf(key), level = to, label = Heat.Labels[to], reason = reason })
			if to > from then
				Comms.toast(p, "Police attention: " .. Heat.Labels[to] .. (if reason then " (" .. reason .. ")" else ""), "alarm")
				if to >= 1 then
					Comms.cue(p, "Siren")
				end
			elseif to == 0 then
				Comms.toast(p, "You lost them. Police attention cleared.", "good")
			end
			p:SetAttribute("HeatLevel", to)
		end
		if from == 0 and to > 0 then
			wantedSince[key] = now()
		elseif to == 0 then
			wantedSince[key] = nil
		end
	end)
	Builder.prompt(station.cellDoor, "Pick the lock", string.format("Cell door (%d s)", Config.Police.JailLockpickSeconds), Config.Police.JailLockpickSeconds, "Lockpick")
	Builder.prompt(station.releaseSwitch, "Release prisoners", "Cell release (the desk sergeant will see you)", 1, "CellRelease")
end

-- Heat API ---------------------------------------------------------------------------------
function PoliceService.addHeat(player: Player, amount: number, reason: string)
	heat:add(Comms.key(player), amount, reason, now())
end

function PoliceService.heatLevel(player: Player): number
	return heat:levelOf(Comms.key(player))
end

function PoliceService.seen(player: Player, t: number)
	heat:seen(Comms.key(player), t)
end

function PoliceService.wanted(): { string }
	return heat:wanted()
end

function PoliceService.recognizeVehicle(vehicleId: string)
	local rec = PoliceService.ctx.services.Vehicle.get(vehicleId)
	if rec and not heat:isVehicleRecognized(vehicleId, now()) and rec.driver then
		Comms.toast(rec.driver, "Police have your " .. rec.label .. "'s plate. Swap cars or lose them.", "alarm")
	end
	heat:recognizeVehicle(vehicleId, now())
	if rec then
		rec.model:SetAttribute("Recognized", true)
	end
end

function PoliceService.isVehicleRecognized(vehicleId: string): boolean
	return heat:isVehicleRecognized(vehicleId, now())
end

function PoliceService.cuffing(player: Player, progress: number)
	Comms.hud(player, { cuffing = math.clamp(progress, 0, 1) })
end

-- Jail -------------------------------------------------------------------------------------
function PoliceService.isJailed(player: Player): boolean
	return jailed[player] ~= nil
end

function PoliceService.placeInCell(player: Player)
	local char = player.Character
	if char and char.PrimaryPart then
		local cell = station.cellSpawns[math.random(1, #station.cellSpawns)]
		PoliceService.ctx.services.Movement.relocate(player, cell)
	end
end

local function openCellDoor(seconds: number)
	doorOpenToken += 1
	local token = doorOpenToken
	station.cellDoor.CanCollide = false
	station.cellDoor.Transparency = 0.7
	station.cellDoor.Color = Palette.SeaGlass
	task.delay(seconds, function()
		if token == doorOpenToken then
			station.cellDoor.CanCollide = true
			station.cellDoor.Transparency = 0
			station.cellDoor.Color = Palette.SecurityRed
		end
	end)
end

function PoliceService.release(player: Player, how: string)
	if not jailed[player] then
		return
	end
	jailed[player] = nil
	player:SetAttribute("Jailed", nil)
	Net.event("Jail"):FireClient(player, { state = "free", how = how })
	Comms.toast(player, "You're out (" .. how .. "). Heat is clear; don't get seen.", "good")
	PoliceService.ctx.services.Mission.memberReleased(player)
	local char = player.Character
	if char and char.PrimaryPart then
		PoliceService.ctx.services.Movement.relocate(player, station.entrance)
	end
end

function PoliceService.arrest(player: Player, byLabel: string, where: string)
	if jailed[player] or not player.Parent then
		return
	end
	local Loot = PoliceService.ctx.services.Loot
	local Security = PoliceService.ctx.services.Security
	local dropped = Loot.dropAll(player, "arrested")
	Security.clearKeycards(player)
	heat:clear(Comms.key(player), "arrested")
	player:SetAttribute("HeatLevel", 0)
	Comms.hud(player, { cuffing = 0 })
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
	jailed[player] = { until_ = now() + Config.Police.JailAutoReleaseSeconds }
	player:SetAttribute("Jailed", true)
	PoliceService.ctx.services.Economy.bumpStat(player, "arrests", 1)
	PoliceService.ctx.services.Mission.memberArrested(player, dropped, where)
	task.defer(PoliceService.placeInCell, player)
	Comms.cue(player, "Arrest")
	Comms.toast(player, string.format("Arrested by %s at %s. Pick the cell lock (%d s), wait for release (%d s), or have a crewmate hit the lobby switch.", byLabel, where, Config.Police.JailLockpickSeconds, Config.Police.JailAutoReleaseSeconds), "alarm")
	Net.event("Jail"):FireClient(player, { state = "jailed", secondsLeft = Config.Police.JailAutoReleaseSeconds, where = where, by = byLabel })
	local crew = PoliceService.ctx.services.Crew.crewOf(player)
	if crew then
		for _, p in ipairs(crew.members) do
			if p ~= player then
				Comms.toast(p, Comms.name(player) .. " was arrested at " .. where .. ". The cell release is in the police station lobby.", "alarm")
			end
		end
	end
end

function PoliceService.onLockpick(player: Player)
	if not jailed[player] then
		Comms.toast(player, "You're not locked in.", "info")
		return
	end
	openCellDoor(6)
	PoliceService.release(player, "picked the lock")
end

function PoliceService.onCellRelease(player: Player)
	local freed = 0
	for p in pairs(jailed) do
		if p ~= player then
			PoliceService.release(p, "released by " .. Comms.name(player))
			freed += 1
		end
	end
	openCellDoor(8)
	if freed == 0 then
		Comms.toast(player, "The cells are empty.", "info")
		return
	end
	-- The desk sergeant sees it: heat for the one who pulled the switch
	PoliceService.addHeat(player, 60, "seen freeing prisoners")
	PoliceService.ctx.services.Mission.note(player, "released " .. freed .. " prisoner(s) from the station")
end

-- Barricade at Lantern Cross when anyone reaches the configured heat level
local function updateBarricade()
	local needed = false
	for _, key in ipairs(heat:wanted()) do
		if heat:levelOf(key) >= Config.Police.BarricadeHeatLevel then
			needed = true
			break
		end
	end
	if needed and not barricadeActive then
		barricadeActive = true
		local sent = 0
		for _, cop in ipairs(cops) do
			if sent < 2 and not cop.target then
				local off = if sent == 0 then Vector3.new(-6, 0, 0) else Vector3.new(6, 0, 0)
				cop.barricadeAt = Vector3.new(Blueprint.Barricade.x, 0, Blueprint.Barricade.z) + off
				sent += 1
			end
		end
		Comms.toastAll("Police are blocking Lantern Cross.", "alarm")
	elseif not needed and barricadeActive then
		barricadeActive = false
		for _, cop in ipairs(cops) do
			cop.barricadeAt = nil
		end
	end
end

-- Dispatcher: after the response delay, up to maxPursuers cruisers go active; the rest stay parked.
local function dispatch()
	local diff = Config.Police.Difficulty[Config.Police.NpcDifficulty] or Config.Police.Difficulty.Medium
	local t = now()
	local due = false
	local focus = nil
	for key, since in pairs(wantedSince) do
		if t - since >= diff.responseSeconds then
			due = true
			local p = Players:GetPlayerByUserId(tonumber(key) or 0)
			local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and not focus then
				focus = root.Position
			end
		end
	end
	if not due then
		for _, cop in ipairs(cops) do
			cop.active = false
		end
		return
	end
	local activeCount = 0
	for _, cop in ipairs(cops) do
		if cop.active then
			activeCount += 1
		end
	end
	if activeCount >= diff.maxPursuers then
		return
	end
	-- Activate the cruisers nearest the first wanted player
	local idle = {}
	for _, cop in ipairs(cops) do
		if not cop.active and not cop.barricadeAt then
			table.insert(idle, cop)
		end
	end
	table.sort(idle, function(a, b)
		local ref = focus or Vector3.zero
		return (a:position() - ref).Magnitude < (b:position() - ref).Magnitude
	end)
	for i = 1, math.min(#idle, diff.maxPursuers - activeCount) do
		idle[i].active = true
	end
end

function PoliceService.start()
	local Vehicle = PoliceService.ctx.services.Vehicle
	local pads = station.cruiserPads
	for i = 1, math.min(Config.Police.NpcFallbackCount, #pads) do
		local rec = Vehicle.spawn("Cruiser", pads[i], { npc = true })
		table.insert(cops, CopBrain.new(PoliceService.ctx, rec, i, graph))
	end
	Rig.create("DeskSergeant", Palette.Police, "Desk Sergeant", PoliceService.ctx.world.npcFolder, station.lobbyPost)
	task.spawn(function()
		local last = now()
		while true do
			task.wait(0.1)
			local t = now()
			local dt = t - last
			last = t
			heat:step(dt, t)
			for _, cop in ipairs(cops) do
				cop:tick(dt, t)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			dispatch()
			updateBarricade()
			for p, j in pairs(jailed) do
				local left = math.ceil(j.until_ - now())
				if left <= 0 then
					openCellDoor(6)
					PoliceService.release(p, "time served")
				else
					Net.event("Jail"):FireClient(p, { state = "jailed", secondsLeft = left })
				end
			end
			for _, p in ipairs(Players:GetPlayers()) do
				local key = Comms.key(p)
				if heat:heatOf(key) > 0 then
					Net.event("Heat"):FireClient(p, { heat = heat:heatOf(key), level = heat:levelOf(key), label = Heat.Labels[heat:levelOf(key)] })
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		jailed[player] = nil
		heat:remove(Comms.key(player))
	end)
end

return PoliceService
