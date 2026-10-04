--!nonstrict
-- Physical loot in the world. The LootLedger is the single source of truth; this service renders each
-- item's state (in a case, carried on a back, dropped on the ground, stowed in a trunk) and validates
-- every hand-off. Anyone can pick up a dropped bag: that is where betrayal and interception live.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Net = require(ReplicatedStorage.Shared.Net)
local LootLedger = require(ReplicatedStorage.Shared.Core.LootLedger)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Comms = require(script.Parent.Comms)

local LootService = { ctx = nil :: any }

local ledger
local visuals = {} -- itemId -> Instance
local listeners = {}
local itemCounter = 0
local lastCrewTouch = {} -- itemId -> crewId that last held it (for theft attribution)
local caseState = {} -- caseId -> { cut = bool, itemId = string? }

local KIND_COLORS = {
	Trinket = Palette.SeaGlass,
	Relic = Palette.WarmWood,
	Jewel = Palette.Gold,
	Core = Palette.SeaGlass,
	Bundle = Palette.Gold,
	Fake = Palette.Gold,
}

function LootService.init(ctx)
	LootService.ctx = ctx
	ledger = LootLedger.new(os.clock)
	LootService.ledger = ledger
end

function LootService.onEvent(fn)
	table.insert(listeners, fn)
end

local function emit(kind: string, data)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, kind, data)
	end
end

local function spec(kind: string)
	return Config.Economy.Loot[kind]
end

local function playerFromKey(key: string): Player?
	return Players:GetPlayerByUserId(tonumber(key) or 0)
end

-- Visual model for an item (bag or crate). Returns a Model with PrimaryPart.
local function makeVisual(item): Model
	local m = Instance.new("Model")
	m.Name = "Loot_" .. item.id
	m:SetAttribute("ItemId", item.id)
	local looksLike = item.mimic or item.kind
	local color = KIND_COLORS[looksLike] or Palette.SeaGlass
	local body
	if item.weight == "Heavy" or looksLike == "Core" then
		body = Instance.new("Part")
		body.Size = Vector3.new(3, 3, 3)
		body.Material = Enum.Material.Metal
		body.Color = Palette.Industrial
		local core = Instance.new("Part")
		core.Name = "Core"
		core.Size = Vector3.new(2, 2, 2)
		core.Material = Enum.Material.Neon
		core.Color = color
		core.CanCollide = false
		core.Massless = true
		core.Parent = m
		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 2
		light.Range = 16
		light.Parent = core
		core.CFrame = CFrame.new()
		body.CFrame = CFrame.new()
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = core
		w.Parent = body
	else
		body = Instance.new("Part")
		body.Size = Vector3.new(2.2, 1.6, 1.2)
		body.Material = Enum.Material.Fabric
		body.Color = color
	end
	body.Name = "Body"
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = m
	m.PrimaryPart = body
	-- Label that reads at a distance: name and value
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(140, 36)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.MaxDistance = 45
	bb.AlwaysOnTop = false
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = string.format("%s\n%d", item.label, if item.kind == "Fake" then (item.mimicValue or 0) else item.value)
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0.2
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.Parent = bb
	bb.Parent = body
	return m
end

local function clearVisual(itemId: string)
	local v = visuals[itemId]
	if v then
		v:Destroy()
		visuals[itemId] = nil
	end
end

local function setAnchoredCollide(m: Model, anchored: boolean, collide: boolean)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
			d.CanCollide = collide and d.Name == "Body"
			d.Massless = not collide
		end
	end
end

local function renderInCase(item, caseRef)
	clearVisual(item.id)
	local m = makeVisual(item)
	m:PivotTo(caseRef.cframe)
	setAnchoredCollide(m, true, false)
	m.Parent = LootService.ctx.world.lootFolder
	visuals[item.id] = m
	local state = caseState[caseRef.id]
	if state and state.cut then
		Builder.prompt(m.PrimaryPart, "Take " .. item.label, "Display case (glass cut)", 0, "LootTake", { ItemId = item.id })
	end
