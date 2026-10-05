--!nonstrict
-- Aurora Exchange security: guards, cameras, alarm levels, shutters, dock keypad, vault readers and drill,
-- keycards, junction box and the restock cycle. SecurityState (pure) decides the level; this service
-- renders it in the world and tells players why.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Net = require(ReplicatedStorage.Shared.Net)
local SecurityState = require(ReplicatedStorage.Shared.Core.SecurityState)
local Builder = require(script.Parent.Parent.Builders.Builder)
local GuardBrain = require(script.Parent.Parent.NPC.GuardBrain)
local Comms = require(script.Parent.Comms)

local SecurityService = { ctx = nil :: any }

local museum
local security
local guards = {}
local cameras = {}
local dockCode = "0000"
local wrongCodeStreak = {}
local restock = { last = 0, pending = nil }
local vaultOpen = false
local swipes = {} -- readerName -> time
local alarmLoop = nil
local officeCardModel = nil
local listeners = {}
local alarmOrigin = nil
local camerasWereActive = nil
local guardVisionScale = 1
local visionFactors: { [string]: number } = {} -- source -> factor (blackout, weather); product is applied
local junctionCutUntil = 0
local gridPowerOff = false
local lastNoiseAt = {} -- key -> time (throttle noise reports from held prompts)
local frozen = false -- engine tests freeze guards and cameras to isolate rules

local function now()
	return os.clock()
end

function SecurityService.onLevelChange(fn)
	table.insert(listeners, fn)
end

function SecurityService.level(): number
	return security.level
end

function SecurityService.state()
	return security
end

-- Vision helpers shared with guards and cameras ------------------------------------------------
local function playerRoot(player: Player): BasePart?
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function insideMuseum(pos: Vector3): boolean
	local b = museum.bounds
	return pos.X >= b.minX and pos.X <= b.maxX and pos.Z >= b.minZ and pos.Z <= b.maxZ and pos.Y < b.maxY
end

local function nearMuseum(pos: Vector3): boolean
	local b = museum.bounds
	return pos.X >= b.minX - 60 and pos.X <= b.maxX + 60 and pos.Z >= b.minZ - 70 and pos.Z <= b.maxZ + 110
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function canSee(eye: CFrame, targetRoot: BasePart, viewDistance: number, viewAngle: number, selfModel: Instance?): boolean
	local toTarget = targetRoot.Position - eye.Position
	local dist = toTarget.Magnitude
	if dist > viewDistance or dist < 0.01 then
		return false
	end
	local dir = toTarget.Unit
	local cosHalf = math.cos(math.rad(viewAngle / 2))
	if eye.LookVector:Dot(dir) < cosHalf then
		return false
	end
	local exclude = { SecurityService.ctx.world.lootFolder, SecurityService.ctx.world.npcFolder }
	if selfModel then
		table.insert(exclude, selfModel)
	end
	rayParams.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(eye.Position, toTarget, rayParams)
	if not result then
		return true
	end
	return result.Instance:IsDescendantOf(targetRoot.Parent)
end

SecurityService.vision = {
	playerRoot = playerRoot,
	insideOrNear = nearMuseum,
	canSee = canSee,
	onSeen = function(player, observer, value)
		Net.event("Detection"):FireClient(player, { level = value, source = observer.label, x = observer:position().X, z = observer:position().Z })
	end,
	detain = function(player, guard)
		SecurityService.ctx.services.Police.arrest(player, guard.label, "the Aurora Exchange")
	end,
	isJailed = function(player)
		return player:GetAttribute("Jailed") == true
	end,
	alarmOrigin = function()
		return alarmOrigin
	end,
	viewScale = function()
		return guardVisionScale
	end,
}

-- World effects ------------------------------------------------------------------------------
local function tween(part: BasePart, props, seconds: number)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function setShutter(down: boolean)
	local s = museum.frontShutter
	if down then
		s.CanCollide = true
		tween(s, { Transparency = 0 }, 0.8)
	else
		s.CanCollide = false
		tween(s, { Transparency = 1 }, 0.8)
	end
	s:SetAttribute("Down", down)
end

