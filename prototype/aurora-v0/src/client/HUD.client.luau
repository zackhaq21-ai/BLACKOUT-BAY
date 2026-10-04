local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Glasshouse")
local Config = require(Shared:WaitForChild("Config"))
local net = Shared:WaitForChild("Net")
local command = net:WaitForChild("Command")
local stateEvent = net:WaitForChild("State")
local toastEvent = net:WaitForChild("Toast")
local C = {bg = Color3.fromRGB(16, 26, 38), panel = Color3.fromRGB(25, 40, 54), mint = Color3.fromRGB(98, 238, 201), muted = Color3.fromRGB(168, 186, 198), white = Color3.fromRGB(238, 243, 235), gold = Color3.fromRGB(255, 194, 103), red = Color3.fromRGB(255, 126, 123)}
local gui = Instance.new("ScreenGui"); gui.Name = "GlasshouseHUD"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = player:WaitForChild("PlayerGui")
local state, mode, catalogOpen, dismissed = nil, "Shuffle", false, false
local buttons, priceCache = {}, {}

local function frame(parent, size, position, color)
	local f = Instance.new("Frame"); f.Size = size; f.Position = position; f.BackgroundColor3 = color or C.panel
	f.BorderSizePixel = 0; f.Parent = parent
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = f
	return f
end
local function label(parent, text, size, position, color, fontSize)
	local t = Instance.new("TextLabel"); t.Size = size; t.Position = position
	t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = color or C.white
	t.Font = Enum.Font.Gotham; t.TextSize = fontSize or 15; t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Center; t.Parent = parent
	return t
end
local function button(parent, text, size, position, callback, primary)
	local b = Instance.new("TextButton"); b.Size = size; b.Position = position
	b.BackgroundColor3 = primary and C.mint or C.panel; b.TextColor3 = primary and C.bg or C.white
	b.Text = text; b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.TextWrapped = true; b.BorderSizePixel = 0
	b.AutoButtonColor = true; b.Selectable = true; b.Parent = parent
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
	b.Activated:Connect(callback); table.insert(buttons, b)
	return b
end

local top = frame(gui, UDim2.new(1, -32, 0, 74), UDim2.fromOffset(16, 12), C.bg)
local brand = label(top, Config.Title, UDim2.new(0.45, 0, 0, 31), UDim2.fromOffset(15, 7), C.mint, 23)
brand.Font = Enum.Font.GothamBlack
local tagline = label(top, "AURORA EXCHANGE  /  1–5 CREW", UDim2.new(0.55, 0, 0, 21), UDim2.fromOffset(15, 40), C.muted, 12)
local timer = label(top, "08:00", UDim2.fromOffset(92, 30), UDim2.new(1, -205, 0, 6), C.white, 24)
timer.Font = Enum.Font.GothamBold
local heatText = label(top, "HEAT 0", UDim2.fromOffset(95, 23), UDim2.new(1, -205, 0, 39), C.gold, 13)
button(top, "Brief / B", UDim2.fromOffset(92, 48), UDim2.new(1, -105, 0, 13), function() dismissed = not dismissed; catalogOpen = false end)

local tracker = frame(gui, UDim2.fromOffset(310, 156), UDim2.fromOffset(16, 96), C.bg)
local stage = label(tracker, "CONTRACT READY", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 10), C.mint, 13)
stage.Font = Enum.Font.GothamBold
local goal = label(tracker, "Start at the crew safehouse", UDim2.new(1, -24, 0, 54), UDim2.fromOffset(12, 38), C.white, 18)
local detail = label(tracker, "Every role can use every tool.", UDim2.new(1, -24, 0, 42), UDim2.fromOffset(12, 100), C.muted, 13)

local crewPanel = frame(gui, UDim2.fromOffset(248, 166), UDim2.new(1, -264, 0, 96), C.bg)
label(crewPanel, "CREW CHANNEL", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(12, 8), C.mint, 12)
local crewText = label(crewPanel, "", UDim2.new(1, -24, 1, -40), UDim2.fromOffset(12, 36), C.white, 13)
crewText.TextYAlignment = Enum.TextYAlignment.Top

