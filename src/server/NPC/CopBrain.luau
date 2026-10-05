--!nonstrict
-- NPC police cruiser. Patrols the road loop, pursues wanted players and recognized vehicles over the road
-- graph, rams getaway cars, and cuffs wanted players on foot when it can stop beside them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Blueprint = require(ReplicatedStorage.Shared.MapBlueprint)
local Palette = require(ReplicatedStorage.Shared.Palette)

local CopBrain = {}
CopBrain.__index = CopBrain

local WHEEL_RADIUS = Config.Vehicles.WheelRadius

function CopBrain.new(ctx, rec, index: number, graph)
	local self = setmetatable({}, CopBrain)
	self.ctx = ctx
	self.rec = rec
	self.index = index
	self.graph = graph
	self.state = "Parked"
	self.active = false -- set by the PoliceService dispatcher
	self.target = nil -- Player
	self.targetVehicleId = nil
	self.path = nil
	self.pathIndex = 1
	self.pathAt = 0
	self.patrolIndex = ((index - 1) % #Blueprint.PolicePatrol) + 1
	self.stuckTimer = 0
	self.reverseUntil = 0
	self.cuffTimer = 0
	self.lastTouchDamage = 0
	self.flashOn = false
	self.lightBar = rec.model:FindFirstChild("LightBar")
	rec.chassis.Touched:Connect(function(hit)
		self:onTouched(hit)
	end)
	return self
end

function CopBrain:difficulty()
	return Config.Police.Difficulty[Config.Police.NpcDifficulty] or Config.Police.Difficulty.Medium
end

function CopBrain:position(): Vector3
	return self.rec.chassis.Position
end

function CopBrain:speed(): number
	return self.rec.chassis.AssemblyLinearVelocity.Magnitude
end

function CopBrain:setLights(on: boolean)
	if not self.lightBar then
		return
	end
	local pl = self.lightBar:FindFirstChildOfClass("PointLight")
	if on then
		self.flashOn = not self.flashOn
		self.lightBar.Color = if self.flashOn then Palette.PoliceLight else Palette.SecurityRed
		if pl then
			pl.Brightness = 2
			pl.Color = self.lightBar.Color
		end
	else
		self.lightBar.Color = Palette.PoliceLight
		if pl then
			pl.Brightness = 0
		end
	end
end

-- Low-level driving: steer toward a world point at a speed factor.
function CopBrain:drive(target: Vector3, speedFactor: number, now: number)
	local chassis = self.rec.chassis
	local tune = Config.Vehicles.Cruiser
	local diff = self:difficulty()
	local maxSpeed = diff.cruiserSpeed * speedFactor
	local toTarget = Vector3.new(target.X - chassis.Position.X, 0, target.Z - chassis.Position.Z)
	if toTarget.Magnitude < 1 then
		return
	end
	local look = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z).Unit
	local dir = toTarget.Unit
	local angle = math.deg(math.atan2(look:Cross(dir).Y, look:Dot(dir))) -- + = target is to the left
	local reversing = now < self.reverseUntil
	local steer = math.clamp(angle / 35, -1, 1) -- positive servo angle turns left
	if reversing then
		steer = -steer
	end
	for _, s in ipairs(self.rec.servos) do
		s.TargetAngle = steer * 35
	end
	local mass = chassis.AssemblyMass
	local torque = mass * tune.accel * WHEEL_RADIUS
	local wantSpeed = if reversing then -maxSpeed * 0.4 else maxSpeed * (if math.abs(angle) > 60 then 0.45 else 1)
	for _, m in ipairs(self.rec.motors) do
		m.MotorMaxTorque = torque
		m.AngularVelocity = -wantSpeed / WHEEL_RADIUS
	end
end

function CopBrain:stop()
	for _, m in ipairs(self.rec.motors) do
		m.AngularVelocity = 0
		m.MotorMaxTorque = self.rec.chassis.AssemblyMass * 40
	end
	for _, s in ipairs(self.rec.servos) do
		s.TargetAngle = 0
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

function CopBrain:canSee(root: BasePart): boolean
	local diff = self:difficulty()
	local eye = self.rec.chassis.Position + Vector3.new(0, 3, 0)
	local to = root.Position - eye
	if to.Magnitude > diff.viewDistance * self.ctx.services.Police.visionScale() then
		return false
	end
	rayParams.FilterDescendantsInstances = { self.rec.model, self.ctx.world.lootFolder, self.ctx.world.npcFolder }
	local hit = workspace:Raycast(eye, to, rayParams)
	if hit == nil then
		return true
	end
	local character = root.Parent :: Instance
	if hit.Instance:IsDescendantOf(character) then
		return true
	end
	local hitModel = hit.Instance:FindFirstAncestorWhichIsA("Model")
	local myVehicleId = root.Parent and (root.Parent :: Instance):GetAttribute("VehicleId")
	return hitModel ~= nil and myVehicleId ~= nil and hitModel:GetAttribute("VehicleId") == myVehicleId
end

function CopBrain:followPath(goal: Vector3, now: number)
	if not self.path or now - self.pathAt > 2.5 then
		local from = self.graph:nearest(self:position().X, self:position().Z)
		local to = self.graph:nearest(goal.X, goal.Z)
		self.path = self.graph:path(from, to)
		self.pathIndex = 1
		self.pathAt = now
	end
	if self.path then
		local node = self.graph.nodes[self.path[self.pathIndex]]
		local np = Vector3.new(node.x, 0, node.z)
		if (Vector3.new(self:position().X, 0, self:position().Z) - np).Magnitude < 14 then
			if self.pathIndex < #self.path then
				self.pathIndex += 1
				node = self.graph.nodes[self.path[self.pathIndex]]
				np = Vector3.new(node.x, 0, node.z)
			else
				self:drive(goal, 1, now)
				return
			end
		end
		self:drive(np, 1, now)
	else
		self:drive(goal, 0.6, now)
	end