local function setDockDoor(open: boolean)
	local d = museum.dockDoor
	local closedCF = d:GetAttribute("ClosedCFrame") or d.CFrame
	if not d:GetAttribute("ClosedCFrame") then
		d:SetAttribute("ClosedCFrame", d.CFrame)
	end
	if open then
		d.CanCollide = false
		tween(d, { CFrame = closedCF * CFrame.new(0, 9, 0) }, 1)
	else
		d.CanCollide = true
		tween(d, { CFrame = closedCF }, 1)
	end
	d:SetAttribute("Open", open)
end

local dockCloseToken = 0
local function openDockTemporarily(seconds: number)
	dockCloseToken += 1
	local token = dockCloseToken
	setDockDoor(true)
	task.delay(seconds, function()
		if token == dockCloseToken then
			setDockDoor(false)
		end
	end)
end

local function setVault(open: boolean)
	local d = museum.vaultDoor
	if not d:GetAttribute("ClosedCFrame") then
		d:SetAttribute("ClosedCFrame", d.CFrame)
	end
	local closedCF = d:GetAttribute("ClosedCFrame")
	vaultOpen = open
	if open then
		d.CanCollide = false
		tween(d, { CFrame = closedCF * CFrame.new(0, -9.5, 0) }, 2.5)
	else
		d.CanCollide = true
		tween(d, { CFrame = closedCF }, 2.5)
	end
	d:SetAttribute("Open", open)
end

local function setCameras(active: boolean)
	for _, cam in ipairs(cameras) do
		cam.lens.Color = if active then Palette.SecurityRed else Palette.Night
		cam.lens.Material = if active then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function setAlarmVisuals(on: boolean)
	if on and not alarmLoop then
		alarmLoop = task.spawn(function()
			local phase = false
			while true do
				phase = not phase
				for _, l in ipairs(museum.alarmLights) do
					l.part.Color = if phase then Palette.SecurityRed else Palette.Night
					l.light.Brightness = if phase then 3 else 0
				end
				task.wait(0.5)
			end
		end)
		if museum.sign then
			museum.sign.Color = Palette.SecurityRed
		end
	elseif not on and alarmLoop then
		task.cancel(alarmLoop)
		alarmLoop = nil
		for _, l in ipairs(museum.alarmLights) do
			l.part.Color = Palette.Night
			l.light.Brightness = 0
		end
		if museum.sign then
			museum.sign.Color = Palette.SeaGlass
		end
	end
end

local function playersNearMuseum(): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = playerRoot(p)
		if root and (root.Position - Vector3.new(museum.bounds.minX + 120, 0, museum.bounds.minZ + 100)).Magnitude < 400 then
			table.insert(out, p)
		end
	end
	return out
end

local function onLevelChanged(level: number, reason: string?, playerKey: string?)
	local label = SecurityState.Labels[level]
	Net.event("SecurityLevel"):FireAllClients({ level = level, label = label, reason = reason })
	if level >= 2 then
		setAlarmVisuals(true)
		Comms.cueAll("Alarm")
		local who = playerKey and Players:GetPlayerByUserId(tonumber(playerKey) or 0)
		local whoRoot = who and playerRoot(who)
		alarmOrigin = if whoRoot then whoRoot.Position else alarmOrigin
		Comms.toastMany(playersNearMuseum(), "AURORA EXCHANGE ALARM — " .. tostring(reason), "alarm")
		-- Everyone inside the building now has police attention
		local Police = SecurityService.ctx.services.Police
		for _, p in ipairs(Players:GetPlayers()) do
			local root = playerRoot(p)
			if root and insideMuseum(root.Position) then
				Police.addHeat(p, Config.Police.AlarmHeat, "inside the Aurora Exchange when the alarm tripped")
			end
		end
	elseif level == 1 then
		Comms.cueMany(playersNearMuseum(), "Suspicious")
		local who = playerKey and Players:GetPlayerByUserId(tonumber(playerKey) or 0)
		if who then
			Comms.toast(who, tostring(reason) .. " — get out of sight.", "warn")
		end
	end
	if level == 3 then
		if not security:powerCutActive(now()) then
			setShutter(true)
		end
		dockCloseToken += 1
		setDockDoor(false)
		Comms.cueAll("Lockdown")
		Comms.toastMany(playersNearMuseum(), "LOCKDOWN — front shutter down, dock sealed. Roof is open; cutting the power lifts the shutter.", "alarm")
	end
	if level == 0 then
		setAlarmVisuals(false)
		setShutter(false)
		alarmOrigin = nil
		Comms.toastMany(playersNearMuseum(), "Aurora Exchange security has stood down.", "info")
	elseif level < 3 and museum.frontShutter:GetAttribute("Down") then
		setShutter(false)
	end
	for _, fn in ipairs(listeners) do
		task.spawn(fn, level, reason, playerKey)
	end
