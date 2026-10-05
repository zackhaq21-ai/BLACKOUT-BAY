--!nonstrict
-- Low-level NPC driving for one convoy vehicle: steer toward waypoints, keep formation, halt when a player or a
-- player's car blocks the road, back out when stuck. Physics is server-owned (network owner nil). No per-frame
-- pathfinding: the route is a fixed list of road nodes chosen at spawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local VehicleFeel = require(ReplicatedStorage.Shared.Core.VehicleFeel)

local PV = Config.Presentation.Vehicle

local ConvoyDriver = {}
ConvoyDriver.__index = ConvoyDriver

local WHEEL_RADIUS = Config.Vehicles.WheelRadius
local WAYPOINT_RADIUS = 12
local PROBE_DISTANCE = 16

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

function ConvoyDriver.new(ctx, rec, tune, waypoints: { Vector3 }, convoyModels: { Instance })
	return setmetatable({
		ctx = ctx,
		rec = rec,
		tune = tune,
		waypoints = waypoints,
		index = 1,
		reverseUntil = 0,
		stuckTimer = 0,
		stuckTotal = 0,
		blocked = false,
		arrived = false,
		exclude = convoyModels,
	}, ConvoyDriver)
end

function ConvoyDriver:position(): Vector3
	return self.rec.chassis.Position
end

function ConvoyDriver:speed(): number
	return self.rec.chassis.AssemblyLinearVelocity.Magnitude
end

function ConvoyDriver:flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- A player character or a player-driven vehicle directly ahead.
function ConvoyDriver:obstructed(): boolean
	local chassis = self.rec.chassis
	local origin = chassis.Position + chassis.CFrame.LookVector * (chassis.Size.Z / 2) + Vector3.new(0, 1, 0)
	local list = table.clone(self.exclude)
	table.insert(list, self.ctx.world.lootFolder)
	table.insert(list, self.ctx.world.npcFolder)
	rayParams.FilterDescendantsInstances = list
	local dir = chassis.CFrame.LookVector * PROBE_DISTANCE
	for _, side in ipairs({ -2, 0, 2 }) do
		local hit = workspace:Raycast(origin + chassis.CFrame.RightVector * side, dir, rayParams)
		if hit then
			local model = hit.Instance:FindFirstAncestorWhichIsA("Model")
			if model then
				if Players:GetPlayerFromCharacter(model) then
					return true
				end
				local vid = model:GetAttribute("VehicleId")
				if vid then
					local other = self.ctx.services.Vehicle.get(vid)
					if other and not other.npc then
						return true
					end
				end
			end
		end
	end
	return false
end

function ConvoyDriver:drive(target: Vector3, wantSpeed: number, now: number)
	local chassis = self.rec.chassis
	local toTarget = self:flat(target - chassis.Position)
	if toTarget.Magnitude < 1 then
		self:stop()
		return
	end
	local look = self:flat(chassis.CFrame.LookVector).Unit
	local dir = toTarget.Unit
	local angle = math.deg(math.atan2(look:Cross(dir).Y, look:Dot(dir)))
	local reversing = now < self.reverseUntil
	local steer = math.clamp(angle / 35, -1, 1)
	if reversing then
		steer = -steer
	end
	local forwardVel = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
	for _, s in ipairs(self.rec.servos) do
		s.TargetAngle = steer * 35 * VehicleFeel.steerLock(PV, self.tune, forwardVel)
		s.AngularSpeed = VehicleFeel.steerSpeed(PV, self.tune, forwardVel)
	end
	local torque = chassis.AssemblyMass * self.tune.accel * WHEEL_RADIUS
	local speed = if reversing then -wantSpeed * 0.4 else wantSpeed * (if math.abs(angle) > 60 then 0.4 elseif math.abs(angle) > 25 then 0.7 else 1)
	for _, m in ipairs(self.rec.motors) do
		m.MotorMaxTorque = torque
		m.AngularVelocity = -speed / WHEEL_RADIUS
	end
	self:setEngine(math.abs(speed))
end

function ConvoyDriver:stop()
	for _, m in ipairs(self.rec.motors) do
		m.AngularVelocity = 0
		m.MotorMaxTorque = self.rec.chassis.AssemblyMass * 60
	end
	for _, s in ipairs(self.rec.servos) do
		s.TargetAngle = 0
	end
	self:setEngine(0)
end

function ConvoyDriver:setEngine(speed: number)
	local engine = self.rec.chassis:FindFirstChild("Engine")
	if engine and engine:IsA("Sound") and engine.SoundId ~= "" then
		engine.PlaybackSpeed = 0.8 + math.clamp(speed / 40, 0, 1) * 0.6
		if not engine.IsPlaying then
			engine:Play()
		end
	end
end

-- One step. `wantSpeed` 0 means hold position. Returns true when the final waypoint is reached.
function ConvoyDriver:tick(dt: number, now: number, wantSpeed: number): boolean
	if self.arrived or self.rec.model:GetAttribute("Disabled") then
		self:stop()
		return self.arrived
	end
	local wp = self.waypoints[self.index]
	if (self:flat(self:position()) - self:flat(wp)).Magnitude < WAYPOINT_RADIUS then
		if self.index < #self.waypoints then
			self.index += 1
			wp = self.waypoints[self.index]
		else
			self.arrived = true
			self:stop()
			return true
		end
	end
	self.blocked = wantSpeed > 0 and self:obstructed()
	if wantSpeed <= 0 or (self.blocked and now >= self.reverseUntil) then
		self:stop()
		return false
	end
	self:drive(wp, wantSpeed, now)
	-- Stuck: wanted to move, did not. Back out briefly; the caller decides when to give up.
	if self:speed() < 2 then
		self.stuckTimer += dt
		self.stuckTotal += dt
		if self.stuckTimer > 3 then
			self.reverseUntil = now + 1.5
			self.stuckTimer = 0
		end
	else
		self.stuckTimer = 0
		self.stuckTotal = 0
	end
	return false
end

-- Index of the waypoint being approached (for checkpoint halts).
function ConvoyDriver:target(): number
	return self.index
end

return ConvoyDriver
