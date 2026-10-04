--!nonstrict
-- Hideout units: assignment to crews, spawning players at home, delivery table, garage prompts, stash sign.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Comms = require(script.Parent.Comms)

local HideoutService = { ctx = nil :: any }

local units = {} -- from world
local unitCrews = {} -- unitId -> { crewId = true }

function HideoutService.init(ctx)
	HideoutService.ctx = ctx
	units = ctx.world.hideouts
	for _, u in ipairs(units) do
		unitCrews[u.id] = {}
		Builder.prompt(u.deliveryTable, "Deliver haul", "Delivery table", 0.6, "Deliver", { UnitId = u.id })
		Builder.prompt(u.board, "Open job board", "Job board", 0, "Board", { UnitId = u.id })
		-- Garage prompts on the two partition pieces
		local parts = {}
		for _, c in ipairs(u.model:GetChildren()) do
			if c.Name == "Partition" then
				table.insert(parts, c)
			end
		end
		if parts[1] then
			Builder.prompt(parts[1], "Roll out Kestrel", "Garage (fast, 2 seats, 2 bags)", 0.8, "SpawnVehicle", { UnitId = u.id, Kind = "Kestrel" })
		end
		if parts[2] then
			Builder.prompt(parts[2], "Roll out Courier Van", "Garage (slow, 4 seats, 5 bags)", 0.8, "SpawnVehicle", { UnitId = u.id, Kind = "Courier" })
		end
	end
end

local function crewCount(unitId: string): number
	local n = 0
	for _ in pairs(unitCrews[unitId]) do
		n += 1
	end
	return n
end

function HideoutService.assignUnit(crew)
	local best, bestN = nil, math.huge
	for _, u in ipairs(units) do
		local n = crewCount(u.id)
		if n < bestN then
			best, bestN = u, n
		end
	end
	if best then
		unitCrews[best.id][crew.id] = true
	end
	return best
end

function HideoutService.releaseUnit(crew)
	if crew.unit then
		unitCrews[crew.unit.id][crew.id] = nil
	end
end

function HideoutService.unitById(id: string)
	for _, u in ipairs(units) do
		if u.id == id then
			return u
		end
	end
	return nil
end

function HideoutService.unitOf(player: Player)
	local crew = HideoutService.ctx.services.Crew.crewOf(player)
	return crew and crew.unit or nil
end

function HideoutService.sendHome(player: Player)
	local unit = HideoutService.unitOf(player)
	local char = player.Character
	if unit and char and char.PrimaryPart then
		char:PivotTo(unit.spawn + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)))
	end
end

function HideoutService.isAtUnit(player: Player, unit): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local p = root.Position
	local b = unit.bounds
	return p.X >= b.minX and p.X <= b.maxX and p.Z >= b.minZ and p.Z <= b.maxZ
end

function HideoutService.start()
	local Police = HideoutService.ctx.services.Police
	local function onCharacter(player: Player, char: Model)
		local root = char:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.NameDisplayDistance = 0
		end
		task.wait() -- let the default spawn settle, then place at home (or in jail)
		if Police and Police.isJailed(player) then
			Police.placeInCell(player)
		else
			HideoutService.sendHome(player)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function(char)
			onCharacter(p, char)
		end)
		if p.Character then
			task.spawn(onCharacter, p, p.Character)
		end
	end
	-- Stash signs show the crews' combined cash (wealth is visible in Glasshouse)
	task.spawn(function()
		while true do
			task.wait(5)
			local Crew = HideoutService.ctx.services.Crew
			for _, u in ipairs(units) do
				local total = 0
				local names = {}
				for crewId in pairs(unitCrews[u.id]) do
					local crew = Crew.get(crewId)
					if crew then
						for _, p in ipairs(crew.members) do
							total += p:GetAttribute("Cash") or 0
							table.insert(names, Comms.name(p))
						end
					end
				end
				local gui = u.stashSign:FindFirstChild("Label")
				local tl = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
				if tl then
					tl.Text = string.format("STASH\n%s\n%s", tostring(total), if #names > 0 then table.concat(names, ", ") else "vacant")
				end
			end
		end
	end)
end

-- Interactions
function HideoutService.onDeliver(player: Player, prompt: ProximityPrompt)
	local unit = HideoutService.unitById(tostring(prompt:GetAttribute("UnitId")))
	local crew = HideoutService.ctx.services.Crew.crewOf(player)
	if not unit or not crew then
		return
	end
	if crew.unit ~= unit then
		Comms.toast(player, "This isn't your crew's hideout. Yours is " .. (crew.unit and crew.unit.label or "?") .. ".", "warn")
		return
	end
	HideoutService.ctx.services.Mission.deliver(player, crew)
end

function HideoutService.onSpawnVehicle(player: Player, prompt: ProximityPrompt)
	local unit = HideoutService.unitById(tostring(prompt:GetAttribute("UnitId")))
	local crew = HideoutService.ctx.services.Crew.crewOf(player)
	if not unit or not crew or crew.unit ~= unit then
		Comms.toast(player, "Only your own crew's garage works.", "warn")
		return
	end
	HideoutService.ctx.services.Vehicle.spawnCrewVehicle(crew, tostring(prompt:GetAttribute("Kind")), unit.vehicleSpawn, player)
end

local _ = Config
return HideoutService
