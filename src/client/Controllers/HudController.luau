--!nonstrict
-- The in-game HUD. Answers: what am I doing, what can I interact with (prompts are native), where is my
-- crew, what am I carrying, what is threatening me, what changed. Shows only what matters right now.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Make = require(script.Parent.Parent.UI.Make)

local HudController = {}

local player = Players.LocalPlayer
local gui
local refs: { [string]: any } = {}
local state = { worldEvents = {}, convoy = nil, stash = 0, cash = 0, crew = nil, mission = nil, carry = nil, security = 0, heat = 0, detection = 0, detectionAt = 0, detectionSource = nil, detectionPos = nil, keycards = {}, cuffing = 0, jailed = false }
local logOpen = false

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function buildScale(screen: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Parent = screen
	local function update()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.78, 1.2)
		scale.Scale = s
	end
	update()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GlasshouseHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	buildScale(gui)

	-- Objective (top-left)
	local obj = Make.panel(gui, "Objective", UDim2.new(0, 330, 0, 0), UDim2.new(0, 16, 0, 16))
	obj.AutomaticSize = Enum.AutomaticSize.Y
	Make.list(obj, 4)
	refs.objTitle = Make.label(obj, "Title", "Open the job board at your pier", Theme.Title, Theme.Text, true)
	refs.objDetail = Make.label(obj, "Detail", "Run solo now, or share your crew code and run it together.", Theme.Small, Theme.Muted)
	refs.objDistance = Make.label(obj, "Distance", "", Theme.Small, Theme.Accent, true)
	refs.objDistance.LayoutOrder = 3

	-- Status pills under the objective
	local pills = Make.frame(gui, "Pills", UDim2.new(0, 330, 0, 30), UDim2.new(0, 16, 0, 120), Theme.Panel, 1)
	refs.pills = pills
	Make.list(pills, 6, true)
	refs.securityPill = Make.pill(pills, "Security", "Museum: Quiet", Theme.Muted)
	refs.heatPill = Make.pill(pills, "Heat", "", Theme.Police)
	refs.heatPill.Parent.Visible = false
	refs.keycardPill = Make.pill(pills, "Keycards", "", Theme.Gold)
	refs.keycardPill.Parent.Visible = false

	-- Cash (top-right)
	local cash = Make.panel(gui, "Cash", UDim2.new(0, 190, 0, 54), UDim2.new(1, -206, 0, 16))
	refs.cash = Make.label(cash, "Amount", "0", Theme.Big, Theme.Gold, true)
	refs.cash.TextXAlignment = Enum.TextXAlignment.Right
	refs.cashNote = Make.label(cash, "Note", "", Theme.Small, Theme.Muted)
	refs.cashNote.TextXAlignment = Enum.TextXAlignment.Right
	refs.cashNote.Position = UDim2.new(0, 0, 0, 32)
	refs.stash = Make.label(cash, "Stash", "", Theme.Small, Theme.Accent, true)
	refs.stash.TextXAlignment = Enum.TextXAlignment.Right
	refs.stash.Position = UDim2.new(0, 0, 0, 46)
	cash.Size = UDim2.new(0, 190, 0, 70)

	-- Crew card (right, under cash)
	local crew = Make.panel(gui, "Crew", UDim2.new(0, 230, 0, 0), UDim2.new(1, -246, 0, 96))
	crew.AutomaticSize = Enum.AutomaticSize.Y
	Make.list(crew, 3)
	refs.crewTitle = Make.label(crew, "Title", "Crew", Theme.Body, Theme.Text, true)
	refs.crewCode = Make.label(crew, "Code", "", Theme.Small, Theme.Muted)
	refs.crewList = Make.frame(crew, "List", UDim2.new(1, 0, 0, 0), UDim2.new(), Theme.Panel, 1)
	refs.crewList.AutomaticSize = Enum.AutomaticSize.Y
	Make.list(refs.crewList, 2)

	-- Carry (bottom-centre)
	local carry = Make.panel(gui, "Carry", UDim2.new(0, 300, 0, 64), UDim2.new(0.5, -150, 1, -150))
	carry.Visible = false
	refs.carry = carry
	refs.carryLabel = Make.label(carry, "Label", "", Theme.Body, Theme.Gold, true)
	refs.carryHint = Make.label(carry, "Hint", "", Theme.Small, Theme.Muted)
	refs.carryHint.Position = UDim2.new(0, 0, 0, 22)

	-- Threat meter (left-centre): an eye that fills as you are seen, with the direction of the watcher
	local threat = Make.frame(gui, "Threat", UDim2.new(0, 120, 0, 120), UDim2.new(0, 16, 0.5, -60), Theme.Panel, 1)
	refs.threat = threat
	threat.Visible = false
	local eye = Make.frame(threat, "Eye", UDim2.new(0, 70, 0, 70), UDim2.new(0.5, -35, 0.5, -35), Theme.Panel, 0.1)
	Make.corner(eye, 35)
	refs.eyeStroke = Make.stroke(eye, Theme.Warn, 3)
	local fill = Make.frame(eye, "Fill", UDim2.new(1, 0, 0, 0), UDim2.new(0, 0, 1, 0), Theme.Warn, 0.2)
	fill.AnchorPoint = Vector2.new(0, 1)
	Make.corner(fill, 35)
	refs.eyeFill = fill
	refs.eyeText = Make.label(eye, "Text", "SEEN", Theme.Small, Theme.Text, true)
	refs.eyeText.TextXAlignment = Enum.TextXAlignment.Center
	refs.eyeText.TextYAlignment = Enum.TextYAlignment.Center
	refs.eyeText.Size = UDim2.fromScale(1, 1)
	refs.eyeText.AutomaticSize = Enum.AutomaticSize.None
	local arrow = Make.label(threat, "Arrow", "▲", 22, Theme.Warn, true)
	arrow.Size = UDim2.new(0, 24, 0, 24)
	arrow.AutomaticSize = Enum.AutomaticSize.None
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0, 10)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextYAlignment = Enum.TextYAlignment.Center
	refs.arrow = arrow
	refs.threatSource = Make.label(threat, "Source", "", Theme.Small, Theme.Warn, true)
	refs.threatSource.Position = UDim2.new(0, -10, 1, -4)
	refs.threatSource.Size = UDim2.new(1, 20, 0, 14)
	refs.threatSource.TextXAlignment = Enum.TextXAlignment.Center

	-- Cuffing bar (centre)
	local cuff = Make.panel(gui, "Cuffing", UDim2.new(0, 260, 0, 48), UDim2.new(0.5, -130, 0.5, 60))
	cuff.Visible = false
	refs.cuff = cuff
	Make.label(cuff, "Text", "Being cuffed — move away!", Theme.Small, Theme.Alarm, true)
	local bg, cfill = Make.bar(cuff, "Bar", Theme.Alarm)
	bg.Position = UDim2.new(0, 0, 0, 22)
	refs.cuffFill = cfill

	-- Safe cracking bar (centre)
	local crack = Make.panel(gui, "Crack", UDim2.new(0, 260, 0, 48), UDim2.new(0.5, -130, 0.5, 60))
	crack.Visible = false
	refs.crack = crack
	refs.crackText = Make.label(crack, "Text", "Cracking the safe", Theme.Small, Theme.Gold, true)
	local kbg, kfill = Make.bar(crack, "Bar", Theme.Gold)
	kbg.Position = UDim2.new(0, 0, 0, 22)
	refs.crackFill = kfill

	-- Raid panel (left, under the pills)
	local raid = Make.panel(gui, "Raid", UDim2.new(0, 330, 0, 0), UDim2.new(0, 16, 0, 160))
	raid.AutomaticSize = Enum.AutomaticSize.Y
	raid.Visible = false
	refs.raid = raid
	Make.list(raid, 2)
	refs.raidTitle = Make.label(raid, "Title", "", Theme.Body, Theme.Alarm, true)
	refs.raidText = Make.label(raid, "Text", "", Theme.Small, Theme.Text)

	-- Vehicle health (bottom-left)
	local veh = Make.panel(gui, "Vehicle", UDim2.new(0, 200, 0, 44), UDim2.new(0, 16, 1, -70))
	veh.Visible = false
	refs.vehicle = veh
	refs.vehicleText = Make.label(veh, "Text", "", Theme.Small, Theme.Text, true)
	local vbg, vfill = Make.bar(veh, "Bar", Theme.Good)
	vbg.Position = UDim2.new(0, 0, 0, 20)
	refs.vehicleFill = vfill

	-- Jail panel (centre-top)
	local jail = Make.panel(gui, "Jail", UDim2.new(0, 360, 0, 0), UDim2.new(0.5, -180, 0, 110))
	jail.AutomaticSize = Enum.AutomaticSize.Y
	jail.Visible = false
	refs.jail = jail
	Make.list(jail, 4)
	Make.label(jail, "Title", "IN A CELL", Theme.Title, Theme.Alarm, true)
	refs.jailText = Make.label(jail, "Text", "", Theme.Small, Theme.Text)

	-- Toasts (top-centre)
	local toasts = Make.frame(gui, "Toasts", UDim2.new(0, 420, 0, 0), UDim2.new(0.5, -210, 0, 16), Theme.Panel, 1)
	toasts.AutomaticSize = Enum.AutomaticSize.Y
	Make.list(toasts, 6)
	refs.toasts = toasts

	-- Evidence log (toggle)
	local log = Make.panel(gui, "Log", UDim2.new(0, 360, 0, 260), UDim2.new(1, -376, 1, -290))
	log.Visible = false
	refs.log = log
	Make.label(log, "Title", "Crew log (L / ▢ to hide)", Theme.Body, Theme.Text, true)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -24)
	scroll.Position = UDim2.new(0, 0, 0, 24)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = log
	Make.list(scroll, 2)
	refs.logList = scroll

	-- World-event banner (bottom-centre, above the carry panel): what is happening, how long, where to counter it
	local banner = Make.panel(gui, "WorldEvent", UDim2.new(0, 360, 0, 50), UDim2.new(0.5, -180, 1, -226))
	banner.Visible = false
	banner.BackgroundColor3 = Color3.fromRGB(34, 26, 14)
	refs.banner = banner
	refs.bannerTitle = Make.label(banner, "Title", "BLACKOUT", Theme.Body, Theme.Warn, true)
	refs.bannerText = Make.label(banner, "Text", "", Theme.Small, Theme.Text)
	refs.bannerText.Position = UDim2.new(0, 0, 0, 22)

	-- Flash overlay for important sounds (visual equivalent, single soft fade, no strobe)
	local flash = Make.frame(gui, "Flash", UDim2.fromScale(1, 1), UDim2.new(), Theme.Alarm, 1)
	flash.ZIndex = 0
	refs.flash = flash

	-- Hint bar (bottom-right): controls
	local hint = Make.panel(gui, "Hints", UDim2.new(0, 230, 0, 0), UDim2.new(1, -246, 1, -96))
	hint.AutomaticSize = Enum.AutomaticSize.Y
	refs.hints = Make.label(hint, "Text", "Shift sprint · C sneak · G drop bag · L log", Theme.Small, Theme.Muted)
	refs.hintPanel = hint