end

local function renderDropped(item, position: Vector3)
	clearVisual(item.id)
	local m = makeVisual(item)
	m:PivotTo(CFrame.new(position))
	setAnchoredCollide(m, false, true)
	m.Parent = LootService.ctx.world.lootFolder
	m.PrimaryPart:SetNetworkOwner(nil)
	visuals[item.id] = m
	Builder.prompt(m.PrimaryPart, "Pick up " .. item.label, if item.weight == "Heavy" then "Heavy — slow, no climbing" else "Light bag", 0, "LootPickup", { ItemId = item.id })
	-- If a bag ever ends up below the island, recover it to its last safe spot
	task.delay(8, function()
		if visuals[item.id] == m and m.PrimaryPart and m.PrimaryPart.Position.Y < -15 then
			m:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
		end
	end)
end

local function renderCarried(item, player: Player)
	clearVisual(item.id)
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso then
		return
	end
	local m = makeVisual(item)
	local offset = if item.weight == "Heavy" then CFrame.new(0, 0.6, 2.2) else CFrame.new(0, 0.2, 1.3)
	m:PivotTo(torso.CFrame * offset)
	setAnchoredCollide(m, false, false)
	local w = Instance.new("WeldConstraint")
	w.Part0 = torso
	w.Part1 = m.PrimaryPart
	w.Parent = m.PrimaryPart
	m.Parent = char
	visuals[item.id] = m
end

local function renderInVehicle(item, vehicle: Model, slot: number)
	clearVisual(item.id)
	local trunk = vehicle:FindFirstChild("Trunk")
	if not trunk then
		return
	end
	local m = makeVisual(item)
	m:PivotTo(trunk.CFrame * CFrame.new(0, 0.8 + (slot - 1) * 0.5, 0))
	setAnchoredCollide(m, false, false)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = trunk
	w.Part1 = m.PrimaryPart
	w.Parent = m.PrimaryPart
	m.Parent = vehicle
	visuals[item.id] = m
end

local function sendCarry(player: Player)
	local items = ledger:carriedBy(Comms.key(player))
	local item = items[1]
	Net.event("Carry"):FireClient(player, if item then { itemId = item.id, label = item.label, weight = item.weight, value = item.value } else {})
	player:SetAttribute("Carrying", if item then item.label else nil)
	LootService.ctx.services.Movement.apply(player)
end

local function crewIdOf(player: Player): string?
	local crew = LootService.ctx.services.Crew.crewOf(player)
	return crew and crew.id or nil
end

-- Public queries
function LootService.carriedBy(player: Player)
	return ledger:carriedBy(Comms.key(player))
end

function LootService.carriedLabel(player: Player): string?
	local items = ledger:carriedBy(Comms.key(player))
	return items[1] and items[1].label or nil
end

function LootService.carriedLabels(player: Player): { string }
	local out = {}
	for _, item in ipairs(ledger:carriedBy(Comms.key(player))) do
		table.insert(out, item.label)
	end
	return out
end

function LootService.isCarryingHeavy(player: Player): boolean
	for _, item in ipairs(ledger:carriedBy(Comms.key(player))) do
		if item.weight == "Heavy" then
			return true
		end
	end
	return false
end

function LootService.get(itemId: string)
	return ledger:get(itemId)
end

function LootService.inVehicle(vehicleId: string)
	return ledger:inVehicle(vehicleId)
end