end

-- Codes, cards ---------------------------------------------------------------------------------
local function newCode()
	local rng = Random.new()
	local digits = {}
	for _ = 1, Config.Museum.CodeLength do
		table.insert(digits, tostring(rng:NextInteger(0, 9)))
	end
	dockCode = table.concat(digits)
	local gui = museum.codeBoard:FindFirstChild("Label")
	local tl = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
	if tl then
		tl.Text = "DELIVERIES\nDOCK CODE\n" .. dockCode
	end
end

local function placeOfficeCard()
	if officeCardModel then
		officeCardModel:Destroy()
	end
	local card = Builder.part(museum.model, museum.officeCardSpot, Vector3.new(1.6, 0.1, 1), { name = "OfficeKeycard", material = Enum.Material.SmoothPlastic, color = Palette.SeaGlass })
	Builder.label(card, "ID", Enum.NormalId.Top, Palette.Night)
	Builder.prompt(card, "Take keycard", "Office keycard (vault reader)", 0.5, "OfficeCard")
	officeCardModel = card
end

function SecurityService.clearKeycards(player: Player)
	player:SetAttribute("KeycardOffice", nil)
	player:SetAttribute("KeycardCaptain", nil)
	Comms.hud(player, { keycards = {} })
end

local function keycardList(player: Player): { string }
	local out = {}
	if player:GetAttribute("KeycardOffice") then
		table.insert(out, "Office")
	end
	if player:GetAttribute("KeycardCaptain") then
		table.insert(out, "Captain")
	end
	return out
end

-- Noise: short loud events and continuous held actions
function SecurityService.noise(label: string, player: Player?)
	security:noise(label, player and tostring(player.UserId) or nil, now())
end

-- Guards within radius "hear" the action: counts as partial exposure per second.
function SecurityService.noiseAt(position: Vector3, radius: number, player: Player, label: string, perSecond: number, dt: number)
	for _, g in ipairs(guards) do
		if (g:position() - position).Magnitude <= radius then
			local v = security:report(g.id, g.label .. " (heard " .. label .. ")", tostring(player.UserId), dt * perSecond / Config.Museum.SuspicionFillPerSecond, false, now())
			g.lastKnown = position
			g.lastSeenAt = now()
			Net.event("Detection"):FireClient(player, { level = v, source = g.label, x = g:position().X, z = g:position().Z })
		end
	end
end

-- Restock ------------------------------------------------------------------------------------
local restockSeed = 0
function SecurityService.restock()
	restockSeed += 1
	local Loot = SecurityService.ctx.services.Loot
	Loot.restockMuseum(os.time() + restockSeed)
	security:reset(now())
	setVault(false)
	setDockDoor(false)
	setShutter(false)
	for _, d in ipairs(museum.frontDoors) do
		d.Transparency = 0.3
		d.CanCollide = true
		d:SetAttribute("Smashed", false)
	end
	for _, c in ipairs(museum.model:GetChildren()) do
		if c.Name == "DoorShard" then
			c:Destroy()
		end
	end
	newCode()
	placeOfficeCard()
	for _, g in ipairs(guards) do
		g:reset()
	end
	for _, p in ipairs(Players:GetPlayers()) do
		SecurityService.clearKeycards(p)
	end
	swipes = {}
	wrongCodeStreak = {}
	restock.last = now()
	restock.pending = nil
	Comms.toastAll("The Aurora Exchange has restocked. The vault is sealed and the dock code has changed.", "info")
	Net.event("HudState"):FireAllClients({ museumStocked = true })
