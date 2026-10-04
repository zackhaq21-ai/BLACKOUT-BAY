--!nonstrict
-- End-of-job results: what happened, what you kept, what you lost, what next.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Make = require(script.Parent.Parent.UI.Make)

local ResultsController = {}

local player = Players.LocalPlayer
local gui, panel
local refs: { [string]: any } = {}
local hideToken = 0

local function fmt(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GlasshouseResults"
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
	panel = Make.panel(gui, "Results", UDim2.new(0, 640, 0, 460), UDim2.new(0.5, -320, 0.5, -230))
	panel.BackgroundTransparency = 0.05
	Make.list(panel, 6)
	refs.headline = Make.label(panel, "Headline", "", Theme.Big, Theme.Gold, true)
	refs.reason = Make.label(panel, "Reason", "", Theme.Body, Theme.Muted)
	refs.value = Make.label(panel, "Value", "", Theme.Title, Theme.Accent, true)
	refs.payouts = Make.frame(panel, "Payouts", UDim2.new(1, 0, 0, 0), UDim2.new(), Theme.Panel, 1)
	refs.payouts.AutomaticSize = Enum.AutomaticSize.Y
	Make.list(refs.payouts, 2)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Story"
	scroll.Size = UDim2.new(1, 0, 0, 170)
	scroll.BackgroundColor3 = Theme.PanelAlt
	scroll.BackgroundTransparency = 0.4
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	Make.corner(scroll, 8)
	Make.padding(scroll, 6)
	Make.list(scroll, 1)
	refs.story = scroll
	refs.next = Make.label(panel, "Next", "", Theme.Small, Theme.Muted)
	refs.done = Make.button(panel, "Done", "Back to the street", Theme.Accent, function()
		ResultsController.hide()
	end)
end

function ResultsController.hide()
	gui.Enabled = false
	GuiService.SelectedObject = nil
end

function ResultsController.show(r)
	refs.headline.Text = r.headline or "Job closed"
	refs.headline.TextColor3 = if (r.deliveredValue or 0) > 0 then Theme.Gold else Theme.Alarm
	refs.reason.Text = string.format("%s · %d s · security peaked at %s%s", r.reason or "", math.floor(r.durationSeconds or 0), ({ [0] = "Quiet", [1] = "Suspicious", [2] = "Alert", [3] = "Lockdown" })[r.maxSecurityLevel or 0] or "?", if r.escalation then " (" .. r.escalation .. ")" else "")
	refs.value.Text = "Delivered: " .. fmt(r.deliveredValue or 0) .. (if r.xp then string.format("   ·   +%d XP", r.xp) else "")
	for _, ch in ipairs(refs.payouts:GetChildren()) do
		if ch:IsA("TextLabel") then
			ch:Destroy()
		end
	end
	for i, p in ipairs(r.payouts or {}) do
		local l = Make.label(refs.payouts, "P" .. i, string.format("%s · %d%% · <b>%s</b>%s", p.name, p.share, fmt(p.amount), if p.userId == player.UserId then "  ← you" else ""), Theme.Body, if p.userId == player.UserId then Theme.Accent else Theme.Text)
		l.LayoutOrder = i
	end
	for _, ch in ipairs(refs.story:GetChildren()) do
		if ch:IsA("TextLabel") then
			ch:Destroy()
		end
	end
	for i, line in ipairs(r.lines or {}) do
		local l = Make.label(refs.story, "L" .. i, string.format("<font color='#9aa3af'>%3ds</font>  %s", math.floor(line.t or 0), line.text), Theme.Small, Theme.kindColor(if line.kind == "stolen" or line.kind == "arrest" then "alarm" elseif line.kind == "deliver" then "good" elseif line.kind == "security" then "warn" else nil))
		if line.kind == "phase" or line.kind == "start" or line.kind == "close" then
			l.TextColor3 = Theme.Muted
		end
		l.LayoutOrder = i
	end
	refs.next.Text = r.next or ""
	gui.Enabled = true
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = refs.done
	end
	hideToken += 1
	local token = hideToken
	task.delay(Config.Mission.ResultsSeconds + 8, function()
		if token == hideToken then
			ResultsController.hide()
		end
	end)
end

function ResultsController.init()
	build()
	Net.event("Results").OnClientEvent:Connect(ResultsController.show)
end

return ResultsController
