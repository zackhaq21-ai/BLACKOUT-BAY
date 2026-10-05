--!nonstrict
-- Camera feel on top of Roblox's default camera: field of view that follows sprint, sneak, vehicle speed and
-- the downed state; a short landing dip; everything smoothed and bounded (CameraFeel). One RenderStepped.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local CameraFeel = require(ReplicatedStorage.Shared.Core.CameraFeel)

local CameraController = {}

local CC = Config.Presentation.Camera
local player = Players.LocalPlayer
local fov = CC.BaseFov
local dip = 0
local pendingDip = 0
local humanoid: Humanoid? = nil
local seatTune = nil
local conn

local function vehicleTune(hum: Humanoid)
	local seat = hum.SeatPart
	local model = seat and seat:FindFirstAncestorWhichIsA("Model")
	local kind = model and model:GetAttribute("Kind")
	return kind and Config.Vehicles[kind] or nil
end

-- Called by MovementController on landing with the downward speed.
function CameraController.landed(fallSpeed: number)
	pendingDip = math.max(pendingDip, CameraFeel.landingDip(CC, fallSpeed))
end

local function step(dt: number)
	local cam = workspace.CurrentCamera
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not cam or not hum then
		return
	end
	if hum ~= humanoid then
		humanoid = hum
		seatTune = nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local seated = hum.SeatPart ~= nil
	if seated and not seatTune then
		seatTune = vehicleTune(hum)
	elseif not seated then
		seatTune = nil
	end
	local vel = if root then root.AssemblyLinearVelocity else Vector3.zero
	local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local target = CameraFeel.targetFov(CC, {
		speed = flat,
		topSpeed = Config.Player.SprintSpeed,
		sprinting = player:GetAttribute("Sprinting") == true,
		sneaking = player:GetAttribute("Sneaking") == true,
		seated = seated,
		vehicleSpeed = flat,
		vehicleTopSpeed = seatTune and seatTune.maxSpeed or 60,
		downed = hum.PlatformStand or hum.Health <= 0,
	})
	fov = CameraFeel.approach(fov, target, CC.FovSmoothing, dt)
	cam.FieldOfView = fov
	-- Landing dip: drop fast, recover smoothly, through the humanoid's camera offset so collision still works
	if pendingDip > 0 then
		dip = math.max(dip, pendingDip)
		pendingDip = 0
	end
	dip = CameraFeel.approach(dip, 0, CC.DipRecover, dt)
	hum.CameraOffset = Vector3.new(0, -dip, 0)
end

function CameraController.init()
	conn = RunService.RenderStepped:Connect(step)
end

function CameraController.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

return CameraController