local actionBar = frame(gui, UDim2.new(0.6, 0, 0, 62), UDim2.new(0.2, 0, 1, -92), C.bg)
local actionText = label(actionBar, "E / X / tap prompt · stay nearby to complete", UDim2.new(1, -24, 0, 31), UDim2.fromOffset(12, 6), C.white, 14)
actionText.TextXAlignment = Enum.TextXAlignment.Center
local progressBg = frame(actionBar, UDim2.new(1, -24, 0, 5), UDim2.fromOffset(12, 45), C.panel)
local progress = frame(progressBg, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), C.mint)
local toast = label(gui, "", UDim2.new(0.8, 0, 0, 66), UDim2.new(0.1, 0, 1, -170), C.gold, 17)
toast.TextXAlignment = Enum.TextXAlignment.Center; toast.TextStrokeTransparency = 0.2
local toastRevision = 0
toastEvent.OnClientEvent:Connect(function(message)
	if type(message) ~= "string" then return end
	toastRevision += 1; local revision = toastRevision; toast.Text = message
	task.delay(5, function() if toastRevision == revision then toast.Text = "" end end)
end)

local modal = frame(gui, UDim2.fromOffset(540, 490), UDim2.fromScale(0.5, 0.52), C.bg)
modal.AnchorPoint = Vector2.new(0.5, 0.5)
local header = label(modal, "THE AURORA EXCHANGE", UDim2.new(1, -40, 0, 34), UDim2.fromOffset(20, 14), C.mint, 21)
header.Font = Enum.Font.GothamBlack
local subtitle = label(modal, "RECOVER THE LIGHT. WRITE YOUR OWN EXIT.", UDim2.new(1, -40, 0, 30), UDim2.fromOffset(20, 50), C.muted, 12)
local scroll = Instance.new("ScrollingFrame"); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(20, 86); scroll.Size = UDim2.new(1, -40, 1, -160)
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = C.mint; scroll.CanvasSize = UDim2.fromOffset(0, 310); scroll.Parent = modal
local briefing = label(scroll, "", UDim2.new(1, -8, 0, 280), UDim2.fromOffset(0, 0), C.white, 16)
briefing.TextYAlignment = Enum.TextYAlignment.Top; briefing.LineHeight = 1.15
local catalog = Instance.new("Frame"); catalog.Size = UDim2.new(1, -8, 0, 460); catalog.BackgroundTransparency = 1; catalog.Visible = false; catalog.Parent = scroll
local catalogRows = {}
for i, item in ipairs(Config.Catalog) do
	local row = frame(catalog, UDim2.new(1, 0, 0, 66), UDim2.fromOffset(0, (i - 1) * 74))
	local chip = frame(row, UDim2.fromOffset(10, 42), UDim2.fromOffset(10, 12), Color3.fromRGB(unpack(item.Color)))
	chip.Name = "Color"
	label(row, item.Name, UDim2.new(1, -140, 0, 25), UDim2.fromOffset(30, 8), C.white, 15)
	local caption = label(row, item.Kind .. " / preview", UDim2.new(1, -140, 0, 24), UDim2.fromOffset(30, 33), C.muted, 12)
	local b = button(row, "Preview", UDim2.fromOffset(100, 46), UDim2.new(1, -110, 0, 10), function()
		if not state then return end
		if state.entitlements[item.Id] then command:FireServer("Equip", item.Id)
		elseif state.commerce and item.PassId > 0 and priceCache[item.Id] then command:FireServer("Buy", item.Id)
		else toast.Text = type(item.EarnedXP) == "number" and ("Earn " .. item.EarnedXP .. " total XP to keep this cosmetic.") or "Preview only. Robux purchasing is disabled."; toastRevision += 1 end
	end)
	catalogRows[item.Id] = {caption = caption, button = b}
end
local readyButton = button(modal, "Ready", UDim2.new(0.25, -16, 0, 46), UDim2.new(0, 20, 1, -60), function() command:FireServer("Ready") end)
local startButton = button(modal, "Start run", UDim2.new(0.31, -12, 0, 46), UDim2.new(0.25, 8, 1, -60), function() command:FireServer("Start", mode) end, true)
local modeButton
modeButton = button(modal, "Shuffle", UDim2.new(0.22, -10, 0, 46), UDim2.new(0.56, 4, 1, -60), function()
	mode = mode == "Shuffle" and "Daily" or "Shuffle"; modeButton.Text = mode
end)
button(modal, "Looks", UDim2.new(0.22, -20, 0, 46), UDim2.new(0.78, 0, 1, -60), function() catalogOpen = not catalogOpen; scroll.CanvasPosition = Vector2.zero end)