-- Transitions
function LootService.pickUp(player: Player, itemId: string, source: string): boolean
	local item = ledger:get(itemId)
	if not item then
		return false
	end
	local key = Comms.key(player)
	local previousCrew = lastCrewTouch[itemId]
	local fromState = item.state
	local ok, err = ledger:pickUp(itemId, key, Config.Player.MaxCarry)
	if not ok then
		Comms.toast(player, if err == "hands full" then "Your hands are full. Drop what you're carrying first." else "Can't take that right now.", "warn")
		return false
	end
	local myCrew = crewIdOf(player)
	if item.kind == "Fake" and item.origin ~= "fake:" .. tostring(myCrew) and not item.revealed then
		item.revealed = true
		item.label = Config.Economy.Loot.Fake.label
		item.mimic = nil
		item.mimicValue = 0
		Comms.toast(player, "This bag is a FAKE. Someone wanted you chasing it.", "warn")
	end
	renderCarried(item, player)
	sendCarry(player)
	Comms.cue(player, "Pickup")
	emit("pickup", { player = player, item = item, fromState = fromState, source = source, crewId = myCrew })
	if fromState == "Dropped" and previousCrew and previousCrew ~= myCrew then
		emit("stolen", { player = player, item = item, fromCrewId = previousCrew, crewId = myCrew })
	end
	lastCrewTouch[itemId] = myCrew
	return true
end

function LootService.drop(player: Player, note: string?): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local key = Comms.key(player)
	local items = ledger:carriedBy(key)
	if #items == 0 then
		return false
	end
	local pos = root.Position + root.CFrame.LookVector * 2.5 + Vector3.new(0, 1, 0)
	for _, item in ipairs(items) do
		ledger:drop(item.id, key, pos, note)
		renderDropped(item, pos)
		emit("drop", { player = player, item = item, note = note, crewId = crewIdOf(player), position = pos })
	end
	sendCarry(player)
	Comms.cue(player, "Drop")
	return true
end

-- Drop everything where the player stands (arrest, death, leaving). Returns labels.
function LootService.dropAll(player: Player, note: string): { string }
	local key = Comms.key(player)
	local items = ledger:carriedBy(key)
	local labels = {}
	if #items == 0 then
		return labels
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = if root then root.Position + Vector3.new(0, 1, 0) else Vector3.new(-390, 3, 322)
	for _, item in ipairs(items) do
		ledger:drop(item.id, key, pos, note)
		renderDropped(item, pos)
		table.insert(labels, item.label)
		emit("drop", { player = player, item = item, note = note, crewId = crewIdOf(player), position = pos })
	end
	if player.Parent then
		sendCarry(player)
	end
	return labels
end

