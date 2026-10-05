--!nonstrict
-- Crew-triggered harbour blackout. A crew on a job cuts the grid at the Harbour Substation (server-timed hold):
-- street and building lights go out, the sky drops to moonlight (never black), emergency amber lights come on,
-- museum cameras die and the lockdown shutter lifts, hideout shields and lasers lose power, guards and police
-- see less and cannot read plates. The saboteur takes heat. Anyone on foot can reset the grid early at the
-- same cabinet. Duration and server cooldown are bounded by WorldEventRules; every check is server-side.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local BlackoutRules = require(ReplicatedStorage.Shared.Core.BlackoutRules)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Comms = require(script.Parent.Comms)

local BlackoutService = {}
BlackoutService.ctx = nil :: any

local BC = Config.WorldEvents.Blackout
local EVENT = "blackout"

local gridDown = false
local gridLights: { { part: BasePart, material: Enum.Material, color: Color3, light: Light?, brightness: number } } = {}
local emergencyLights: { { part: BasePart, light: Light } } = {}
local refs -- substation refs from IslandBuilder
local prompts: { sabotage: ProximityPrompt?, reset: ProximityPrompt? } = {}
local holds: { [Player]: { kind: string, prompt: ProximityPrompt, progress: number } } = {}
local completing: { [Player]: boolean } = {}
local lightingTween: Tween?

local NORMAL = { Brightness = 2, OutdoorAmbient = Color3.fromRGB(78, 86, 108), Ambient = Color3.fromRGB(56, 60, 76), FogColor = Color3.fromRGB(92, 115, 140) } -- re-read from Lighting at start()
local MOONLIT = { Brightness = 0.9, OutdoorAmbient = Color3.fromRGB(38, 46, 72), Ambient = Color3.fromRGB(26, 30, 46), FogColor = Color3.fromRGB(40, 52, 74) }

-- Light inventory ------------------------------------------------------------------------------
local KEEP = { Lighthouse = true, PoliceStation = true } -- own generators: the lighthouse sweeps on, the station stays lit
local GRID_NAMES = { LampHead = true, Windows = true, FloodHead = true, DeckLampHead = true, Lantern = true, Lamp = true, BayLamp = true, AccentStrip = true, CoilGlow = true }

local function inKeptModel(inst: Instance): boolean
	local m = inst:FindFirstAncestorWhichIsA("Model")
	while m do
		if KEEP[m.Name] then
			return true
		end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local function collectLights(root: Instance)
	gridLights = {}
	emergencyLights = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "EmergencyLight" then
				local l = d:FindFirstChildWhichIsA("Light")
				if l then
					table.insert(emergencyLights, { part = d, light = l })
				end
			elseif d.Material == Enum.Material.Neon and (GRID_NAMES[d.Name] or (d.Name == "NeonSign" and d:FindFirstAncestor("LanternCross"))) and not inKeptModel(d) then
				local l = d:FindFirstChildWhichIsA("Light")
				table.insert(gridLights, { part = d, material = d.Material, color = d.Color, light = l, brightness = l and l.Brightness or 0 })
			end
		end
	end
end

local function setGridLights(on: boolean)
	for _, g in ipairs(gridLights) do
		g.part.Material = if on then g.material else Enum.Material.SmoothPlastic
		g.part.Color = if on then g.color else Palette.Night
		if g.light then
			g.light.Enabled = on
			g.light.Brightness = g.brightness
		end
	end
	for _, e in ipairs(emergencyLights) do
		e.part.Material = if on then Enum.Material.SmoothPlastic else Enum.Material.Neon
		e.part.Color = if on then Color3.fromRGB(70, 48, 20) else Palette.SecurityAmber
		e.light.Enabled = not on
		e.light.Brightness = if on then 0 else 1.4
	end
end

local function setSky(down: boolean)
	if lightingTween then
		lightingTween:Cancel()
	end
	local tw = TweenService:Create(Lighting, TweenInfo.new(if down then 0.6 else 2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), if down then MOONLIT else NORMAL)
	lightingTween = tw
	tw:Play()
end