local function timeString(seconds)
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function render(data)
	state = data
	timer.Text = timeString(data.timeLeft)
	heatText.Text = (data.alarmed and "LOCKDOWN " or "HEAT ") .. data.heat
	heatText.TextColor3 = data.heat >= 75 and C.red or C.gold
	tagline.Text = "AURORA EXCHANGE  /  " .. #data.roster .. " OF 5 CREW"
	local lines = {}
	for _, m in ipairs(data.roster) do
		table.insert(lines, (m.id == data.host and "◆ " or "• ") .. m.name .. (m.captured and " [RECOVER]" or "") .. "\n  " .. (data.status == "Active" and m.role or (m.ready and "Ready" or "Choosing loadout")))
	end
	crewText.Text = table.concat(lines, "\n")
	stage.Text = data.status == "Active" and ("CONTRACT / " .. string.upper(data.mode) .. " " .. data.seed) or "CONTRACT / " .. string.upper(data.status)
	if data.status == "Lobby" then goal.Text = "Your crew. Your approach."; detail.Text = "Solo works. Every tool is included."
	elseif data.status ~= "Active" then goal.Text = data.result or "Contract complete"; detail.Text = "+" .. data.reward .. " XP · retries are free"
	elseif not data.member then goal.Text = "Joining the next crew"; detail.Text = "This run is underway. Explore the safehouse."
	elseif data.member.captured then goal.Text = "Recover at the coral pad"; detail.Text = "Free re-entry costs 15 mission seconds."
	elseif not data.member.entered then goal.Text = "Choose one of three entrances"; detail.Text = data.watchedEntrance .. " is watched: +12 heat."
	elseif data.core == "Carried" then
		goal.Text = data.carrier == player.UserId and "Get the core to extraction" or "Cover the core carrier"
		detail.Text = (data.heat >= 75 and "Tram closed. " or "Tram open. ") .. (data.curator == "Released" and "Canal open. " or "") .. "Tunnel always open."
	elseif data.core == "Dropped" then goal.Text = "Recover the dropped core"; detail.Text = "Find the mint CORE marker in the gallery."
	elseif data.vaultOpen then goal.Text = "Take the Aurora core"; detail.Text = "The " .. data.vault .. " vault is open."
	else goal.Text = "Signals " .. data.signals .. "/" .. data.needed .. "  ·  " .. data.vault .. " vault"
		detail.Text = data.powerOff and "Light grid down. Finish signals, then open quietly." or "Cut the light grid. Or force the vault: +65 heat."
	end
	if data.job then
		actionText.Text = data.job.text .. "  " .. string.format("%.1fs", data.job.remaining)
		progress.Size = UDim2.fromScale(math.clamp(1 - data.job.remaining / data.job.duration, 0, 1), 1)
		progress.BackgroundColor3 = C.mint
	elseif data.exposure > 0 then
		actionText.Text = "SPOTTED — break line of sight or use STASIS"
		progress.Size = UDim2.fromScale(data.exposure / 3.8, 1); progress.BackgroundColor3 = C.red
	else
		actionText.Text = data.member and ("E / X / tap · stay nearby · stasis " .. data.member.stasis .. "/3") or "E / X / tap a prompt · B for briefing"
		progress.Size = UDim2.fromScale(0, 1)
	end
	local isHost = data.host == player.UserId
	startButton.Text = data.status == "Active" and "In progress" or (isHost and "Start run" or "Leader starts")
	startButton.Active = isHost and data.status ~= "Active"; startButton.AutoButtonColor = startButton.Active
	startButton.BackgroundColor3 = startButton.Active and C.mint or C.panel
	local myReady = false
	for _, m in ipairs(data.roster) do if m.id == player.UserId then myReady = m.ready end end
	readyButton.Text = myReady and "Ready ✓" or "Ready"
	if data.status == "Active" then
		briefing.Text = "THE PLAN\n\n1  Pick an entrance. The watched route adds heat.\n2  Sync " .. data.needed .. " signals + cut the light grid.\n3  Open the " .. data.vault .. " vault, or force it for +65 heat.\n4  Take the core. Leave through the front getaway gate.\n5  Drive or walk to an exit. Gather the crew within 20 studs.\n\nRelease the curator for the canal route. Capture gains a signal but adds heat. Red patrol lines show direction; cover breaks sight. Three free stasis charges reset each run.\n\nTRAM: northeast coast, closes at 75 heat.\nCANAL: northwest coast, requires release.\nTUNNEL: west safehouse road, always available."
	else
		briefing.Text = (data.result and (data.result .. "\n+" .. data.reward .. " XP this run\n\n") or "A stolen light core. One island. Three ways in.\n\n") .. "Start SOLO, or bring up to four partners. Partners choose Ready; the crew leader starts. Roles guide teamwork — anyone can complete every objective.\n\nSHUFFLE changes the watched entrance, vault and patrol start. DAILY repeats today's UTC contract. No simultaneous switches.\n\nWASD / thumbstick: move or drive\nE / gamepad X / tap: interact\nF / gamepad Y: alternative choice\nSpace / jump: leave a vehicle\nB: open or close this briefing\n\n" .. data.xp .. " XP · " .. data.wins .. " escapes\nProgress: " .. data.saveStatus .. "\nLocal Studio progress resets when the session stops.\n\nLooks are optional. Essential tools and retries are free. Paid looks, when eventually enabled, stay owned after failure."
	end
	for _, item in ipairs(Config.Catalog) do
		local row = catalogRows[item.Id]
		local owned = data.entitlements[item.Id] == true
		row.caption.Text = owned and (item.Kind .. " / permanently unlocked") or (type(item.EarnedXP) == "number" and (item.EarnedXP .. " total XP") or "Robux cosmetic / preview only")
		row.button.Text = owned and ((data.equipped == item.Id or data.decor == item.Id) and "Equipped" or "Equip") or "Preview"
		if not owned and data.commerce and item.PassId > 0 and priceCache[item.Id] then row.button.Text = "R$ " .. priceCache[item.Id] end
	end