end

local function coreTaken(): boolean
	local Loot = SecurityService.ctx.services.Loot
	local core = Loot.coreItemId and Loot.get(Loot.coreItemId)
	return core == nil or core.state ~= "InCase"
end

local function tickRestock()
	local Loot = SecurityService.ctx.services.Loot
	local t = now()
	local empty = Loot.museumStockRemaining() == 0 and coreTaken()
	local expired = t - restock.last > Config.Museum.RestockCycleSeconds
	if (empty or expired) and not restock.pending then
		restock.pending = t + Config.Museum.RestockDelaySeconds
		Comms.toastAll("Aurora Exchange: restock in " .. Config.Museum.RestockDelaySeconds .. " s.", "info")
	end
	if restock.pending and t >= restock.pending then
		local occupied = false
		for _, p in ipairs(Players:GetPlayers()) do
			local root = playerRoot(p)
			if root and insideMuseum(root.Position) then
				occupied = true
				break
			end
		end
		if not occupied or t >= restock.pending + 300 then
			SecurityService.restock()
		end
	end
end

-- Cameras ------------------------------------------------------------------------------------
local function tickCameras(dt: number, t: number)
	local active = security:camerasActive(t)
	for i, cam in ipairs(cameras) do
		local sweep = math.rad(Config.Museum.CameraSweepDegrees / 2) * math.sin(t * (2 * math.pi / Config.Museum.CameraSweepSeconds) + i)
		local cf = cam.baseCFrame * CFrame.Angles(0, sweep, 0)
		cam.part.CFrame = cf
		cam.lens.CFrame = cf * CFrame.new(0, 0, -1.6)
		if active then
			for _, player in ipairs(Players:GetPlayers()) do
				local root = playerRoot(player)
				if root and insideMuseum(root.Position) and canSee(cf, root, Config.Museum.CameraViewDistance, Config.Museum.CameraViewAngle, nil) then
					local v = security:report("cam_" .. cam.id, cam.label, tostring(player.UserId), dt, player:GetAttribute("Sneaking") == true, t)
					Net.event("Detection"):FireClient(player, { level = v, source = cam.label, x = cf.Position.X, z = cf.Position.Z })
				end
			end
		end
	end
	if camerasWereActive ~= active then
		camerasWereActive = active
		setCameras(active)
	end
end

-- Interactions -------------------------------------------------------------------------------
local function playerPos(player: Player): Vector3?
	local root = playerRoot(player)
	return root and root.Position or nil
end

function SecurityService.onFrontSmash(player: Player)
	if museum.frontShutter:GetAttribute("Down") then
		Comms.toast(player, "The shutter is down. Cut the power or find another way.", "warn")
		return
	end
	if museum.frontDoors[1]:GetAttribute("Smashed") then
		return
	end
	for _, d in ipairs(museum.frontDoors) do
		d.Transparency = 0.85
		d.CanCollide = false
		d:SetAttribute("Smashed", true)
		local pp = d:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp:Destroy()
		end
		for i = 1, 3 do
			Builder.part(museum.model, d.CFrame * CFrame.new(math.random(-4, 4), -5, math.random(1, 4)) * CFrame.Angles(0, i, 0), Vector3.new(1.5, 0.1, 1), { name = "DoorShard", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.4, canCollide = false })
		end
	end
	Comms.cueAt("Smash", museum.frontDoors[1].Position, 3000)
	SecurityService.noise("Front doors smashed by " .. Comms.name(player), player)
	SecurityService.ctx.services.Police.addHeat(player, Config.Police.AlarmHeat, "smashed the museum doors")
end

function SecurityService.onKeypadOpen(player: Player)
	if security.level >= 3 and not security:powerCutActive(now()) then
		Comms.toast(player, "Keypad dead: lockdown. Cut the power to wake it.", "warn")
		return
	end
	Net.event("OpenKeypad"):FireClient(player, { targetId = "dock", digits = Config.Museum.CodeLength })
end