function LootService.stow(player: Player, vehicle: Model): boolean
	local key = Comms.key(player)
	local items = ledger:carriedBy(key)
	local item = items[1]
	if not item then
		Comms.toast(player, "Nothing to stow.", "info")
		return false
	end
	local kind = vehicle:GetAttribute("Kind")
	local capacity = Config.Vehicles[kind] and Config.Vehicles[kind].trunk or 0
	local vid = vehicle:GetAttribute("VehicleId")
	local ok, err = ledger:stow(item.id, key, vid, capacity)
	if not ok then
		Comms.toast(player, if err == "trunk full" then "The trunk is full." else "Can't stow that.", "warn")
		return false
	end
	renderInVehicle(item, vehicle, #ledger:inVehicle(vid))
	sendCarry(player)
	Comms.cue(player, "Drop")
	emit("stow", { player = player, item = item, vehicle = vehicle, crewId = crewIdOf(player) })
	return true
end

function LootService.takeFromVehicle(player: Player, vehicle: Model): boolean
	local key = Comms.key(player)
	local vid = vehicle:GetAttribute("VehicleId")
	local items = ledger:inVehicle(vid)
	local item = items[#items]
	if not item then
		Comms.toast(player, "The trunk is empty.", "info")
		return false
	end
	local previousCrew = lastCrewTouch[item.id]
	local ok, err = ledger:takeFromVehicle(item.id, key, vid, Config.Player.MaxCarry)
	if not ok then
		Comms.toast(player, if err == "hands full" then "Your hands are full." else "Can't take that.", "warn")
		return false
	end
	renderCarried(item, player)
	sendCarry(player)
	Comms.cue(player, "Pickup")
	local myCrew = crewIdOf(player)
	emit("pickup", { player = player, item = item, fromState = "InVehicle", source = "trunk", crewId = myCrew })
	if previousCrew and previousCrew ~= myCrew then
		emit("stolen", { player = player, item = item, fromCrewId = previousCrew, crewId = myCrew })
	end
	lastCrewTouch[item.id] = myCrew
	return true
end

function LootService.spillVehicle(vehicle: Model, note: string)
	local vid = vehicle:GetAttribute("VehicleId")
	local trunk = vehicle:FindFirstChild("Trunk")
	local pos = if trunk then trunk.Position + Vector3.new(0, 2, 3) else vehicle:GetPivot().Position
	for _, item in ipairs(ledger:dropAllFromVehicle(vid, pos, note)) do
		renderDropped(item, pos)
		emit("drop", { player = nil, item = item, note = note, crewId = lastCrewTouch[item.id], position = pos })
	end
end

function LootService.deliver(player: Player, jobId: string): (number, { any })
	local key = Comms.key(player)
	local delivered = {}
	local total = 0
	for _, item in ipairs(ledger:carriedBy(key)) do
		if item.kind == "Fake" then
			ledger:destroy(item.id, "fake delivered")
			clearVisual(item.id)
			Comms.toast(player, "That bag was a fake. Nothing to fence.", "warn")
			sendCarry(player)
			continue
		end
		local ok, _, value = ledger:deliver(item.id, key, jobId)
		if ok then
			total += value
			table.insert(delivered, item)
			clearVisual(item.id)
			emit("deliver", { player = player, item = item, value = value, jobId = jobId, crewId = crewIdOf(player) })
		end
	end
	if total > 0 then
		sendCarry(player)
		Comms.cue(player, "Deliver")
	end
	return total, delivered
end

-- Museum stock
function LootService.cutCase(player: Player, caseId: string): boolean
	local state = caseState[caseId]
	if not state or state.cut then
		return false
	end
	state.cut = true
	local caseRef = state.ref
	caseRef.model:SetAttribute("Cut", true)
	caseRef.glass.Transparency = 0.9
	local pp = caseRef.glass:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp:Destroy()
	end
	-- shards
	for i = 1, 4 do
		local shard = Builder.part(caseRef.model, caseRef.cframe * CFrame.new(math.random(-2, 2), -3.5, math.random(-2, 2)) * CFrame.Angles(0, math.rad(i * 37), 0), Vector3.new(1.2, 0.1, 0.8), { name = "Shard", material = Enum.Material.Glass, color = Palette.Glass, transparency = 0.4, canCollide = false })
		shard.Reflectance = 0.3
	end
	local item = state.itemId and ledger:get(state.itemId)
	if item and item.state == "InCase" and visuals[item.id] then
		Builder.prompt(visuals[item.id].PrimaryPart, "Take " .. item.label, "Display case (glass cut)", 0, "LootTake", { ItemId = item.id })
	end
	emit("casecut", { player = player, caseId = caseId, crewId = crewIdOf(player), position = caseRef.cframe.Position })
	return true
end

-- (Re)stock the museum: purge terminal items, remove leftover case items, choose a layout, register and render.
function LootService.restockMuseum(seed: number)
	local museum = LootService.ctx.world.museum
	ledger:purgeTerminal()
	for _, case in ipairs(museum.cases) do
		local st = caseState[case.id]
		if st and st.itemId then
			local item = ledger:get(st.itemId)
			if item and item.state == "InCase" then
				ledger:destroy(item.id, "restock")
				clearVisual(item.id)
			end
		end
		case.model:SetAttribute("Cut", false)
		case.glass.Transparency = 0.55
		for _, c in ipairs(case.model:GetChildren()) do
			if c.Name == "Shard" then
				c:Destroy()
			end
		end
		local old = case.glass:FindFirstChildOfClass("ProximityPrompt")
		if old then
			old:Destroy()
		end
		caseState[case.id] = { cut = false, itemId = nil, ref = case }
	end
	ledger:purgeTerminal()
	local rng = Random.new(seed)
	-- Non-vault cases: pick 6 of 8 to stock, kinds weighted toward trinkets with a couple of relics/jewels
	local nonVault, vault = {}, {}
	for _, case in ipairs(museum.cases) do
		if case.zone == "Vault" then
			table.insert(vault, case)
		else
			table.insert(nonVault, case)
		end
	end
	for i = #nonVault, 2, -1 do
		local j = rng:NextInteger(1, i)
		nonVault[i], nonVault[j] = nonVault[j], nonVault[i]
	end
	local function stock(case, kind)
		itemCounter += 1
		local s = spec(kind)
		local id = string.format("%s_%d", kind, itemCounter)
		ledger:register({ id = id, kind = kind, label = s.label, value = s.value, weight = s.weight, position = case.cframe.Position, origin = "AuroraExchange" })
		caseState[case.id].itemId = id
		lastCrewTouch[id] = nil
		renderInCase(ledger:get(id), case)
		Builder.prompt(case.glass, "Cut the glass", s.label, Config.Museum.GlassCutSeconds, "CaseCut", { CaseId = case.id })
	end
	local kinds = { "Trinket", "Trinket", "Trinket", "Relic", "Relic", "Jewel" }
	for i = 1, 6 do
		stock(nonVault[i], kinds[i])
	end
	for _, case in ipairs(vault) do
		stock(case, if rng:NextNumber() < 0.5 then "Jewel" else "Relic")
	end
	-- The Core on its pedestal is a special "case" without glass
	itemCounter += 1
	local coreSpec = spec("Core")
	local coreId = "Core_" .. itemCounter
	ledger:register({ id = coreId, kind = "Core", label = coreSpec.label, value = coreSpec.value, weight = "Heavy", position = museum.corePedestal.cframe.Position, origin = "AuroraExchange" })
	lastCrewTouch[coreId] = nil
	local coreItem = ledger:get(coreId)
	clearVisual(coreId)
	local m = makeVisual(coreItem)
	m:PivotTo(museum.corePedestal.cframe)
	setAnchoredCollide(m, true, false)
	m.Parent = LootService.ctx.world.lootFolder
	visuals[coreId] = m
	Builder.prompt(m.PrimaryPart, "Lift the Aurora Core", "Heavy: slow, no climbing, no jumping", 1.5, "LootTake", { ItemId = coreId })
	LootService.coreItemId = coreId
end

-- Mint stolen stash as physical bundles on the floor. Returns the new item ids.
function LootService.mintBundles(values: { number }, position: Vector3, origin: string, label: string?): { string }
	local ids = {}
	for i, value in ipairs(values) do
		itemCounter += 1
		local id = string.format("Bundle_%d", itemCounter)
		local spec = Config.Economy.Loot.Bundle
		ledger:register({ id = id, kind = "Bundle", label = label or spec.label, value = value, weight = "Light", position = position, origin = origin })
		local item = ledger:get(id)
		item.state = "Dropped"
		item.position = position
		renderDropped(item, position + Vector3.new((i - 1) * 2.2 - (#values - 1) * 1.1, 0, 0))
		lastCrewTouch[id] = nil
		table.insert(ids, id)
	end
	return ids
end

-- A fake bag for a crew. Mimics a real kind (visual, label, shown value) but is always light and worth 0.
-- It never shares an id with real loot, and it is never counted as touched loot by a job.
function LootService.mintFake(player: Player, mimicKind: string): (boolean, string?)
	local crewId = crewIdOf(player)
	if not crewId then
		return false, "no crew"
	end
	local live = 0
	for _, item in pairs(ledger.items) do
		if item.kind == "Fake" and item.origin == "fake:" .. crewId and item.state ~= "Destroyed" then
			live += 1
		end
	end
	if live >= Config.Decoys.MaxFakesPerCrew then
		return false, string.format("your crew already has %d fake bags out", live)
	end
	local mimic = Config.Economy.Loot[mimicKind]
	if not mimic or not table.find(Config.Decoys.Mimics, mimicKind) then
		return false, "unknown kind"
	end
	itemCounter += 1
	local id = string.format("Fake_%d", itemCounter)
	local label = if mimicKind == "Bundle" then "Stash of " .. Comms.name(player) else mimic.label
	ledger:register({ id = id, kind = "Fake", label = label, value = 0, weight = "Light", origin = "fake:" .. crewId })
	local item = ledger:get(id)
	item.mimic = mimicKind
	item.mimicValue = if mimicKind == "Bundle" then Config.Decoys.BundleMimicValue else mimic.value
	lastCrewTouch[id] = crewId
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = if root then root.Position + root.CFrame.LookVector * 2.5 + Vector3.new(0, 1, 0) else Vector3.new(-390, 3, 322)
	if #ledger:carriedBy(Comms.key(player)) == 0 then
		item.state = "Dropped"
		item.position = pos
		ledger:pickUp(id, Comms.key(player), Config.Player.MaxCarry)
		renderCarried(item, player)
		sendCarry(player)
	else
		item.state = "Dropped"
		item.position = pos
		renderDropped(item, pos)
	end
	return true, nil
end

-- Destroy a crew's live fakes (job closed). Returns how many were removed.
function LootService.clearFakes(crewId: string): number
	local n = 0
	for id, item in pairs(ledger.items) do
		if item.kind == "Fake" and item.origin == "fake:" .. crewId and item.state ~= "Destroyed" then
			local holder = item.holder and Players:GetPlayerByUserId(tonumber(item.holder) or 0)
			ledger:destroy(id, "fake expired")
			clearVisual(id)
			if holder then
				sendCarry(holder)
			end
			n += 1
		end
	end
	return n
end

-- Every dropped item with its current world position (for retention and recovery).
function LootService.droppedItems(): { { item: any, position: Vector3 } }
	local out = {}
	for id, item in pairs(ledger.items) do
		if item.state == "Dropped" then
			local v = visuals[id]
			local pos = if v and v.PrimaryPart then v.PrimaryPart.Position else item.position
			if typeof(pos) == "Vector3" then
				table.insert(out, { item = item, position = pos })
			end
		end
	end
	return out
end

-- Remove an item from the world for good (retained by defences, recovered, etc.).
function LootService.absorb(itemId: string, note: string)
	local item = ledger:get(itemId)
	if not item then
		return
	end
	ledger:destroy(itemId, note)
	clearVisual(itemId)
	emit("absorbed", { item = item, note = note, crewId = lastCrewTouch[itemId] })
end

function LootService.museumStockRemaining(): number
	return ledger:countInState("InCase")
end

function LootService.caseOf(caseId: string)
	return caseState[caseId]
end

function LootService.start()
	Players.PlayerRemoving:Connect(function(player)
		LootService.dropAll(player, "left the server")
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			local humanoid = char:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					LootService.dropAll(player, "went down")
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
end

-- Interactions (routed by InteractionService)
function LootService.onPickup(player: Player, prompt: ProximityPrompt)
	LootService.pickUp(player, tostring(prompt:GetAttribute("ItemId")), "ground")
end

function LootService.onTake(player: Player, prompt: ProximityPrompt)
	LootService.pickUp(player, tostring(prompt:GetAttribute("ItemId")), "case")
end

function LootService.onCaseCut(player: Player, prompt: ProximityPrompt)
	LootService.cutCase(player, tostring(prompt:GetAttribute("CaseId")))
end

local _ = playerFromKey
return LootService
