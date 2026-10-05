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
local profileState = nil -- last ProfileState
local targets = {}
local wanted = nil
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
	local looksTab = Make.frame(panel, "LooksTab", UDim2.new(1, 0, 1, -70), UDim2.new(0, 0, 0, 70), Theme.Panel, 1)
	local wantedTab = Make.frame(panel, "WantedTab", UDim2.new(1, 0, 1, -70), UDim2.new(0, 0, 0, 70), Theme.Panel, 1)
	tabs = { Job = jobTab, Hideout = hideoutTab, Raids = raidTab, Wanted = wantedTab, Looks = looksTab }
	for i, name in ipairs({ "Job", "Hideout", "Raids", "Wanted", "Looks" }) do
		local b = Make.ghostButton(tabBar, "Tab" .. name, name, function()
			BoardController.showTab(name)
		end)
		b.Size = UDim2.new(0, 92, 1, 0)
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
	-- Getaway kit: fake bags (approved deception). Decoy cars need no button: roll out a second car and
	-- send it the loud way with a fake in the trunk.
	Make.label(right, "KitHead", "Getaway kit", Theme.Body, Theme.Text, true)
	Make.label(right, "KitNote", "Fake bags cost 150 from the leader's stash, max 3 out. They look real from a distance and are always light. Split real loot between two cars and send a decoy the exposed way.", Theme.Small, Theme.Muted)
	local kit = Make.frame(right, "Kit", UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(), Theme.Panel, 1)
	Make.list(kit, 4, true)
	for i, mimic in ipairs({ "Trinket", "Relic", "Jewel", "Core", "Bundle" }) do
		local b = Make.ghostButton(kit, "Fake" .. mimic, "Fake " .. (if mimic == "Bundle" then "stash" else mimic), function()
			hideoutSend("fake", { mimic = mimic })
		end)
		b.Size = UDim2.new(0.2, -4, 1, 0)
		b.TextSize = Theme.Small
		b.LayoutOrder = i
	end

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
	Make.label(rl, "Head", "Everyone can see what you have. A cracked safe gives up the owner's ENTIRE stash; their defences and the police push back, and anything you leave inside goes back to them. Online owners are raided at their own pier; others at the Breakwater Lockup.", Theme.Small, Theme.Muted)
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

	-- Looks tab: earned/owned suits. Style only; never a gameplay advantage.
	local lk = Make.frame(looksTab, "Looks", UDim2.new(1, 0, 1, 0), UDim2.new(), Theme.Panel, 1)
	Make.list(lk, 6)
	refs.looksHead = Make.label(lk, "Head", "", Theme.Body, Theme.Text, true)
	Make.label(lk, "Note", "Looks are permanent once earned or owned. Raids and lost runs never take them. No paid look changes stats, hitboxes or visibility. Purchasing is disabled in this build.", Theme.Small, Theme.Muted)
	local ls = Instance.new("ScrollingFrame")
	ls.Size = UDim2.new(1, 0, 1, -70)
	ls.BackgroundTransparency = 1
	ls.BorderSizePixel = 0
	ls.ScrollBarThickness = 6
	ls.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ls.CanvasSize = UDim2.new()
	ls.Parent = lk
	Make.list(ls, 4)
	refs.looks = ls
	-- Wanted tab: bounties
	local wt = Make.frame(wantedTab, "Wanted", UDim2.new(1, 0, 1, 0), UDim2.new(), Theme.Panel, 1)
	Make.list(wt, 6)
	Make.label(wt, "Head", "Bounties are paid from your stash and stack on the target until someone outside their crew takes them down on foot (hold on them for 2 s within 7 studs). Contributors and crewmates can't claim; a target can't be claimed again for 5 minutes. Being taken down drops your bag.", Theme.Small, Theme.Muted)
	local amountRow = Make.frame(wt, "AmountRow", UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(), Theme.Panel, 1)
	refs.bountyBox = Make.textbox(amountRow, "Amount", "Bounty amount (min 100)")
	refs.bountyBox.Size = UDim2.new(0.5, 0, 1, 0)
	local ws = Instance.new("ScrollingFrame")
	ws.Size = UDim2.new(1, 0, 1, -130)
	ws.BackgroundTransparency = 1
	ws.BorderSizePixel = 0
	ws.ScrollBarThickness = 6
	ws.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ws.CanvasSize = UDim2.new()
	ws.Parent = wt
	Make.list(ws, 4)
	refs.wantedList = ws
	Make.ghostButton(wt, "RefreshWanted", "Refresh", function()
		hideoutSend("listWanted")
	end)
	BoardController.showTab("Job")