function SecurityService.onKeypadSubmit(player: Player, targetId: string, code: string)
	if targetId ~= "dock" or type(code) ~= "string" then
		return
	end
	local pos = playerPos(player)
	if not pos or (pos - museum.dockKeypad.Position).Magnitude > 12 then
		return
	end
	if security.level >= 3 and not security:powerCutActive(now()) then
		Comms.toast(player, "Keypad dead: lockdown.", "warn")
		return
	end
	if code == dockCode then
		wrongCodeStreak[player] = nil
		Comms.cue(player, "Unlock")
		Comms.toast(player, "Dock door open for 25 s.", "good")
		openDockTemporarily(25)
		Net.event("CloseKeypad"):FireClient(player)
	else
		wrongCodeStreak[player] = (wrongCodeStreak[player] or 0) + 1
		Comms.cue(player, "Keypad")
		if wrongCodeStreak[player] >= 3 then
			wrongCodeStreak[player] = 0
			Net.event("CloseKeypad"):FireClient(player)
			SecurityService.noise("Keypad tamper alarm at the loading dock", player)
		else
			Comms.toast(player, "Wrong code (" .. wrongCodeStreak[player] .. "/3). The code is on the security office board.", "warn")
		end
	end
end

function SecurityService.onDockRelease(player: Player)
	if security.level >= 3 and not security:powerCutActive(now()) then
		Comms.toast(player, "Sealed: lockdown.", "warn")
		return
	end
	openDockTemporarily(25)
	Comms.cue(player, "Unlock")
end

-- Dim the interior while the power is out (junction box or harbour blackout)
local function setInteriorLights(on: boolean)
	for _, c in ipairs(museum.model:GetChildren()) do
		if c.Name == "CeilingLight" then
			c.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local l = c:FindFirstChildOfClass("PointLight")
			if l then
				l.Brightness = if on then 1.1 else 0.2
			end
		end
	end
end

-- Harbour grid (BlackoutService). Off: cameras dead, shutter lifted, interior dark for `seconds`.
-- On: power returns unless a junction-box cut is still running; idempotent.
function SecurityService.setGridPower(on: boolean, seconds: number)
	local t = now()
	if not on then
		if gridPowerOff then
			return
		end
		gridPowerOff = true
		security:cutPower(t, math.max(1, seconds))
		setShutter(false)
		setInteriorLights(false)
		return
	end
	if not gridPowerOff then
		return
	end
	gridPowerOff = false
	security.powerCutUntil = math.max(junctionCutUntil, 0)
	if not security:powerCutActive(t) then
		setInteriorLights(true)
		if security.level >= 3 then
			setShutter(true)
		end
	end
end

-- Several sources (blackout, weather) each contribute a factor; guards see the product, floored so they never go blind.
function SecurityService.setVisionFactor(source: string, scale: number)
	visionFactors[source] = math.clamp(if scale ~= scale then 1 else scale, 0.25, 1)
	local product = 1
	for _, f in pairs(visionFactors) do
		product *= f
	end
	guardVisionScale = math.clamp(product, 0.25, 1)
end

function SecurityService.guardVisionScale(): number
	return guardVisionScale
end

function SecurityService.camerasActive(): boolean
	return security:camerasActive(now())
end

function SecurityService.onJunctionBox(player: Player)
	local t = now()
	local readyAt = museum.junctionBox:GetAttribute("ReadyAt") or 0
	if t < readyAt then
		Comms.toast(player, string.format("Junction box is fried. %d s until it can be cut again.", math.ceil(readyAt - t)), "warn")
		return
	end
	museum.junctionBox:SetAttribute("ReadyAt", t + Config.Museum.PowerCutCooldownSeconds)
	junctionCutUntil = t + Config.Museum.PowerCutSeconds
	security:cutPower(t, Config.Museum.PowerCutSeconds)
	setShutter(false)
	Comms.cueAll("PowerCut")
	Comms.toastMany(playersNearMuseum(), string.format("POWER CUT — cameras dark and the shutter lifted for %d s.", Config.Museum.PowerCutSeconds), "good")
	setInteriorLights(false)
	task.delay(Config.Museum.PowerCutSeconds, function()
		if not security:powerCutActive(now()) and not gridPowerOff then
			setInteriorLights(true)
			if security.level >= 3 then
				setShutter(true)
			end
			Comms.toastMany(playersNearMuseum(), "Power is back.", "warn")
		end
	end)
