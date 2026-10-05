--!nonstrict
-- Drives constraint cars from the driver's seat inputs (throttle/steer come from VehicleSeat for keyboard,
-- gamepad and touch). The seated client owns the physics, so this is responsive; the server owns damage.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local VehicleFeel = require(ReplicatedStorage.Shared.Core.VehicleFeel)

local PV = Config.Presentation.Vehicle

local VehicleController = {}

local player = Players.LocalPlayer
local WHEEL_RADIUS = Config.Vehicles.WheelRadius
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
		if active.engine and active.engine.IsPlaying then
			active.engine:Stop()
		end
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
	local engine = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Engine")
	if engine and engine:IsA("Sound") and engine.SoundId ~= "" and not engine.IsPlaying then
		engine:Play()
	end
	active = { seat = seat, model = model, chassis = model.PrimaryPart, motors = motors, servos = servos, tune = tune, engine = if engine and engine:IsA("Sound") then engine else nil }
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
		local mode = if disabled then "coast" else VehicleFeel.mode(PV, throttle, forwardVel)
		for _, m in ipairs(motors) do
			if disabled then
				m.MotorMaxTorque = 0
				m.AngularVelocity = 0
			elseif mode == "brake" then
				m.AngularVelocity = 0
				m.MotorMaxTorque = mass * tune.brake * WHEEL_RADIUS
			elseif mode == "drive" or mode == "reverse" then
				-- strong pull-away, fading toward top speed (VehicleFeel curve)
				m.AngularVelocity = -VehicleFeel.targetSpeed(PV, tune, throttle, mode) / WHEEL_RADIUS
				m.MotorMaxTorque = mass * tune.accel * WHEEL_RADIUS * VehicleFeel.torqueFactor(PV, tune, forwardVel)
			else
				m.AngularVelocity = 0
				m.MotorMaxTorque = mass * PV.CoastDrag
			end
		end
		-- Less lock and slower hands at speed; heavy classes slower still (same maths as the NPC drivers)
		local lock = VehicleFeel.steerLock(PV, tune, forwardVel)
		local servoSpeed = VehicleFeel.steerSpeed(PV, tune, forwardVel)
		for _, s in ipairs(servos) do
			s.TargetAngle = -steer * 35 * lock
			s.AngularSpeed = servoSpeed
		end
		-- Engine bed (silent until an id is set): pitch follows speed and load
		local engine = active.engine
		if engine then
			local load = math.abs(throttle)
			engine.PlaybackSpeed = 0.75 + math.clamp(math.abs(forwardVel) / tune.maxSpeed, 0, 1) * 0.7 + load * 0.1
			engine.Volume = 0.3 + load * 0.25
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