end
stateEvent.OnClientEvent:Connect(render)

local lastStatus
game:GetService("RunService").RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera; if not camera then return end
	local viewport = camera.ViewportSize
	local compact = viewport.X < 760
	crewPanel.Visible = not compact
	tracker.Size = UDim2.fromOffset(compact and math.min(310, viewport.X - 32) or 310, compact and 136 or 156)
	detail.Position = UDim2.fromOffset(12, compact and 87 or 100)
	brand.TextSize = compact and 17 or 23
	tagline.TextSize = compact and 10 or 12
	timer.Position = UDim2.new(1, compact and -185 or -205, 0, 6); timer.TextSize = compact and 20 or 24
	heatText.Position = UDim2.new(1, compact and -185 or -205, 0, 39)
	modal.Size = UDim2.fromOffset(math.min(540, viewport.X - 30), math.min(490, viewport.Y - 105))
	actionBar.Size = UDim2.new(compact and 0.82 or 0.6, 0, 0, 62)
	actionBar.Position = UDim2.new(compact and 0.09 or 0.2, 0, 1, compact and -122 or -92)
	if state and lastStatus ~= state.status then
		dismissed = state.status == "Active"; catalogOpen = false; lastStatus = state.status
	end
	modal.Visible = not dismissed
	briefing.Visible = not catalogOpen; catalog.Visible = catalogOpen
	header.Text = catalogOpen and "CREW LOOKS" or "THE AURORA EXCHANGE"
	subtitle.Text = catalogOpen and "STYLE ONLY · NO PAID ADVANTAGE · OWN IT ONCE" or "RECOVER THE LIGHT. WRITE YOUR OWN EXIT."
	scroll.CanvasSize = UDim2.fromOffset(0, catalogOpen and 450 or (state and state.status == "Active" and 450 or 520))
	briefing.Size = UDim2.new(1, -8, 0, scroll.CanvasSize.Y.Offset)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.ButtonSelect then
		dismissed = not dismissed
		if not dismissed and UserInputService.GamepadEnabled then GuiService.SelectedObject = readyButton end
	elseif input.KeyCode == Enum.KeyCode.Backspace then command:FireServer("Cancel") end
end)
-- No hardcoded Robux prices. Only query configured passes after an explicitly enabled release.
task.spawn(function()
	if not Config.CommerceEnabled then return end
	for _, item in ipairs(Config.Catalog) do
		if item.PassId > 0 then
			local ok, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, item.PassId, Enum.InfoType.GamePass)
			if ok and info.IsForSale and type(info.PriceInRobux) == "number" then priceCache[item.Id] = info.PriceInRobux end
		end
	end
end)
command:FireServer("Sync")