end

function CopBrain:onTouched(hit: BasePart)
	local now = os.clock()
	if now - self.lastTouchDamage < 1.2 then
		return
	end
	local model = hit:FindFirstAncestorWhichIsA("Model")
	local vid = model and model:GetAttribute("VehicleId")
	if not vid or vid == self.rec.id then
		return
	end
	local Vehicle = self.ctx.services.Vehicle
	local Police = self.ctx.services.Police
	local other = Vehicle.get(vid)
	if not other or other.npc then
		return
	end
	local relSpeed = (self.rec.chassis.AssemblyLinearVelocity - other.chassis.AssemblyLinearVelocity).Magnitude
	if relSpeed > 18 and (self.target or Police.isVehicleRecognized(vid)) then
		self.lastTouchDamage = now
		Vehicle.damage(vid, Config.Vehicles.RamDamage, "rammed by police")
		if other.driver then
			Police.addHeat(other.driver, Config.Police.RamHeat, "rammed by police")
		end
	end
end

function CopBrain:tick(dt: number, now: number)
	local Police = self.ctx.services.Police
	local Vehicle = self.ctx.services.Vehicle
	local chassis = self.rec.chassis
	if not chassis or not chassis.Parent or self.rec.model:GetAttribute("Disabled") then
		return
	end
	-- Perception: wanted players and recognized vehicles in view
	local best, bestD = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and not player:GetAttribute("Jailed") then
			local wanted = Police.heatLevel(player) > 0
			local vrec = Vehicle.vehicleOfPlayer(player)
			local recognized = vrec and Police.isVehicleRecognized(vrec.id)
			if (wanted or recognized) and self:canSee(root) then
				Police.seen(player, now)
				if vrec and wanted then
					Police.recognizeVehicle(vrec.id)
				end
				local d = (root.Position - self:position()).Magnitude
				if d < bestD then
					best, bestD = player, d
				end
			end
		end
	end
	if best then
		self.target = best
		self.lastSeenAt = now
		self.lastKnown = best.Character:GetPivot().Position
	end
	local target = self.target
	if target and (not target.Parent or Police.heatLevel(target) == 0 or target:GetAttribute("Jailed")) then
		self.target = nil
		target = nil
	end

	if self.barricadeAt then
		self.state = "Barricade"
		self:setLights(true)
		local d = (Vector3.new(self:position().X, 0, self:position().Z) - self.barricadeAt).Magnitude
		if d > 10 then
			self:followPath(self.barricadeAt, now)
		else
			self:stop()
		end
		return
	end

	if not self.active then
		target = nil
		self.target = nil
	end

	if target then
		self.state = "Pursuit"
		self:setLights(true)
		local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		local goal = if root and now - (self.lastSeenAt or 0) < 4 then root.Position else self.lastKnown
		if not goal then
			self.target = nil
			return
		end
		local d = (goal - self:position()).Magnitude
		local onFoot = Vehicle.vehicleOfPlayer(target) == nil
		local diff = self:difficulty()
		if onFoot and root and d <= Config.Police.ArrestRange then
			self:stop()
			if self:speed() < 8 then
				self.cuffTimer += dt
				Police.cuffing(target, self.cuffTimer / diff.cuffSeconds)
				if self.cuffTimer >= diff.cuffSeconds then
					self.cuffTimer = 0
					Police.arrest(target, "Police", Blueprint.nearestLandmark(goal.X, goal.Z))
					self.target = nil
				end
			end
			return
		elseif d > Config.Police.ArrestBreakRange then
			if self.cuffTimer > 0 then
				Police.cuffing(target, 0)
			end
			self.cuffTimer = 0
		end
		if d < 70 and root and self:canSee(root) then
			self:drive(goal, 1, now)
		else
			self:followPath(goal, now)
		end
		-- Stuck handling
		if self:speed() < 2 then
			self.stuckTimer += dt
			if self.stuckTimer > 2.5 then
				self.reverseUntil = now + 1.5
				self.stuckTimer = 0
			end
		else
			self.stuckTimer = 0
		end
		return
	end

	-- No target: dispatched cruisers patrol; the rest park.
	if self.active then
		self.state = "Patrol"
		self:setLights(false)
		local wp = Blueprint.PolicePatrol[self.patrolIndex]
		local p = Vector3.new(wp.x, 0, wp.z)
		if (Vector3.new(self:position().X, 0, self:position().Z) - p).Magnitude < 16 then
			self.patrolIndex = (self.patrolIndex % #Blueprint.PolicePatrol) + 1
		end
		self:followPath(p, now)
		if self:speed() < 2 then
			self.stuckTimer += dt
			if self.stuckTimer > 3 then
				self.reverseUntil = now + 1.5
				self.stuckTimer = 0
			end
		else
			self.stuckTimer = 0
		end
	else
		if self.state ~= "Parked" then
			local pad = self.rec.spawnCFrame.Position
			if (self:position() - pad).Magnitude > 12 then
				self.state = "Return"
				self:followPath(pad, now)
				return
			end
			self.state = "Parked"
		end
		self:setLights(false)
		self:stop()
	end
end

return CopBrain
