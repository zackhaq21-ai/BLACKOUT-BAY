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

	-- Left: routes
	local left = Make.frame(panel, "Routes", UDim2.new(0.5, -8, 1, -90), UDim2.new(0, 0, 0, 34), Theme.Panel, 1)
	Make.list(left, 6)
	Make.label(left, "Head", "Three ways in. Pick one on the way; change your mind when it goes wrong.", Theme.Small, Theme.Muted)
	refs.routeList = left
	-- Right: crew
	local right = Make.frame(panel, "Crew", UDim2.new(0.5, -8, 1, -90), UDim2.new(0.5, 8, 0, 34), Theme.Panel, 1)
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
	local bottom = Make.frame(panel, "Bottom", UDim2.new(1, 0, 0, Theme.MinButton), UDim2.new(0, 0, 1, -Theme.MinButton), Theme.Panel, 1)
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
		if prompt:GetAttribute("Tag") == "Board" then
			BoardController.open()
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
