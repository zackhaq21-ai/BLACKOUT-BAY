--!nonstrict
-- Drives constraint cars from the driver's seat inputs (throttle/steer come from VehicleSeat for keyboard,
-- gamepad and touch). The seated client owns the physics, so this is responsive; the server owns damage.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local VehicleController = {}

local player = Players.LocalPlayer
local WHEEL_RADIUS = 1.4
local active = nil -- { seat, model, chassis, motors, servos, tune }
local conn = nil
local hud

local function collect(model: Model)
	local motors, servos = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("HingeConstraint") then
			if d.Name == "WheelMotor" then
				table.insert(motors, d)
			elseif d.Name == "SteerServo" then
				table.insert(servos, d)
			end
		end
	end
	return motors, servos
end

local function stopDriving()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if active then
		for _, m in ipairs(active.motors) do
			m.AngularVelocity = 0
			m.MotorMaxTorque = active.chassis.AssemblyMass * 20
		end
		for _, s in ipairs(active.servos) do
			s.TargetAngle = 0
		end
	end
	active = nil
	if hud then
		hud.hideVehicle()
	end
end

local function startDriving(seat: VehicleSeat)
	local model = seat:FindFirstAncestorWhichIsA("Model")
	if not model or not model:GetAttribute("VehicleId") then
		return
	end
	local kind = model:GetAttribute("Kind")
	local tune = Config.Vehicles[kind]
	if not tune then
		return
	end
	local motors, servos = collect(model)
	active = { seat = seat, model = model, chassis = model.PrimaryPart, motors = motors, servos = servos, tune = tune }
	conn = RunService.Heartbeat:Connect(function()
		if not active or not seat.Parent or seat.Occupant == nil then
			stopDriving()
			return
		end
		local chassis = active.chassis
		local disabled = model:GetAttribute("Disabled") == true
		local throttle = if disabled then 0 else seat.ThrottleFloat
		local steer = seat.SteerFloat
		local forwardVel = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		local mass = chassis.AssemblyMass
		local braking = (throttle < 0 and forwardVel > 4) or (throttle > 0 and forwardVel < -4)
		for _, m in ipairs(motors) do
			if disabled then
				m.MotorMaxTorque = 0
				m.AngularVelocity = 0
			elseif braking then
				m.AngularVelocity = 0
				m.MotorMaxTorque = mass * tune.brake * WHEEL_RADIUS
			elseif math.abs(throttle) > 0.05 then
				local target = throttle * (if throttle < 0 then tune.maxSpeed * 0.4 else tune.maxSpeed)
				m.AngularVelocity = -target / WHEEL_RADIUS
				m.MotorMaxTorque = mass * tune.accel * WHEEL_RADIUS
			else
				-- coast with light drag
				m.AngularVelocity = 0
				m.MotorMaxTorque = mass * 4
			end
		end
		-- Less steering lock at speed keeps the car readable
		local speedFactor = math.clamp(1 - math.abs(forwardVel) / (tune.maxSpeed * 1.6), 0.45, 1)
		for _, s in ipairs(servos) do
			s.TargetAngle = -steer * 35 * speedFactor
		end
	end)
end

function VehicleController.init(hudController)
	hud = hudController
	local function hookCharacter(char: Model)
		local humanoid = char:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end
		humanoid.Seated:Connect(function(isSeated, seat)
			if isSeated and seat and seat:IsA("VehicleSeat") then
				startDriving(seat)
			else
				stopDriving()
			end
		end)
	end
	if player.Character then
		hookCharacter(player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
end

return VehicleController