end

-- Updates ----------------------------------------------------------------------------------
function HudController.toast(text: string, kind: string?)
	local color = Theme.kindColor(kind)
	local f = Make.frame(refs.toasts, "Toast", UDim2.new(1, 0, 0, 0), UDim2.new(), Theme.Panel, 0.1)
	f.AutomaticSize = Enum.AutomaticSize.Y
	Make.corner(f, 8)
	Make.stroke(f, color, 1.5)
	Make.padding(f, 8)
	local t = Make.label(f, "Text", text, Theme.Body, if kind == "alarm" then Theme.Alarm else Theme.Text, kind == "alarm")
	t.TextXAlignment = Enum.TextXAlignment.Center
	-- slide in from above and fade up; alarms also get the stroke to breathe once
	f.BackgroundTransparency = 1
	t.TextTransparency = 1
	f.Position = UDim2.new(0, 0, 0, -12)
	TweenService:Create(f, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.1, Position = UDim2.new() }):Play()
	TweenService:Create(t, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
	local life = if kind == "alarm" then 7 else 5
	task.delay(life, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		f:Destroy()
	end)
	-- Keep at most 4
	local kids = refs.toasts:GetChildren()
	local n = 0
	for i = #kids, 1, -1 do
		if kids[i]:IsA("Frame") then
			n += 1
			if n > 4 then
				kids[i]:Destroy()
			end
		end
	end
end

function HudController.flash(color: Color3)
	refs.flash.BackgroundColor3 = color
	refs.flash.BackgroundTransparency = 0.75
	TweenService:Create(refs.flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
end

local function setMission(m)
	state.mission = m
	refs.objTitle.Text = m.objective or ""
	refs.objDetail.Text = m.objectiveDetail or ""
	refs.objDistance.Text = ""
end

local function setCrew(c)
	state.crew = c
	refs.crewTitle.Text = string.format("Crew · %s · %d/%d", c.unitLabel or "?", #c.members, c.maxSize or 5)
	refs.crewCode.Text = if #c.members < (c.maxSize or 5) then "Join code: " .. tostring(c.code) .. (if c.jobActive then "  (job running)" else "") else "Crew full" .. (if c.jobActive then "  (job running)" else "")
	for _, ch in ipairs(refs.crewList:GetChildren()) do
		if ch:IsA("TextLabel") then
			ch:Destroy()
		end
	end
	for i, m in ipairs(c.members) do
		local line = Make.label(refs.crewList, "M" .. i, "", Theme.Small, Theme.Text)
		local parts = { (if m.isLeader then "★ " else "") .. m.name }
		if m.jailed then
			table.insert(parts, "<font color='#e63c30'>in a cell</font>")
		end
		if m.carrying then
			table.insert(parts, "<font color='#ffd060'>" .. m.carrying .. "</font>")
		end
		table.insert(parts, tostring(m.share) .. "%")
		line.Text = table.concat(parts, " · ")
		line.LayoutOrder = i
		if m.userId == player.UserId then
			line.TextColor3 = Theme.Accent
		end
	end
end

local function setCarry(c)
	state.carry = c and c.itemId and c or nil
	if state.carry then
		refs.carry.Visible = true
		refs.carryLabel.Text = string.format("Carrying: %s (%s)", c.label, fmt(c.value))
		refs.carryHint.Text = if c.weight == "Heavy" then "Heavy: slow, no sprint, no climbing. G / ▽ to drop." else "G / ▽ to drop. Anyone can pick up a dropped bag."
	else
		refs.carry.Visible = false
	end
end

local function setSecurity(s)
	state.security = s.level
	local colors = { [0] = Theme.Muted, [1] = Theme.Warn, [2] = Theme.Alarm, [3] = Theme.Alarm }
	refs.securityPill.Text = "Museum: " .. tostring(s.label)
	refs.securityPill.TextColor3 = colors[s.level] or Theme.Muted
	local stroke = refs.securityPill.Parent:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = colors[s.level] or Theme.Muted
	end
end

local function setHeat(h)
	state.heat = h.level
	refs.heatPill.Parent.Visible = h.level > 0
	refs.heatPill.Text = string.format("Police: %s", h.label or "")
end

local function setKeycards(list)
	state.keycards = list or {}
	refs.keycardPill.Parent.Visible = #state.keycards > 0
	refs.keycardPill.Text = "Keycards: " .. table.concat(state.keycards, ", ")
end

local function setLog(entries)
	for _, ch in ipairs(refs.logList:GetChildren()) do
		if ch:IsA("TextLabel") then
			ch:Destroy()
		end
	end
	for i = #entries, 1, -1 do
		local e = entries[i]
		local l = Make.label(refs.logList, "E" .. i, e.text, Theme.Small, Theme.kindColor(e.kind))
		l.LayoutOrder = #entries - i
	end
end

-- World events: one banner for the most urgent active event; countdown uses the server clock
local EVENT_HINT = { blackout = "Street and pier power is out. Reset it at the Harbour Substation (crane yard)." }
local function setWorldEvent(e)
	if type(e) ~= "table" or type(e.id) ~= "string" then
		return
	end
	state.worldEvents[e.id] = if e.active then e else nil
	if e.id == "blackout" then
		if e.active then
			HudController.flash(Theme.Warn)
		end
	end
end

local function convoyLine(c): string
	local phase = tostring(c.phase or "")
	local where = tostring(c.landmark or "")
	local cargo = tostring(c.cargo or "secured")
	local cargoText = if cargo == "secured" then "cargo secured" elseif cargo == "sealed" then "cargo sealed" elseif cargo == "loose" then string.format("%d crates loose", c.crates or 0) else "cargo taken"
	if phase == "Departing" then
		return "Leaving soon from " .. where .. " · " .. cargoText
	elseif phase == "Checkpoint" then
		return "Security check at " .. where .. " · " .. cargoText
	elseif phase == "Crippled" or phase == "Halted" then
		return "Stopped near " .. where .. " · " .. cargoText
	elseif phase == "Breached" then
		return "Breached near " .. where .. " · " .. cargoText .. " · get them to your pier"
	end
	return "Moving near " .. where .. " · " .. cargoText
end

local function updateBanner()
	local pick = nil
	for _, e in pairs(state.worldEvents) do
		if not pick or e.id == "convoy" or ((e.endsAt or 0) > (pick.endsAt or 0) and pick.id ~= "convoy") then
			pick = e
		end
	end
	if not pick then
		if refs.banner.Visible and not refs.bannerHiding then
			refs.bannerHiding = true
			TweenService:Create(refs.banner, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.36, function()
				refs.banner.Visible = false
				refs.banner.BackgroundTransparency = 0.1
				refs.bannerHiding = false
			end)
		end
		return
	end
	refs.bannerHiding = false
	local left = math.max(0, (pick.endsAt or 0) - workspace:GetServerTimeNow())
	refs.banner.Visible = true
	refs.bannerTitle.Text = string.format("%s · %d:%02d", tostring(pick.label or pick.id), math.floor(left / 60), math.floor(left % 60))
	if pick.id == "convoy" and state.convoy and state.convoy.active then
		refs.bannerText.Text = convoyLine(state.convoy)
		refs.bannerTitle.TextColor3 = if (state.convoy.alert or 0) >= 2 then Theme.Alarm else Theme.Warn
	else
		refs.bannerText.Text = EVENT_HINT[pick.id] or ""
		refs.bannerTitle.TextColor3 = Theme.Warn
	end
end

local function setJail(j)
	if j.state == "jailed" then
		state.jailed = true
		refs.jail.Visible = true
		refs.jailText.Text = string.format("Auto-release in %d s. Pick the cell door lock (hold E / ✕ on the door), or a crewmate can hit CELL RELEASE in the lobby.", j.secondsLeft or 0)
	else
		state.jailed = false
		refs.jail.Visible = false
	end
end

function HudController.toggleLog(force: boolean?)
	logOpen = if force ~= nil then force else not logOpen
	refs.log.Visible = logOpen
end

function HudController.setHints(text: string)
	refs.hints.Text = text
end

-- Per-frame: distance/direction to the objective, threat meter decay
local bannerAt = 0
local function step()
	local tnow = os.clock()
	if tnow - bannerAt > 0.25 then
		bannerAt = tnow
		updateBanner()
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and state.mission and state.mission.targetX then
		local d = Vector3.new(state.mission.targetX - root.Position.X, 0, state.mission.targetZ - root.Position.Z)
		local dist = d.Magnitude
		local cam = workspace.CurrentCamera
		local look = cam and Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
		local dir = if dist > 1 then d.Unit else Vector3.new(0, 0, -1)
		local ang = math.deg(math.atan2(look:Cross(dir).Y, look:Dot(dir)))
		local compass = if math.abs(ang) < 25 then "ahead" elseif ang > 0 and ang < 155 then "to your left" elseif ang < 0 and ang > -155 then "to your right" else "behind you"
		refs.objDistance.Text = string.format("%d studs %s", math.floor(dist), compass)
	end
	-- Threat
	local t = os.clock()
	if t - state.detectionAt > 0.6 then
		state.detection = math.max(0, state.detection - 0.5 * (t - state.detectionAt - 0.6))
	end
	local v = state.detection
	refs.threat.Visible = v > 0.02
	refs.eyeFill.Size = UDim2.new(1, 0, v, 0)
	local color = if v >= 0.95 then Theme.Alarm elseif v >= 0.5 then Theme.Warn else Theme.Accent
	refs.eyeFill.BackgroundColor3 = color
	refs.eyeStroke.Color = color
	refs.eyeText.Text = if v >= 0.95 then "SPOTTED" elseif v >= 0.5 then "NOTICED" else "WATCHED"
	refs.threatSource.Text = state.detectionSource or ""
	if root and state.detectionPos then
		local d = Vector3.new(state.detectionPos.X - root.Position.X, 0, state.detectionPos.Y - root.Position.Z)
		local cam = workspace.CurrentCamera
		local look = cam and Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
		if d.Magnitude > 0.5 and look.Magnitude > 0 then
			local ang = math.deg(math.atan2(look.Unit:Cross(d.Unit).Y, look.Unit:Dot(d.Unit)))
			refs.arrow.Rotation = -ang
			local rad = math.rad(-ang)
			refs.arrow.Position = UDim2.new(0.5, math.sin(rad) * 50, 0.5, -math.cos(rad) * 50)
		end
	end
end

function HudController.init()
	build()
	Net.event("Toast").OnClientEvent:Connect(function(d)
		HudController.toast(d.text, d.kind)
	end)
	Net.event("HudState").OnClientEvent:Connect(function(d)
		if d.cash ~= nil then
			local delta = d.cash - (state.cash or 0)
			state.cash = d.cash
			refs.cash.Text = fmt(d.cash)
			if delta ~= 0 then
				Make.pulse(refs.cash, if delta > 0 then Theme.Good else Theme.Alarm)
			end
		end
		if d.saveable ~= nil then
			refs.cashNote.Text = if d.saveable then "saved" else "NOT SAVING: " .. tostring(d.saveReason or "")
			refs.cashNote.TextColor3 = if d.saveable then Theme.Muted else Theme.Warn
		end
		if d.keycards then
			setKeycards(d.keycards)
		end
		if d.cuffing ~= nil then
			refs.cuff.Visible = d.cuffing > 0
			refs.cuffFill.Size = UDim2.new(d.cuffing, 0, 1, 0)
		end
		if d.holdProgress ~= nil then
			refs.crack.Visible = d.holdProgress > 0
			refs.crackFill.Size = UDim2.new(d.holdProgress, 0, 1, 0)
			if d.holdText then
				refs.crackText.Text = d.holdText
			end
		end
		if d.crackProgress ~= nil then
			refs.crack.Visible = d.crackProgress > 0
			refs.crackFill.Size = UDim2.new(d.crackProgress, 0, 1, 0)
			refs.crackText.Text = if d.crackAssist then "Cracking the safe (assisted)" else "Cracking the safe — stay close"
		end
		if d.vehicleHealth ~= nil then
			refs.vehicle.Visible = true
			refs.vehicleText.Text = string.format("Vehicle %d / %d", d.vehicleHealth, d.vehicleMaxHealth or d.vehicleHealth)
			refs.vehicleFill.Size = UDim2.new(math.clamp(d.vehicleHealth / math.max(1, d.vehicleMaxHealth or 1), 0, 1), 0, 1, 0)
		end
	end)
	Net.event("MissionState").OnClientEvent:Connect(setMission)
	Net.event("CrewState").OnClientEvent:Connect(setCrew)
	Net.event("Carry").OnClientEvent:Connect(setCarry)
	Net.event("SecurityLevel").OnClientEvent:Connect(setSecurity)
	Net.event("Heat").OnClientEvent:Connect(setHeat)
	Net.event("EventLog").OnClientEvent:Connect(function(d)
		setLog(d.entries or {})
	end)
	Net.event("Jail").OnClientEvent:Connect(setJail)
	Net.event("WorldEvent").OnClientEvent:Connect(setWorldEvent)
	Net.event("ConvoyState").OnClientEvent:Connect(function(c)
		if type(c) ~= "table" then
			return
		end
		local wasBreached = state.convoy and state.convoy.cargo == "loose"
		state.convoy = if c.active then c else nil
		if c.active and c.cargo == "loose" and not wasBreached then
			HudController.flash(Theme.Gold)
		end
	end)
	Net.event("HideoutState").OnClientEvent:Connect(function(h)
		local before = state.stash or 0
		state.stash = h.stash or 0
		if state.stash ~= before then
			Make.pulse(refs.stash, if state.stash > before then Theme.Good else Theme.Alarm)
		end
		refs.stash.Text = if (h.stash or 0) > 0 then string.format("stash %s AT RISK · tier %d", fmt(h.stash or 0), h.tier or 0) else string.format("stash 0 · tier %d", h.tier or 0)
		refs.stash.TextColor3 = if (h.stash or 0) > 0 then Theme.Warn else Theme.Accent
	end)
	Net.event("RaidState").OnClientEvent:Connect(function(r)
		if not r.active then
			refs.raid.Visible = false
			return
		end
		refs.raid.Visible = true
		local parts = {}
		table.insert(parts, if r.shieldDown then "shield down" else "shield up")
		table.insert(parts, if r.doorOpen then "pier door open" else "pier door shut")
		table.insert(parts, if r.alarmed then "ALARM" else "quiet")
		table.insert(parts, if r.cracked then string.format("safe open: %s out, %s kept", fmt(r.stolen or 0), fmt(r.retained or 0)) else "safe shut")
		table.insert(parts, string.format("%d:%02d left", math.floor((r.secondsLeft or 0) / 60), (r.secondsLeft or 0) % 60))
		if r.defending then
			refs.raidTitle.Text = if r.recovery then string.format("%s IS TAKING BACK WHAT YOU STOLE (%s owed)", (r.raiderName or "?"):upper(), fmt(r.owed or 0)) else string.format("YOUR HIDEOUT IS UNDER RAID — %s's crew (%d)", r.raiderName or "?", r.crewSize or 1)
			refs.raidTitle.TextColor3 = Theme.Alarm
		else
			refs.raidTitle.Text = if r.recovery then string.format("Recovery: %s owes you %s · %s", r.targetName or "?", fmt(r.owed or 0), r.unitLabel or "?") else string.format("Raid: %s's hideout (tier %d) at %s", r.targetName or "?", r.tier or 0, r.unitLabel or "?")
			refs.raidTitle.TextColor3 = Theme.Gold
		end
		refs.raidText.Text = table.concat(parts, " · ")
	end)
	Net.event("Detection").OnClientEvent:Connect(function(d)
		state.detection = math.max(state.detection, d.level or 0)
		state.detectionAt = os.clock()
		state.detectionSource = d.source
		state.detectionPos = Vector2.new(d.x or 0, d.z or 0)
	end)
	RunService.RenderStepped:Connect(step)
end

function HudController.state()
	return state
end

function HudController.hideVehicle()
	refs.vehicle.Visible = false
end

function HudController.applyBootstrap(b)
	state.cash = b.cash or 0
	refs.cash.Text = fmt(state.cash)
	refs.cashNote.Text = if b.saveable then "saved" else "NOT SAVING this session"
	refs.cashNote.TextColor3 = if b.saveable then Theme.Muted else Theme.Warn
	if b.crew then
		setCrew(b.crew)
	end
	if type(b.convoy) == "table" and b.convoy.active then
		state.convoy = b.convoy
	end
	if type(b.worldEvents) == "table" then
		for _, e in pairs(b.worldEvents) do
			setWorldEvent(e)
		end
	end
	setSecurity({ level = b.securityLevel or 0, label = ({ [0] = "Quiet", [1] = "Suspicious", [2] = "Alert", [3] = "Lockdown" })[b.securityLevel or 0] })
end

return HudController
