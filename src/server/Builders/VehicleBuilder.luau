--!nonstrict
-- Constraint cars built from parts: a heavy chassis, a light body, four hinge-driven wheels with servo
-- steering on the front axle, a VehicleSeat, passenger seats and a trunk. Tuning comes from Config.Vehicles.
-- The seated client drives the constraints (responsive); the server owns damage, trunk contents and speed sanity.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)

local VehicleBuilder = {}

local WHEEL_RADIUS = 1.4

local SHAPES = {
	Kestrel = { length = 13, width = 6.2, cabin = { 5.4, 2.2, 6 }, color = Palette.SeaGlassDeep, chassisY = 1.1 },
	Courier = { length = 16, width = 7, cabin = { 6.6, 4.5, 12 }, color = Palette.PaleStone, chassisY = 1.1 },
	Commuter = { length = 13, width = 6.2, cabin = { 5.4, 2.4, 7 }, color = Palette.WarmStone, chassisY = 1.1 },
	Cruiser = { length = 14, width = 6.4, cabin = { 5.6, 2.3, 6.5 }, color = Palette.Police, chassisY = 1.1 },
}

local function mk(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = true
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

local function attachment(part: BasePart, name: string, cf: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf
	a.Parent = part
	return a
end

function VehicleBuilder.build(parent: Instance, kind: string, cf: CFrame, id: string): Model
	local tune = Config.Vehicles[kind]
	local shape = SHAPES[kind] or SHAPES.Commuter
	local model = Instance.new("Model")
	model.Name = "Vehicle_" .. id
	model:SetAttribute("VehicleId", id)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Health", tune.health)
	model:SetAttribute("MaxHealth", tune.health)
	model:SetAttribute("Disabled", false)
	model:SetAttribute("Label", tune.label)

	local L, Wd = shape.length, shape.width
	local chassis = mk(model, "Chassis", Vector3.new(Wd, 1.2, L), cf * CFrame.new(0, shape.chassisY, 0), Palette.Night, Enum.Material.Metal)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(4 * tune.mass, 0.3, 0.2)
	model.PrimaryPart = chassis
	local body = mk(model, "Body", Vector3.new(Wd - 0.4, 1.6, L - 1), chassis.CFrame * CFrame.new(0, 1.4, 0), shape.color, Enum.Material.SmoothPlastic)
	body.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.3, 0.2)
	weld(chassis, body)
	local cab = shape.cabin
	local cabin = mk(model, "Cabin", Vector3.new(cab[1], cab[2], cab[3]), chassis.CFrame * CFrame.new(0, 2.2 + cab[2] / 2, if kind == "Courier" then 1.5 else -0.5), shape.color, Enum.Material.SmoothPlastic)
	cabin.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.3, 0.2)
	weld(chassis, cabin)
	local glass = mk(model, "Glass", Vector3.new(cab[1] - 0.4, cab[2] - 0.6, cab[3] + 0.2), cabin.CFrame * CFrame.new(0, 0.1, 0), Palette.Glass, Enum.Material.Glass, { Transparency = 0.4, CanCollide = false, Reflectance = 0.2 })
	glass.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.2)
	weld(chassis, glass)
	-- Headlights and tail lights
	for _, side in ipairs({ -1, 1 }) do
		local head = mk(model, "Headlight", Vector3.new(1.2, 0.6, 0.3), chassis.CFrame * CFrame.new(side * (Wd / 2 - 1), 1.3, -L / 2 + 0.1), Palette.WarmInterior, Enum.Material.Neon, { CanCollide = false })
		head.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.2)
		local sl = Instance.new("SpotLight")
		sl.Face = Enum.NormalId.Front
		sl.Angle = 60
		sl.Range = 48
		sl.Brightness = 1.5
		sl.Color = Palette.WarmInterior
		sl.Parent = head
		weld(chassis, head)
		local tail = mk(model, "Taillight", Vector3.new(1.2, 0.6, 0.3), chassis.CFrame * CFrame.new(side * (Wd / 2 - 1), 1.3, L / 2 - 0.1), Palette.SecurityRed, Enum.Material.Neon, { CanCollide = false })
		tail.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.2)
		weld(chassis, tail)
	end
	if kind == "Cruiser" then
		local bar = mk(model, "LightBar", Vector3.new(4, 0.5, 1), cabin.CFrame * CFrame.new(0, cab[2] / 2 + 0.25, 0), Palette.PoliceLight, Enum.Material.Neon, { CanCollide = false })
		bar.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.2)
		local pl = Instance.new("PointLight")
		pl.Color = Palette.PoliceLight
		pl.Brightness = 0
		pl.Range = 40
		pl.Parent = bar
		weld(chassis, bar)
		local decal = Instance.new("SurfaceGui")
		decal.Face = Enum.NormalId.Right
		decal.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		decal.PixelsPerStud = 20
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = "POLICE"
		tl.TextScaled = true
		tl.Font = Enum.Font.GothamBold
		tl.TextColor3 = Palette.PaleStone
		tl.Parent = decal
		decal.Parent = body
	end

	-- Wheels: front wheels on steering knuckles (servo hinge about Y), all wheels motor hinges about X.
	local axleZ = L / 2 - 2.6
	local wheelX = Wd / 2 + 1.5 -- wheel centre clears the chassis edge by 0.1 (radius 1.4)
	for _, spec in ipairs({ { -1, -1, true }, { 1, -1, true }, { -1, 1, false }, { 1, 1, false } }) do
		local sx, sz, steer = spec[1], spec[2], spec[3]
		local wheelPos = chassis.CFrame * CFrame.new(sx * wheelX, -0.2, sz * axleZ)
		local hub = chassis
		if steer then
			local knuckle = mk(model, "Knuckle", Vector3.new(0.8, 0.8, 0.8), wheelPos * CFrame.new(-sx * 0.9, 0, 0), Palette.Industrial, Enum.Material.Metal, { CanCollide = false })
			knuckle.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.2)
			local a0 = attachment(chassis, "SteerA0", chassis.CFrame:ToObjectSpace(knuckle.CFrame) * CFrame.Angles(0, 0, math.rad(90)))
			local a1 = attachment(knuckle, "SteerA1", CFrame.Angles(0, 0, math.rad(90)))
			local servo = Instance.new("HingeConstraint")
			servo.Name = "SteerServo"
			servo.Attachment0 = a0
			servo.Attachment1 = a1
			servo.ActuatorType = Enum.ActuatorType.Servo
			servo.ServoMaxTorque = 1e7
			servo.AngularSpeed = 6
			servo.TargetAngle = 0
			servo.LimitsEnabled = true
			servo.LowerAngle = -35
			servo.UpperAngle = 35
			servo.Parent = chassis
			hub = knuckle
		end
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Shape = Enum.PartType.Ball
		wheel.Size = Vector3.new(WHEEL_RADIUS * 2, WHEEL_RADIUS * 2, WHEEL_RADIUS * 2)
		wheel.CFrame = wheelPos
		wheel.Color = Palette.Night
		wheel.Material = Enum.Material.Rubber
		wheel.CustomPhysicalProperties = PhysicalProperties.new(1.2, 2, 0, 1, 1)
		wheel.Anchored = false
		wheel.CanCollide = true
		wheel.Parent = model
		local a0 = attachment(hub, "WheelA0", hub.CFrame:ToObjectSpace(wheelPos))
		local a1 = attachment(wheel, "WheelA1", CFrame.new())
		local motor = Instance.new("HingeConstraint")
		motor.Name = "WheelMotor"
		motor.Attachment0 = a0
		motor.Attachment1 = a1
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.AngularVelocity = 0
		motor.MotorMaxTorque = 0
		motor.MotorMaxAcceleration = 60
		motor.Parent = hub
	end

	-- Seats
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.6, 2)
	seat.CFrame = chassis.CFrame * CFrame.new(-1.3, 2.1, -1)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Anchored = false
	seat.MaxSpeed = tune.maxSpeed
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	seat.Disabled = false
	seat.Parent = model
	weld(chassis, seat)
	for i = 2, tune.seats do
		local ps = Instance.new("Seat")
		ps.Name = "PassengerSeat" .. i
		ps.Size = Vector3.new(2, 0.6, 2)
		local col = if i % 2 == 0 then 1.3 else -1.3
		local row = if i <= 2 then -1 else 2.5
		ps.CFrame = chassis.CFrame * CFrame.new(col, 2.1, row)
		ps.Transparency = 1
		ps.CanCollide = false
		ps.Anchored = false
		ps.Parent = model
		weld(chassis, ps)
	end

	-- Trunk (prompt target) at the rear
	local trunk = mk(model, "Trunk", Vector3.new(Wd - 1, 0.4, 2), chassis.CFrame * CFrame.new(0, 2.3, L / 2 - 1.5), Palette.Night, Enum.Material.SmoothPlastic, { CanCollide = false, Transparency = 0.5 })
	trunk.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.2)
	weld(chassis, trunk)
	attachment(trunk, "TrunkAttachment", CFrame.new(0, 0.6, 0))

	-- Smoke emitter for the disabled state
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Enabled = false
	smoke.Rate = 25
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Speed = NumberRange.new(4, 7)
	smoke.Size = NumberSequence.new(1.5, 4)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Color = ColorSequence.new(Palette.Industrial)
	smoke.Parent = cabin

	model.Parent = parent
	return model
end

return VehicleBuilder