end

local function renderWanted()
	for _, ch in ipairs(refs.wantedList:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	local rows = wanted and wanted.wanted or {}
	if #rows == 0 then
		local f = Make.frame(refs.wantedList, "Empty", UDim2.new(1, -8, 0, 40), UDim2.new(), Theme.PanelAlt, 0.3)
		Make.corner(f, 8)
		Make.padding(f, 8)
		Make.label(f, "T", "Nobody else is on this server right now.", Theme.Small, Theme.Muted)
		return
	end
	for i, w in ipairs(rows) do
		local row = Make.frame(refs.wantedList, "W" .. i, UDim2.new(1, -8, 0, 50), UDim2.new(), Theme.PanelAlt, 0.3)
		row.LayoutOrder = i
		Make.corner(row, 8)
		Make.padding(row, 6)
		local l = Make.label(row, "Name", string.format("<b>%s</b>  %s%s", w.name, if (w.bounty or 0) > 0 then "BOUNTY " .. fmt(w.bounty) else "no bounty", if w.crewmate then " · crewmate" elseif w.jailed then " · in a cell" else ""), Theme.Body, if (w.bounty or 0) > 0 then Theme.Alarm else Theme.Text)
		l.Size = UDim2.new(1, -130, 1, 0)
		l.TextYAlignment = Enum.TextYAlignment.Center
		l.AutomaticSize = Enum.AutomaticSize.None
		if not w.crewmate then
			local b = Make.button(row, "Place", "Add bounty", Theme.Gold, function()
				local n = tonumber(refs.bountyBox.Text)
				if n then
					hideoutSend("placeBounty", { userId = w.userId, amount = math.floor(n) })
					refs.bountyBox.Text = ""
				end
			end)
			b.Size = UDim2.new(0, 120, 0, 36)
			b.Position = UDim2.new(1, -120, 0, 1)
			b.TextColor3 = Theme.Panel
		end
	end
end

local function renderLooks()
	if not profileState then
		return
	end
	local ps = profileState
	refs.looksHead.Text = string.format("%d XP · %d escapes · %d jobs%s", ps.xp or 0, ps.wins or 0, ps.jobs or 0, if ps.saveable then "" else " · NOT SAVING this session")
	for _, ch in ipairs(refs.looks:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	for i, item in ipairs(ps.catalog or {}) do
		local row = Make.frame(refs.looks, "L" .. i, UDim2.new(1, -8, 0, 56), UDim2.new(), Theme.PanelAlt, 0.3)
		row.LayoutOrder = i
		Make.corner(row, 8)
		Make.padding(row, 6)
		local chip = Make.frame(row, "Chip", UDim2.new(0, 10, 1, 0), UDim2.new(), Color3.fromRGB(item.Color[1], item.Color[2], item.Color[3]), 0)
		Make.corner(chip, 4)
		local owned = ps.entitlements and ps.entitlements[item.Id] == true
		local equipped = ps.equipped == item.Id
		local caption = if owned then "permanently yours" elseif type(item.EarnedXP) == "number" then string.format("earn %d XP", item.EarnedXP) else "Robux look · preview only"
		local l = Make.label(row, "Name", string.format("<b>%s</b>  %s · %s", item.Name, item.Kind, caption), Theme.Body, if owned then Theme.Text else Theme.Muted)
		l.Position = UDim2.new(0, 18, 0, 0)
		l.Size = UDim2.new(1, -140, 1, 0)
		l.TextYAlignment = Enum.TextYAlignment.Center
		l.AutomaticSize = Enum.AutomaticSize.None
		local b = Make.button(row, "Act", if equipped then "Equipped" elseif owned then "Equip" else "Preview", if owned and not equipped then Theme.Accent else Theme.PanelAlt, function()
			if owned then
				Net.event("ProfileRequest"):FireServer({ action = "equip", item = item.Id })
			else
				Net.event("ProfileRequest"):FireServer({ action = "buy", item = item.Id })
			end
		end)
		b.Size = UDim2.new(0, 110, 0, 40)
		b.Position = UDim2.new(1, -110, 0, 2)
		b.TextColor3 = if owned and not equipped then Theme.Panel else Theme.Text
	end
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
	elseif name == "Looks" then
		Net.event("ProfileRequest"):FireServer({ action = "refresh" })
	elseif name == "Wanted" then
		hideoutSend("listWanted")
	end
end

local function renderHideout()
	if not hideout then
		return
	end
	local h = hideout
	refs.stashLine.Text = string.format("Stash: %s", fmt(h.stash))
	refs.exposedLine.Text = if (h.stash or 0) > 0 then string.format("HIGH STAKES: a cracked safe takes ALL of it (%s). Your defences and the police are the only protection%s.", fmt(h.exposed or 0), if h.bankingEnabled then "; banked money can't be raided" else "") else "Your stash is empty. Everything you earn lands here, and a raid can take all of it."
	refs.tierLine.Text = string.format("Hideout tier %d / %d%s", h.tier or 0, h.maxTier or 6, if (h.bounty or 0) > 0 then string.format("   ·   BOUNTY ON YOU: %s", fmt(h.bounty)) else "")
	if h.nextCost then
		refs.upgrade.Text = string.format("Upgrade to tier %d — %s (%s)", (h.tier or 0) + 1, fmt(h.nextCost), h.nextDesc or "")
		refs.upgrade.Visible = true
	else
		refs.upgrade.Visible = false
	end
	refs.bankNote.Text = if h.bankingEnabled then string.format("Bank stash into your wallet: %d%% fee, 2 min cooldown. The wallet is never raided.", math.floor((h.bankFee or 0) * 100)) else "Banking is off on this server."
	refs.bankBox.Parent.Visible = h.bankingEnabled ~= false
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
		local serverNow = h.now or os.time()
		local recovered = r.recovered or 0
		local owed = math.max(0, (r.lost or 0) - recovered)
		if r.recovery then
			Make.label(card, "What", string.format("They recovered %s from you", fmt(r.lost or 0)), Theme.Small, Theme.Alarm)
		else
			Make.label(card, "What", string.format("Lost %s · Defences kept %s · Recovered %s", fmt(r.lost or 0), fmt(r.retained or 0), fmt(recovered)), Theme.Small, if owed > 0 then Theme.Alarm else Theme.Good)
		end
		for ci = math.max(1, #(r.clues or {}) - 3), #(r.clues or {}) do
			local c = r.clues[ci]
			Make.label(card, "Clue" .. ci, "· " .. tostring(c.text), Theme.Small, Theme.Muted)
		end
		if r.recoveryUntil and r.recoveryUntil > serverNow and owed > 0 and r.raidId then
			local btn = Make.button(card, "Recover", string.format("Recover %s — trail goes cold in %d min", fmt(owed), math.max(1, math.floor((r.recoveryUntil - serverNow) / 60))), Theme.Gold, function()
				hideoutSend("recover", { raidId = r.raidId })
				BoardController.close()
			end)
			btn.TextColor3 = Theme.Panel
		elseif r.recoveryUntil and owed > 0 then
			Make.label(card, "Cold", "Trail went cold: the recovery window closed.", Theme.Small, Theme.Muted)
		end
		if not r.recovery and r.raider and tonumber(r.raider) then
			local bb = Make.ghostButton(card, "Bounty", "Put 500 on " .. tostring(r.raiderName), function()
				hideoutSend("placeBounty", { userId = tonumber(r.raider), amount = 500 })
			end)
			bb.TextSize = Theme.Small
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
		local l2 = Make.label(row, "Exposed", string.format("Whole stash on the table: %s%s", fmt(tg.exposed or 0), if tg.raidActive then " · being raided now" else ""), Theme.Small, if (tg.exposed or 0) > 0 then Theme.Gold else Theme.Muted)
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
	elseif currentTab == "Looks" then
		renderLooks()
	elseif currentTab == "Wanted" then
		renderWanted()
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
	Net.event("WantedList").OnClientEvent:Connect(function(d)
		wanted = d
		if open and currentTab == "Wanted" then
			renderWanted()
		end
	end)
	Net.event("ProfileState").OnClientEvent:Connect(function(ps)
		profileState = ps
		if open and currentTab == "Looks" then
			renderLooks()
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