local function setPrompts()
	local canStart, why = BlackoutService.ctx.services.WorldEvent.canStart(EVENT)
	if prompts.sabotage then
		prompts.sabotage.Enabled = not gridDown
		prompts.sabotage.ObjectText = if gridDown then "Harbour grid (down)" elseif canStart then string.format("Harbour grid · crew on a job · loud · %d s", BC.DurationSeconds) else "Harbour grid (" .. tostring(why) .. ")"
	end
	if prompts.reset then
		prompts.reset.Enabled = gridDown
	end
	if refs and refs.warningLight then
		refs.warningLight.Color = if gridDown then Palette.SecurityRed else Palette.SecurityAmber
		local l = refs.warningLight:FindFirstChildWhichIsA("Light")
		if l then
			l.Color = refs.warningLight.Color
		end
	end
end

-- World state (idempotent either way) --------------------------------------------------------
local function applyGrid(down: boolean, seconds: number)
	if gridDown == down then
		return
	end
	gridDown = down
	local S = BlackoutService.ctx.services
	setGridLights(not down)
	setSky(down)
	S.Security.setGridPower(not down, seconds)
	S.Security.setGuardVisionScale(BlackoutRules.visionScale(BC, "guard", down))
	S.Police.setGridDown(down, BlackoutRules.visionScale(BC, "cop", down))
	S.Raid.setGridDown(down)
	setPrompts()
end

function BlackoutService.isGridDown(): boolean
	return gridDown
end