end

function SecurityService.onCameraSwitch(player: Player)
	security:disableCameras(now(), Config.Museum.CameraSwitchSeconds)
	Comms.toast(player, string.format("Cameras disabled for %d s.", Config.Museum.CameraSwitchSeconds), "good")
	Comms.cue(player, "Unlock")
end

function SecurityService.onOfficeCard(player: Player)
	if officeCardModel then
		officeCardModel:Destroy()
		officeCardModel = nil
	end
	player:SetAttribute("KeycardOffice", true)
	Comms.hud(player, { keycards = keycardList(player) })
	Comms.toast(player, "Office keycard taken. Vault readers A and B need two swipes within 4 s.", "good")
end

function SecurityService.onPickpocket(player: Player, prompt: ProximityPrompt)
	local guard
	local promptPart = prompt.Parent :: Instance
	for _, g in ipairs(guards) do
		if g.model == promptPart.Parent or g.root == promptPart then
			guard = g
		end
	end
	if not guard or not guard.hasCard then
		return
	end
	local pos = playerPos(player)
	if not pos then
		return
	end
	local look = guard.root.CFrame.LookVector
	local toPlayer = (pos - guard:position())
	if toPlayer.Magnitude > 6 then
		return
	end
	if security.level >= 2 or look:Dot(toPlayer.Unit) > -0.1 then
		-- Caught with a hand in the pocket
		local v = security:report(guard.id, guard.label, tostring(player.UserId), 1.2, false, now())
		guard.lastKnown = pos
		guard.lastSeenAt = now()
		Net.event("Detection"):FireClient(player, { level = v, source = guard.label, x = guard:position().X, z = guard:position().Z })
		Comms.toast(player, guard.label .. " turned around. Approach from behind.", "warn")
		return
	end
	guard.hasCard = false
	player:SetAttribute("KeycardCaptain", true)
	Comms.hud(player, { keycards = keycardList(player) })
	Comms.toast(player, "Captain's keycard lifted.", "good")
	local pp = guard.root:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Enabled = false
	end
end

function SecurityService.onReader(player: Player, prompt: ProximityPrompt)
	if vaultOpen then
		return
	end
	if not (player:GetAttribute("KeycardOffice") or player:GetAttribute("KeycardCaptain")) then
		Comms.toast(player, "No keycard. One is on the security office desk; the captain carries the other.", "warn")
		return
	end
	local name = (prompt.Parent :: Instance).Name
	local t = now()
	swipes[name] = t
	local other = if name == "ReaderA" then "ReaderB" else "ReaderA"
	Comms.cue(player, "Keypad")
	if swipes[other] and t - swipes[other] <= Config.Museum.DualSwipeWindowSeconds then
		setVault(true)
		Comms.cueAll("Unlock")
		Comms.toastMany(playersNearMuseum(), "Vault open: dual swipe accepted.", "good")
		SecurityService.ctx.services.Mission.note(player, "opened the vault with keycards")
	else
		Comms.toast(player, "Reader " .. name:sub(-1) .. " accepted. Swipe the other reader within 4 s.", "info")
	end
end

function SecurityService.onDrillStart(player: Player)
	if vaultOpen then
		return
	end
	SecurityService.noise("Drill screaming on the vault door", player)
end

function SecurityService.onDrillHold(player: Player, dt: number)
	local t = now()
	if (lastNoiseAt[player] or 0) + 1 < t then
		lastNoiseAt[player] = t
		security.lastReportAt = t
	end
	local _ = dt
end

function SecurityService.onDrillDone(player: Player)
	if vaultOpen then
		return
	end
	setVault(true)
	Comms.cueAll("Unlock")
	Comms.toastMany(playersNearMuseum(), "Vault drilled open by " .. Comms.name(player) .. ".", "alarm")
	SecurityService.ctx.services.Mission.note(player, "drilled the vault open")
end

