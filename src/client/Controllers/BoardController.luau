--!nonstrict
-- The job board: route intel, crew management, payout split, start/close job. Opens from the board prompt.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Make = require(script.Parent.Parent.UI.Make)

local BoardController = {}

local player = Players.LocalPlayer
local gui, panel
local refs: { [string]: any } = {}
local crew = nil
local routes = {}
local open = false
local pendingShares = nil
local hideout = nil -- last HideoutState
local targets = {}
local tabs = {}
local currentTab = "Job"

local function fmt(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function hideoutSend(action, extra)
	local req = { action = action }
	if extra then
		for k, v in pairs(extra) do
			req[k] = v
		end
	end
	Net.event("HideoutRequest"):FireServer(req)
end

local function send(action, extra)
	local req = { action = action }
	if extra then
		for k, v in pairs(extra) do
			req[k] = v
		end
	end
	Net.event("CrewRequest"):FireServer(req)
end

local function rebuildCrew()
	local list = refs.memberList
	for _, ch in ipairs(list:GetChildren()) do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	if not crew then
		return
	end
	local isLeader = crew.leaderId == player.UserId
	refs.crewHeader.Text = string.format("%s · %d/%d · code <b>%s</b>", crew.unitLabel or "Crew", #crew.members, crew.maxSize or 5, crew.code or "")
	pendingShares = pendingShares or {}
	for i, m in ipairs(crew.members) do
		local key = tostring(m.userId)
		if pendingShares[key] == nil then
			pendingShares[key] = m.share
		end
		local row = Make.frame(list, "Row" .. i, UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(), Theme.PanelAlt, 0.3)
		Make.corner(row, 8)
		row.LayoutOrder = i
		local name = Make.label(row, "Name", (if m.isLeader then "★ " else "") .. m.name .. (if m.carrying then "  <font color='#ffd060'>" .. m.carrying .. "</font>" else ""), Theme.Body, Theme.Text, m.userId == player.UserId)
		name.Size = UDim2.new(0.5, 0, 1, 0)
		name.Position = UDim2.new(0, 8, 0, 0)
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.AutomaticSize = Enum.AutomaticSize.None
		local share = Make.label(row, "Share", tostring(pendingShares[key]) .. "%", Theme.Body, Theme.Gold, true)
		share.Size = UDim2.new(0, 56, 1, 0)
		share.Position = UDim2.new(0.5, 0, 0, 0)
		share.TextXAlignment = Enum.TextXAlignment.Center
		share.TextYAlignment = Enum.TextYAlignment.Center
		share.AutomaticSize = Enum.AutomaticSize.None
		if isLeader and #crew.members > 1 and not crew.jobActive then
			local function adjust(delta)
				-- Move percent from/to the largest other share so the total stays 100
				local other
				for _, o in ipairs(crew.members) do
					local ok = tostring(o.userId)
					if ok ~= key and (other == nil or pendingShares[ok] > pendingShares[other]) then
						other = ok
					end
				end
				if not other then
					return
				end
				local allowed = (delta > 0 and pendingShares[other] >= delta) or (delta < 0 and pendingShares[key] >= -delta)
				if allowed then
					pendingShares[key] += delta
					pendingShares[other] -= delta
				end
				rebuildCrew()
			end
			local minus = Make.button(row, "Minus", "−5", Theme.PanelAlt, function()
				adjust(-5)
			end)
			minus.TextColor3 = Theme.Text
			minus.Size = UDim2.new(0, 44, 0, 36)
			minus.Position = UDim2.new(0.5, 60, 0, 4)
			Make.stroke(minus)
			local plus = Make.button(row, "Plus", "+5", Theme.PanelAlt, function()
				adjust(5)
			end)
			plus.TextColor3 = Theme.Text
			plus.Size = UDim2.new(0, 44, 0, 36)
			plus.Position = UDim2.new(0.5, 108, 0, 4)
			Make.stroke(plus)
			if m.userId ~= player.UserId then
				local kick = Make.button(row, "Kick", "✕", Theme.Alarm, function()
					send("kick", { userId = m.userId })
				end)
				kick.Size = UDim2.new(0, 36, 0, 36)
				kick.Position = UDim2.new(1, -40, 0, 4)
			end
		end
	end
	refs.applySplit.Visible = isLeader and #crew.members > 1 and not crew.jobActive
	refs.leave.Visible = #crew.members > 1
	refs.start.Text = if crew.jobActive then "Job running" else (if #crew.members == 1 then "Start job (solo)" else "Start job (" .. #crew.members .. " players)")
	refs.start.BackgroundColor3 = if crew.jobActive then Theme.PanelAlt else Theme.Accent
	refs.close.Visible = crew.jobActive
	refs.splitNote.Text = if crew.jobActive then "Split is locked while the job runs." elseif isLeader then "Leader sets the split. It only decides delivered value: whoever holds a bag, holds it." else "The leader sets the split. If you disagree, leave before the job starts."
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GlasshouseBoard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function update()
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.7, 1.15)
	end
	update()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)

	panel = Make.panel(gui, "Board", UDim2.new(0, 860, 0, 520), UDim2.new(0.5, -430, 0.5, -260))
	panel.BackgroundTransparency = 0.05
	local title = Make.label(panel, "Title", "JOB BOARD — THE AURORA EXCHANGE", Theme.Title, Theme.Accent, true)
	title.Size = UDim2.new(1, -60, 0, 24)
	local closeBtn = Make.ghostButton(panel, "CloseBtn", "✕", function()
		BoardController.close()
	end)
	closeBtn.Size = UDim2.new(0, 44, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, -4)

	-- Tab bar
	local tabBar = Make.frame(panel, "Tabs", UDim2.new(1, -60, 0, 36), UDim2.new(0, 0, 0, 28), Theme.Panel, 1)
	Make.list(tabBar, 6, true)
	local jobTab = Make.frame(panel, "JobTab", UDim2.new(1, 0, 1, -70), UDim2.new(0, 0, 0, 70), Theme.Panel, 1)
	local hideoutTab = Make.frame(panel, "HideoutTab", UDim2.new(1, 0, 1, -70), UDim2.new(0, 0, 0, 70), Theme.Panel, 1)
	local raidTab = Make.frame(panel, "RaidTab", UDim2.new(1, 0, 1, -70), UDim2.new(0, 0, 0, 70), Theme.Panel, 1)
	tabs = { Job = jobTab, Hideout = hideoutTab, Raids = raidTab }
	for i, name in ipairs({ "Job", "Hideout", "Raids" }) do
		local b = Make.ghostButton(tabBar, "Tab" .. name, name, function()
			BoardController.showTab(name)
		end)
		b.Size = UDim2.new(0, 120, 1, 0)
		b.LayoutOrder = i
		refs["tab" .. name] = b
	end

	-- Left: routes
	local left = Make.frame(jobTab, "Routes", UDim2.new(0.5, -8, 1, -50), UDim2.new(0, 0, 0, 0), Theme.Panel, 1)
	Make.list(left, 6)
	Make.label(left, "Head", "Three ways in. Pick one on the way; change your mind when it goes wrong.", Theme.Small, Theme.Muted)
	refs.routeList = left
	-- Right: crew
	local right = Make.frame(jobTab, "Crew", UDim2.new(0.5, -8, 1, -50), UDim2.new(0.5, 8, 0, 0), Theme.Panel, 1)
	Make.list(right, 6)
	refs.crewHeader = Make.label(right, "Header", "Crew", Theme.Body, Theme.Text, true)
	refs.memberList = Make.frame(right, "Members", UDim2.new(1, 0, 0, 0), UDim2.new(), Theme.Panel, 1)
	refs.memberList.AutomaticSize = Enum.AutomaticSize.Y
	Make.list(refs.memberList, 4)
	refs.splitNote = Make.label(right, "SplitNote", "", Theme.Small, Theme.Muted)
	refs.applySplit = Make.ghostButton(right, "ApplySplit", "Apply split", function()
		send("setShares", { shares = pendingShares })
	end)
	local joinRow = Make.frame(right, "JoinRow", UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(), Theme.Panel, 1)
	refs.joinBox = Make.textbox(joinRow, "Code", "Crew code (4 letters)")
	refs.joinBox.Size = UDim2.new(0.6, -4, 1, 0)
	local joinBtn = Make.button(joinRow, "Join", "Join crew", Theme.Accent, function()
		send("join", { code = refs.joinBox.Text })
		refs.joinBox.Text = ""
	end)
	joinBtn.Size = UDim2.new(0.4, 0, 1, 0)
	joinBtn.Position = UDim2.new(0.6, 0, 0, 0)
	refs.leave = Make.ghostButton(right, "Leave", "Leave crew (keep what you carry)", function()
		send("leave")
	end)

	-- Bottom: start / close
	local bottom = Make.frame(jobTab, "Bottom", UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(0, 0, 1, -Theme.MinButton), Theme.Panel, 1)
	Make.list(bottom, 8, true)
	refs.start = Make.button(bottom, "Start", "Start job", Theme.Accent, function()
		Net.event("MissionRequest"):FireServer({ action = "start" })
		BoardController.close()
	end)
	refs.start.Size = UDim2.new(0.5, -4, 1, 0)
	refs.close = Make.ghostButton(bottom, "CloseJob", "Close job now (pay out what was delivered)", function()
		Net.event("MissionRequest"):FireServer({ action = "close" })
	end)
	refs.close.Size = UDim2.new(0.5, -4, 1, 0)

	-- Hideout tab: stash, tier, upgrade, bank, reports
	local hl = Make.frame(hideoutTab, "Left", UDim2.new(0.5, -8, 1, 0), UDim2.new(), Theme.Panel, 1)
	Make.list(hl, 6)
	refs.stashLine = Make.label(hl, "Stash", "", Theme.Title, Theme.Gold, true)
	refs.exposedLine = Make.label(hl, "Exposed", "", Theme.Small, Theme.Muted)
	refs.tierLine = Make.label(hl, "Tier", "", Theme.Body, Theme.Text, true)
	refs.upgrade = Make.button(hl, "Upgrade", "Upgrade", Theme.Accent, function()
		hideoutSend("upgrade")
	end)
	refs.bankNote = Make.label(hl, "BankNote", "", Theme.Small, Theme.Muted)
	local bankRow = Make.frame(hl, "BankRow", UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(), Theme.Panel, 1)
	refs.bankBox = Make.textbox(bankRow, "Amount", "Amount to bank")
	refs.bankBox.Size = UDim2.new(0.5, -4, 1, 0)
	local bankBtn = Make.button(bankRow, "Bank", "Bank", Theme.Gold, function()
		local n = tonumber(refs.bankBox.Text)
		if n then
			hideoutSend("bank", { amount = math.floor(n) })
			refs.bankBox.Text = ""
		end
	end)
	bankBtn.Size = UDim2.new(0.25, -2, 1, 0)
	bankBtn.Position = UDim2.new(0.5, 0, 0, 0)
	local bankAll = Make.ghostButton(bankRow, "BankAll", "All", function()
		if hideout and hideout.stash > 0 then
			hideoutSend("bank", { amount = hideout.stash })
		end
	end)
	bankAll.Size = UDim2.new(0.25, -2, 1, 0)
	bankAll.Position = UDim2.new(0.75, 2, 0, 0)
	refs.backendNote = Make.label(hl, "Backend", "", Theme.Small, Theme.Warn)
	local hr = Make.frame(hideoutTab, "Right", UDim2.new(0.5, -8, 1, 0), UDim2.new(0.5, 8, 0, 0), Theme.Panel, 1)
	Make.list(hr, 6)
	refs.reportsTitle = Make.label(hr, "Title", "Raid reports", Theme.Body, Theme.Text, true)
	local rs = Instance.new("ScrollingFrame")
	rs.Size = UDim2.new(1, 0, 1, -80)
	rs.BackgroundTransparency = 1
	rs.BorderSizePixel = 0
	rs.ScrollBarThickness = 6
	rs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rs.CanvasSize = UDim2.new()
	rs.Parent = hr
	Make.list(rs, 4)
	refs.reports = rs
	refs.markRead = Make.ghostButton(hr, "MarkRead", "Mark reports read", function()
		hideoutSend("markRead")
	end)

	-- Raids tab: target list
	local rl = Make.frame(raidTab, "List", UDim2.new(1, 0, 1, 0), UDim2.new(), Theme.Panel, 1)
	Make.list(rl, 6)
	Make.label(rl, "Head", "Everyone can see what you have. A raid takes a share of the stash above the protected floor; the owner's defences and the police push back. Online owners are raided at their own pier; others at the Breakwater Lockup.", Theme.Small, Theme.Muted)
	local ts = Instance.new("ScrollingFrame")
	ts.Size = UDim2.new(1, 0, 1, -90)
	ts.BackgroundTransparency = 1
	ts.BorderSizePixel = 0
	ts.ScrollBarThickness = 6
	ts.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ts.CanvasSize = UDim2.new()
	ts.Parent = rl
	Make.list(ts, 4)
	refs.targets = ts
	refs.refreshTargets = Make.ghostButton(rl, "Refresh", "Refresh targets", function()
		hideoutSend("listTargets")
	end)
	BoardController.showTab("Job")
end

function BoardController.showTab(name: string)
	currentTab = name
	for n, f in pairs(tabs) do
		f.Visible = n == name
		local b = refs["tab" .. n]
		if b then
			b.BackgroundColor3 = if n == name then Theme.Accent else Theme.PanelAlt
			b.TextColor3 = if n == name then Theme.Panel else Theme.Text
		end
	end
	if name == "Hideout" then
		hideoutSend("refresh")
	elseif name == "Raids" then
		hideoutSend("listTargets")
	end
end

local function renderHideout()
	if not hideout then
		return
	end
	local h = hideout
	refs.stashLine.Text = string.format("Stash: %s", fmt(h.stash))
	refs.exposedLine.Text = string.format("A raid could take %s right now (first %s is protected). Banked money can't be raided.", fmt(h.exposed or 0), fmt(h.floor or 0))
	refs.tierLine.Text = string.format("Hideout tier %d / %d", h.tier or 0, h.maxTier or 6)
	if h.nextCost then
		refs.upgrade.Text = string.format("Upgrade to tier %d — %s (%s)", (h.tier or 0) + 1, fmt(h.nextCost), h.nextDesc or "")
		refs.upgrade.Visible = true
	else
		refs.upgrade.Visible = false
	end
	refs.bankNote.Text = string.format("Bank stash into your wallet: %d%% fee, 2 min cooldown.", math.floor((h.bankFee or 0) * 100))
	refs.backendNote.Text = if h.backend == "memory" then "No DataStore in this session: the stash lives on this server only." else ""
	refs.reportsTitle.Text = string.format("Raid reports (%d unread)", h.unread or 0)
	for _, ch in ipairs(refs.reports:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	for i, r in ipairs(h.reports or {}) do
		local card = Make.frame(refs.reports, "R" .. i, UDim2.new(1, -8, 0, 0), UDim2.new(), Theme.PanelAlt, 0.3)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = i
		Make.corner(card, 8)
		Make.padding(card, 8)
		Make.list(card, 2)
		local ago = os.time() - (r.t or os.time())
		local when = if ago < 3600 then string.format("%d min ago", math.floor(ago / 60)) elseif ago < 86400 then string.format("%d h ago", math.floor(ago / 3600)) else string.format("%d d ago", math.floor(ago / 86400))
		Make.label(card, "Who", string.format("%s%s · %s", r.raiderName or "?", if r.crewNames and #r.crewNames > 1 then " + " .. tostring(#r.crewNames - 1) else "", when), Theme.Body, if i <= (h.unread or 0) then Theme.Alarm else Theme.Text, true)
		Make.label(card, "How", "Entry: " .. tostring(r.entry) .. (if r.defences and #r.defences > 0 then " · Defences: " .. table.concat(r.defences, ", ") else " · No defences triggered"), Theme.Small, Theme.Muted)
		Make.label(card, "What", string.format("Lost %s · Defences kept %s", fmt(r.lost or 0), fmt(r.retained or 0)), Theme.Small, if (r.lost or 0) > 0 then Theme.Alarm else Theme.Good)
		if r.recoveryUntil and r.recoveryUntil > os.time() then
			Make.label(card, "Rec", string.format("Recovery opportunity: %d min left (recovery missions arrive in a later milestone)", math.floor((r.recoveryUntil - os.time()) / 60)), Theme.Small, Theme.Gold)
		end
	end
end

local function renderTargets()
	for _, ch in ipairs(refs.targets:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	if #targets == 0 then
		local f = Make.frame(refs.targets, "Empty", UDim2.new(1, -8, 0, 40), UDim2.new(), Theme.PanelAlt, 0.3)
		Make.corner(f, 8)
		Make.padding(f, 8)
		Make.label(f, "T", "No hideouts worth raiding yet. Stashes above the protected floor show up here.", Theme.Small, Theme.Muted)
		return
	end
	for i, tg in ipairs(targets) do
		local row = Make.frame(refs.targets, "T" .. i, UDim2.new(1, -8, 0, 56), UDim2.new(), Theme.PanelAlt, 0.3)
		row.LayoutOrder = i
		Make.corner(row, 8)
		Make.padding(row, 6)
		local l = Make.label(row, "Name", string.format("<b>%s</b>  stash %s · tier %s · %s", tg.name, fmt(tg.stash), tostring(tg.tier or "?"), if tg.online then "online: " .. tostring(tg.where) else "away: " .. tostring(tg.where)), Theme.Body, Theme.Text)
		l.Size = UDim2.new(1, -120, 0, 20)
		l.AutomaticSize = Enum.AutomaticSize.None
		local l2 = Make.label(row, "Exposed", string.format("Up to %s on the table%s", fmt(tg.exposed or 0), if tg.raidActive then " · being raided now" else ""), Theme.Small, if (tg.exposed or 0) > 0 then Theme.Gold else Theme.Muted)
		l2.Position = UDim2.new(0, 0, 0, 22)
		l2.Size = UDim2.new(1, -120, 0, 18)
		l2.AutomaticSize = Enum.AutomaticSize.None
		local b = Make.button(row, "Raid", "Raid", if tg.raidActive then Theme.PanelAlt else Theme.Alarm, function()
			if not tg.raidActive then
				hideoutSend("startRaid", { userId = tg.userId })
				BoardController.close()
			end
		end)
		b.Size = UDim2.new(0, 100, 0, 40)
		b.Position = UDim2.new(1, -100, 0, 2)
		b.TextColor3 = Theme.Text
	end
end

local function fillRoutes()
	for _, ch in ipairs(refs.routeList:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	for i, r in ipairs(routes) do
		local card = Make.frame(refs.routeList, "Route" .. i, UDim2.new(1, 0, 0, 0), UDim2.new(), Theme.PanelAlt, 0.3)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = i + 1
		Make.corner(card, 8)
		Make.padding(card, 8)
		Make.list(card, 2)
		Make.label(card, "T", r.title, Theme.Body, Theme.Gold, true)
		Make.label(card, "S", r.summary, Theme.Small, Theme.Text)
	end
end

function BoardController.open()
	if open then
		return
	end
	open = true
	pendingShares = nil
	gui.Enabled = true
	send("refresh")
	Net.event("MissionRequest"):FireServer({ action = "refresh" })
	rebuildCrew()
	if currentTab == "Hideout" then
		renderHideout()
	elseif currentTab == "Raids" then
		renderTargets()
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = refs.start
	end
end

function BoardController.close()
	open = false
	gui.Enabled = false
	GuiService.SelectedObject = nil
end

function BoardController.isOpen(): boolean
	return open
end

function BoardController.init(bootstrap)
	build()
	routes = bootstrap.routes or {}
	crew = bootstrap.crew
	fillRoutes()
	rebuildCrew()
	Net.event("HideoutState").OnClientEvent:Connect(function(h)
		hideout = h
		if open and currentTab == "Hideout" then
			renderHideout()
		end
	end)
	Net.event("RaidTargets").OnClientEvent:Connect(function(d)
		targets = d.targets or {}
		if open and currentTab == "Raids" then
			renderTargets()
		end
	end)
	Net.event("CrewState").OnClientEvent:Connect(function(c)
		local changedMembers = not crew or #crew.members ~= #c.members or crew.jobActive ~= c.jobActive
		crew = c
		if changedMembers then
			pendingShares = nil
		end
		if open then
			rebuildCrew()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local tag = prompt:GetAttribute("Tag")
		if tag == "Board" then
			BoardController.open()
		elseif tag == "RaidSafe" and tostring(prompt:GetAttribute("UnitId")) == tostring(crew and crew.unitId) then
			BoardController.open()
			BoardController.showTab("Hideout")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if open and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			BoardController.close()
		end
		local _ = processed
	end)
end

return BoardController