-- Diagnostics for the engine scenario
function BlackoutService.lightReport(): { dark: number, total: number, emergencyOn: number }
	local dark, emergencyOn = 0, 0
	for _, g in ipairs(gridLights) do
		if g.part.Material ~= Enum.Material.Neon then
			dark += 1
		end
	end
	for _, e in ipairs(emergencyLights) do
		if e.light.Enabled then
			emergencyOn += 1
		end
	end
	return { dark = dark, total = #gridLights, emergencyOn = emergencyOn }
end

-- Eligibility (all server-side) -----------------------------------------------------------------
local function actorOf(player: Player)
	local S = BlackoutService.ctx.services
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local crew = S.Crew.crewOf(player)
	return {
		alive = humanoid ~= nil and humanoid.Health > 0,
		jailed = player:GetAttribute("Jailed") == true,
		seated = humanoid ~= nil and humanoid.SeatPart ~= nil,
		jobActive = crew ~= nil and S.Mission.isJobActive(crew.id),
	}
end

local function refusal(player: Player, kind: string): string?
	if kind == "sabotage" then
		local why = BlackoutRules.sabotageRefusal(BC, actorOf(player))
		if why then
			return why
		end
		local ok, err = BlackoutService.ctx.services.WorldEvent.canStart(EVENT)
		return if ok then nil else err
	end
	local why = BlackoutRules.resetRefusal(actorOf(player))
	if why then
		return why
	end
	return if gridDown then nil else "the grid is up"
end

local function seconds(kind: string): number
	return if kind == "sabotage" then BC.SabotageSeconds else BC.ResetSeconds
end

local function holdText(kind: string): string
	return if kind == "sabotage" then "Cutting the harbour grid — loud" else "Resetting the harbour grid"
end

-- Hold handlers (server-timed; the client's hold length is never trusted) ------------------------
local function beginHold(kind: string)
	return function(player: Player, prompt: ProximityPrompt)
		local why = refusal(player, kind)
		if why then
			Comms.toast(player, (if kind == "sabotage" then "Can't cut the grid: " else "Can't reset: ") .. why .. ".", "warn")
			return
		end
		holds[player] = { kind = kind, prompt = prompt, progress = 0 }
	end
end

local function complete(player: Player, kind: string)
	if completing[player] then
		return
	end
	completing[player] = true
	holds[player] = nil
	Comms.hud(player, { holdProgress = 0 })
	local S = BlackoutService.ctx.services
	local why = refusal(player, kind)
	if why then
		Comms.toast(player, "No luck: " .. why .. ".", "warn")
		completing[player] = nil
		return
	end
	if kind == "sabotage" then
		local crew = S.Crew.crewOf(player)
		local active, err = S.WorldEvent.trigger(EVENT, player, { crewId = crew and crew.id or nil })
		if not active then
			Comms.toast(player, "Can't cut the grid: " .. tostring(err) .. ".", "warn")
		else
			S.Police.addHeat(player, BC.SaboteurHeat, "cut the harbour grid")
			if crew then
				S.EventLog.crew(crew.id, string.format("%s cut the harbour grid (%d s)", Comms.name(player), BC.DurationSeconds), "warn")
			end
			Comms.cueAll("PowerCut")
			Comms.toastAll(string.format("BLACKOUT — the harbour grid is down for %d s. Reset it at the substation in the crane yard.", BC.DurationSeconds), "alarm")
			Comms.toast(player, string.format("Grid cut. Police heat +%d. Cameras dark, shutters up, pier shields down.", BC.SaboteurHeat), "good")
		end
	else
		local ended = S.WorldEvent.cancel(EVENT, "reset by " .. Comms.name(player))
		if ended then
			local crew = S.Crew.crewOf(player)
			if crew then
				S.EventLog.crew(crew.id, Comms.name(player) .. " reset the harbour grid", "good")
			end
			Comms.toastAll(Comms.name(player) .. " reset the harbour grid. Lights back on.", "warn")
		end
	end
	completing[player] = nil
end

local function holdTick(player: Player, prompt: ProximityPrompt, dt: number)
	local h = holds[player]
	if not h or h.prompt ~= prompt then
		return
	end
	if refusal(player, h.kind) then
		holds[player] = nil
		Comms.hud(player, { holdProgress = 0 })
		return
	end
	h.progress += math.clamp(dt, 0, 1)
	Comms.hud(player, { holdProgress = math.clamp(h.progress / seconds(h.kind), 0, 1), holdText = holdText(h.kind) })
	if h.progress >= seconds(h.kind) then
		complete(player, h.kind)
	end
end

local function holdEnded(player: Player)
	if holds[player] then
		holds[player] = nil
		Comms.hud(player, { holdProgress = 0 })
	end
end

-- PromptTriggered: the client says its hold finished. Only the server's own timer counts.
local function triggered(kind: string)
	return function(player: Player, prompt: ProximityPrompt)
		local h = holds[player]
		if not h or h.prompt ~= prompt or h.kind ~= kind or h.progress < seconds(kind) - 0.35 then
			return
		end
		complete(player, kind)
	end
end

-- Engine-test helper: run the hold on the server clock for one player (same validation as a real hold).
function BlackoutService.testHold(player: Player, kind: string): boolean
	local prompt = if kind == "sabotage" then prompts.sabotage else prompts.reset
	if not prompt then
		return false
	end
	beginHold(kind)(player, prompt)
	if not holds[player] then
		return false
	end
	local t0 = os.clock()
	while holds[player] and os.clock() - t0 < seconds(kind) + 2 do
		task.wait(0.25)
		holdTick(player, prompt, 0.25)
	end
	return if kind == "sabotage" then gridDown else not gridDown
end

function BlackoutService.init(ctx)
	BlackoutService.ctx = ctx
end

function BlackoutService.start()
	local S = BlackoutService.ctx.services
	refs = BlackoutService.ctx.world.island.substation
	NORMAL = { Brightness = Lighting.Brightness, OutdoorAmbient = Lighting.OutdoorAmbient, Ambient = Lighting.Ambient, FogColor = Lighting.FogColor }
	collectLights(BlackoutService.ctx.world.root)
	setGridLights(true)
	if refs then
		prompts.sabotage = Builder.prompt(refs.cabinet, "Cut the grid", "Harbour grid", BC.SabotageSeconds, "GridSabotage")
		prompts.reset = Builder.prompt(refs.resetPanel, "Reset the grid", string.format("Grid reset (%d s)", BC.ResetSeconds), BC.ResetSeconds, "GridReset")
	end
	local def = BlackoutRules.definition(BC)
	S.WorldEvent.register(def, {
		label = "BLACKOUT",
		onStart = function(active)
			applyGrid(true, active.endsAt - active.startedAt)
		end,
		onEnd = function(_active, reason)
			applyGrid(false, 0)
			if reason == "expired" then
				Comms.toastAll("The harbour grid is back up.", "warn")
			end
		end,
	})
	S.Interaction.register("GridSabotage", triggered("sabotage"))
	S.Interaction.register("GridReset", triggered("reset"))
	S.Interaction.registerHold("GridSabotage", { begin = beginHold("sabotage"), hold = holdTick, ended = holdEnded })
	S.Interaction.registerHold("GridReset", { begin = beginHold("reset"), hold = holdTick, ended = holdEnded })
	setPrompts()
	task.spawn(function()
		while true do
			task.wait(5)
			if not gridDown then
				setPrompts() -- cooldown text
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		holds[player] = nil
		completing[player] = nil
	end)
end

return BlackoutService