function SecurityService.onCaseCutHold(player: Player, prompt: ProximityPrompt, dt: number)
	local part = prompt.Parent :: BasePart
	SecurityService.noiseAt(part.Position, 30, player, "glass cutting", 0.35, dt)
end

function SecurityService.setFrozen(on: boolean)
	frozen = on
	for _, g in ipairs(guards) do
		g.humanoid.WalkSpeed = if on then 0 else Config.Museum.GuardWalkSpeed
	end
end

function SecurityService.isInside(player: Player): boolean
	local pos = playerPos(player)
	return pos ~= nil and insideMuseum(pos)
end

function SecurityService.isInsideBounds(pos: Vector3): boolean
	return insideMuseum(pos)
end

-- Lifecycle ----------------------------------------------------------------------------------
function SecurityService.init(ctx)
	SecurityService.ctx = ctx
	museum = ctx.world.museum
	security = SecurityState.new({
		fillPerSecond = Config.Museum.SuspicionFillPerSecond,
		sneakMultiplier = Config.Museum.SuspicionSneakMultiplier,
		decayPerSecond = Config.Museum.SuspicionDecayPerSecond,
		suspiciousThreshold = Config.Museum.SuspiciousThreshold,
		alertThreshold = Config.Museum.AlertThreshold,
		lockdownDelay = Config.Museum.LockdownDelaySeconds,
		calmSeconds = Config.Museum.CalmSeconds,
	})
	security:onChange(onLevelChanged)
	cameras = museum.cameras
	-- Prompts
	for _, d in ipairs(museum.frontDoors) do
		Builder.prompt(d, "Smash the glass", "Front doors (loud)", Config.Museum.FrontSmashSeconds, "FrontSmash")
	end
	Builder.prompt(museum.dockKeypad, "Enter code", "Dock keypad", 0, "DockKeypad")
	Builder.prompt(museum.dockRelease, "Open dock door", "Door release", 0.5, "DockRelease")
	Builder.prompt(museum.junctionBox, "Cut the power", "Junction box (cameras + shutter)", 3, "JunctionBox")
	Builder.prompt(museum.cameraSwitch, "Kill the cameras", "CCTV main switch", 1.5, "CameraSwitch")
	for _, r in ipairs(museum.readers) do
		Builder.prompt(r, "Swipe keycard", "Vault reader " .. r.Name:sub(-1), 0.4, "Reader")
	end
	Builder.prompt(museum.drillPoint, "Drill the lock", "Vault (loud, " .. Config.Museum.DrillSeconds .. " s)", Config.Museum.DrillSeconds, "Drill")
end

function SecurityService.start()
	for _, route in ipairs(museum.guardRoutes) do
		local g = GuardBrain.new(SecurityService.ctx, route, security)
		if route.carriesCard then
			Builder.prompt(g.root, "Pickpocket keycard", "From behind, unseen", Config.Museum.PickpocketSeconds, "Pickpocket")
		end
		table.insert(guards, g)
	end
	SecurityService.restock()
	-- Main security tick (5 Hz for perception, decay and cameras)
	task.spawn(function()
		local last = now()
		while true do
			task.wait(0.2)
			local t = now()
			local dt = t - last
			last = t
			security:step(dt, t)
			if not frozen then
				for _, g in ipairs(guards) do
					g:tick(dt, t, SecurityService.vision)
				end
				tickCameras(dt, t)
				-- Running inside the museum is audible: a sprinting player's footsteps count as partial exposure
				-- to guards within earshot. Sneaking and walking make no noise (that is what sneak is for).
				for _, p in ipairs(Players:GetPlayers()) do
					local root = playerRoot(p)
					if root and p:GetAttribute("Sprinting") == true and insideMuseum(root.Position) and root.AssemblyLinearVelocity.Magnitude > 12 then
						SecurityService.noiseAt(root.Position, Config.Museum.FootstepHearingRadius, p, "running footsteps", Config.Museum.FootstepNoisePerSecond, dt)
					end
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			tickRestock()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		wrongCodeStreak[player] = nil
		lastNoiseAt[player] = nil
	end)
end

return SecurityService
