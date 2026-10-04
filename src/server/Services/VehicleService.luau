--!nonstrict
-- Vehicles: spawning (street cars, crew garage, police cruisers), trunks, occupancy, damage and the disabled
-- state. A disabled getaway spills its trunk: the crew must transfer loot under pressure.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local VehicleBuilder = require(script.Parent.Parent.Builders.VehicleBuilder)
local Builder = require(script.Parent.Parent.Builders.Builder)
local Comms = require(script.Parent.Comms)

local VehicleService = { ctx = nil :: any }

local vehicles = {} -- id -> record
local counter = 0
local crewVehicles = {} -- crewId -> { kind -> id }

function VehicleService.init(ctx)
	VehicleService.ctx = ctx
end

function VehicleService.get(id: string)
	return vehicles[id]
end

function VehicleService.all()
	return vehicles
end

local function refreshTrunkPrompt(rec)
	local prompt = rec.trunkPrompt
	if not prompt then
		return
	end
	local items = VehicleService.ctx.services.Loot.inVehicle(rec.id)
	local cap = Config.Vehicles[rec.kind].trunk
	if rec.model:GetAttribute("Disabled") then
		prompt.ActionText = "Take loot"
		prompt.ObjectText = string.format("%s (wrecked) — %d bag(s)", rec.label, #items)
	else
		prompt.ActionText = if #items > 0 then "Stow / take loot" else "Stow loot"
		prompt.ObjectText = string.format("%s trunk %d/%d", rec.label, #items, cap)
	end
	prompt.Enabled = cap > 0
end

local function onOccupant(rec)
	local occupant = rec.seat.Occupant
	local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	if rec.driver and rec.driver ~= player then
		rec.driver:SetAttribute("VehicleId", nil)
	end
	rec.driver = player
	if player then
		player:SetAttribute("VehicleId", rec.id)
		if not rec.npc then
			pcall(function()
				rec.chassis:SetNetworkOwner(player)
			end)
		end
		local Police = VehicleService.ctx.services.Police
		if Police.heatLevel(player) > 0 then
			Police.recognizeVehicle(rec.id)
		end
	elseif not rec.npc then
		pcall(function()
			rec.chassis:SetNetworkOwner(nil)
		end)
	end
end

function VehicleService.spawn(kind: string, cf: CFrame, opts)
	opts = opts or {}
	counter += 1
	local id = string.format("%s_%d", kind, counter)
	local model = VehicleBuilder.build(VehicleService.ctx.world.vehiclesFolder, kind, cf, id)
	local rec = {
		id = id,
		kind = kind,
		label = Config.Vehicles[kind].label,
		model = model,
		chassis = model.PrimaryPart,
		seat = model:FindFirstChild("DriverSeat"),
		driver = nil,
		crewId = opts.crewId,
		npc = opts.npc == true,
		spawnCFrame = cf,
		streetSpot = opts.streetSpot,
		health = Config.Vehicles[kind].health,
		motors = {},
		servos = {},
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("HingeConstraint") then
			if d.Name == "WheelMotor" then
				table.insert(rec.motors, d)
			elseif d.Name == "SteerServo" then
				table.insert(rec.servos, d)
			end
		end
	end
	vehicles[id] = rec
	if Config.Vehicles[kind].trunk > 0 then
		rec.trunkPrompt = Builder.prompt(model.Trunk, "Stow loot", rec.label .. " trunk", 0.6, "Trunk", { VehicleId = id })
		refreshTrunkPrompt(rec)
	end
	rec.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupant(rec)
	end)
	if rec.npc then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				pcall(function()
					d:SetNetworkOwner(nil)
				end)
			end
		end
	end
	return rec
end

function VehicleService.destroy(id: string)
	local rec = vehicles[id]
	if not rec then
		return
	end
	VehicleService.ctx.services.Loot.spillVehicle(rec.model, "vehicle removed")
	if rec.driver then
		rec.driver:SetAttribute("VehicleId", nil)
	end
	rec.model:Destroy()
	vehicles[id] = nil
	if rec.crewId and crewVehicles[rec.crewId] and crewVehicles[rec.crewId][rec.kind] == id then
		crewVehicles[rec.crewId][rec.kind] = nil
	end
end

function VehicleService.isOccupied(rec): boolean
	for _, d in ipairs(rec.model:GetChildren()) do
		if (d:IsA("VehicleSeat") or d:IsA("Seat")) and d.Occupant then
			return true
		end
	end
	return false
end

function VehicleService.spawnCrewVehicle(crew, kind: string, cf: CFrame, player: Player)
	if not Config.Vehicles[kind] or kind == "Cruiser" then
		return
	end
	crewVehicles[crew.id] = crewVehicles[crew.id] or {}
	local existingId = crewVehicles[crew.id][kind]
	local existing = existingId and vehicles[existingId]
	if existing then
		if VehicleService.isOccupied(existing) then
			Comms.toast(player, "Your " .. existing.label .. " is in use. Empty it first.", "warn")
			return
		end
		VehicleService.destroy(existingId)
	end
	-- Make sure the bay is clear of other cars
	for _, rec in pairs(vehicles) do
		if (rec.chassis.Position - cf.Position).Magnitude < 10 and not VehicleService.isOccupied(rec) and rec.crewId == crew.id then
			VehicleService.destroy(rec.id)
		end
	end
	local rec = VehicleService.spawn(kind, cf, { crewId = crew.id })
	crewVehicles[crew.id][kind] = rec.id
	Comms.toastMany(crew.members, rec.label .. " is in the bay. Walk into the driver seat to drive; the trunk is at the back.", "good")
end

function VehicleService.damage(id: string, amount: number, reason: string)
	local rec = vehicles[id]
	if not rec or rec.model:GetAttribute("Disabled") then
		return
	end
	rec.health = math.max(0, rec.health - amount)
	rec.model:SetAttribute("Health", rec.health)
	if rec.driver then
		Comms.hud(rec.driver, { vehicleHealth = rec.health, vehicleMaxHealth = Config.Vehicles[rec.kind].health })
	end
	if rec.health <= 0 then
		VehicleService.disable(id, reason)
	end
end

function VehicleService.disable(id: string, reason: string)
	local rec = vehicles[id]
	if not rec or rec.model:GetAttribute("Disabled") then
		return
	end
	rec.model:SetAttribute("Disabled", true)
	for _, m in ipairs(rec.motors) do
		m.MotorMaxTorque = 0
		m.AngularVelocity = 0
	end
	local smoke = rec.model:FindFirstChild("Smoke", true)
	if smoke then
		smoke.Enabled = true
	end
	for _, d in ipairs(rec.model:GetChildren()) do
		if d.Name == "Headlight" then
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	VehicleService.ctx.services.Loot.spillVehicle(rec.model, "vehicle disabled: " .. reason)
	refreshTrunkPrompt(rec)
	local occupants = {}
	for _, d in ipairs(rec.model:GetChildren()) do
		if (d:IsA("VehicleSeat") or d:IsA("Seat")) and d.Occupant then
			local p = Players:GetPlayerFromCharacter(d.Occupant.Parent)
			if p then
				table.insert(occupants, p)
			end
		end
	end
	Comms.toastMany(occupants, rec.label .. " is wrecked (" .. reason .. "). Grab the bags and find another way.", "alarm")
	task.delay(Config.Vehicles.DisabledSmokeSeconds, function()
		if vehicles[id] == rec then
			local spot = rec.streetSpot
			VehicleService.destroy(id)
			if spot then
				task.delay(Config.Vehicles.RespawnSeconds, function()
					VehicleService.spawn("Commuter", rec.spawnCFrame, { streetSpot = spot })
				end)
			end
		end
	end)
end

function VehicleService.onTrunk(player: Player, prompt: ProximityPrompt)
	local rec = vehicles[prompt:GetAttribute("VehicleId")]
	if not rec then
		return
	end
	local Loot = VehicleService.ctx.services.Loot
	local canStow = not rec.model:GetAttribute("Disabled") and #Loot.carriedBy(player) > 0
	if canStow then
		Loot.stow(player, rec.model)
	else
		Loot.takeFromVehicle(player, rec.model)
	end
	refreshTrunkPrompt(rec)
end

function VehicleService.vehicleOfPlayer(player: Player)
	local id = player:GetAttribute("VehicleId")
	return id and vehicles[id] or nil
end

function VehicleService.start()
	for _, spot in ipairs(Blueprint.StreetCars) do
		VehicleService.spawn("Commuter", CFrame.new(spot.x, 3, spot.z) * CFrame.Angles(0, math.rad(spot.rot), 0), { streetSpot = spot.name })
	end
	VehicleService.ctx.services.Loot.onEvent(function(kind, data)
		if kind == "stow" and data.vehicle then
			local rec = vehicles[data.vehicle:GetAttribute("VehicleId")]
			if rec then
				refreshTrunkPrompt(rec)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, rec in pairs(vehicles) do
			if rec.driver == player then
				rec.driver = nil
			end
		end
	end)
end

return VehicleService
