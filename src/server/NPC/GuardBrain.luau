--!nonstrict
-- Museum guard: patrols a route, reports what it sees to SecurityState, investigates what it half-sees,
-- chases and detains when the building is on alert. Readable: its nameplate says what it is doing.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rig = require(script.Parent.Rig)

local GuardBrain = {}
GuardBrain.__index = GuardBrain

function GuardBrain.new(ctx, route, security)
	local self = setmetatable({}, GuardBrain)
	self.ctx = ctx
	self.route = route
	self.security = security
	self.id = "guard_" .. route.id
	self.label = route.label
	self.carriesCard = route.carriesCard
	self.hasCard = route.carriesCard ~= nil
	self.waypoint = 1
	self.pauseUntil = 0
	self.state = "Patrol"
	self.target = nil
	self.lastKnown = nil
	self.lastSeenAt = 0
	self.detainTimer = 0
	self.investigateUntil = 0
	self.model = Rig.create(self.id, Palette.SeaGlassDeep, route.label, ctx.world.npcFolder, CFrame.new(route.points[1].position))
	self.humanoid = self.model:FindFirstChildOfClass("Humanoid")
	self.root = self.model:FindFirstChild("HumanoidRootPart")
	self.humanoid.WalkSpeed = Config.Museum.GuardWalkSpeed
	return self
end

function GuardBrain:setState(state: string, suffix: string?)
	if self.state ~= state then
		self.state = state
		Rig.setPlateText(self.model, self.label .. " — " .. (suffix or state))
	end
end

function GuardBrain:position(): Vector3
	return self.root.Position
end

function GuardBrain:eyeCFrame(): CFrame
	return self.root.CFrame * CFrame.new(0, 1.5, 0)
end

function GuardBrain:moveTo(pos: Vector3)
	self.humanoid:MoveTo(pos)
end

-- Navmesh pathing for off-route movement (chases, investigations). Recomputed at most once per second.
function GuardBrain:pathTo(goal: Vector3, now: number)
	if not self.path or now - (self.pathAt or 0) > 1 or (self.pathGoal and (self.pathGoal - goal).Magnitude > 6) then
		self.pathAt = now
		self.pathGoal = goal
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
		local ok = pcall(function()
			path:ComputeAsync(self:position(), goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			self.path = path:GetWaypoints()
			self.pathIndex = 2
		else
			self.path = nil
		end
	end
	if self.path and self.path[self.pathIndex] then
		local wp = self.path[self.pathIndex]
		if (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(self:position().X, 0, self:position().Z)).Magnitude < 4 then
			self.pathIndex += 1
			wp = self.path[self.pathIndex]
		end
		if wp then
			self:moveTo(wp.Position)
			return
		end
	end
	self:moveTo(goal)
end

function GuardBrain:reset()
	self.waypoint = 1
	self.state = "Patrol"
	self.target = nil
	self.lastKnown = nil
	self.path = nil
	self.detainTimer = 0
	self.hasCard = self.carriesCard ~= nil
	self.humanoid.WalkSpeed = Config.Museum.GuardWalkSpeed
	self.model:PivotTo(CFrame.new(self.route.points[1].position))
	Rig.setPlateText(self.model, self.label)
end

local function distXZ(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

function GuardBrain:tick(dt: number, now: number, vision)
	if not self.root or not self.root.Parent then
		return
	end
	local cfg = Config.Museum
	local level = self.security.level
	-- Perception
	local bestSeen, bestDist = nil, math.huge
	local viewDistance = cfg.GuardViewDistance * (if vision.viewScale then vision.viewScale() else 1)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = vision.playerRoot(player)
		if root and vision.insideOrNear(root.Position) then
			local d = (root.Position - self:position()).Magnitude
			if d <= viewDistance and vision.canSee(self:eyeCFrame(), root, viewDistance, cfg.GuardViewAngle, self.model) then
				local v = self.security:report(self.id, self.label, tostring(player.UserId), dt, player:GetAttribute("Sneaking") == true, now)
				vision.onSeen(player, self, v)
				if d < bestDist then
					bestSeen, bestDist = player, d
				end
			end
		end
	end
	if bestSeen then
		self.lastKnown = vision.playerRoot(bestSeen).Position
		self.lastSeenAt = now
		if level >= 2 then
			self.target = bestSeen
		end
	end

	-- Behaviour
	if level >= 2 then
		self.humanoid.WalkSpeed = cfg.GuardAlertSpeed + (if vision.speedBonus then vision.speedBonus() else 0)
		local target = self.target
		local troot = target and vision.playerRoot(target)
		if troot and target.Parent and not vision.isJailed(target) then
			local d = distXZ(troot.Position, self:position())
			if now - self.lastSeenAt < 6 then
				self:setState("Chase", "chasing " .. target.Name)
				self:pathTo(troot.Position, now)
				if d <= cfg.DetainRange then
					self.detainTimer += dt
					if self.detainTimer >= cfg.DetainSeconds then
						self.detainTimer = 0
						vision.detain(target, self)
						self.target = nil
					end
				elseif d > cfg.DetainBreakRange then
					self.detainTimer = 0
				end
				return
			end
			self.target = nil
		end
		-- Lost them: go to the last place something happened, then sweep the patrol at speed
		local focus = self.lastKnown or vision.alarmOrigin()
		if focus and distXZ(focus, self:position()) > 4 and now - self.lastSeenAt < 12 then
			self:setState("Search", "searching")
			self:pathTo(focus, now)
			return
		end
		self:setState("Sweep", "sweeping")
	else
		self.humanoid.WalkSpeed = cfg.GuardWalkSpeed + (if vision.speedBonus then vision.speedBonus() else 0)
		self.detainTimer = 0
		self.target = nil
		-- Investigate when this guard's own suspicion crosses the threshold
		if self.lastKnown and now - self.lastSeenAt < 1 and level >= 1 then
			self.investigateUntil = now + 5
		end
		if now < self.investigateUntil and self.lastKnown then
			self:setState("Investigate", "investigating")
			self:pathTo(self.lastKnown, now)
			return
		end
		self:setState("Patrol", nil)
		Rig.setPlateText(self.model, self.label)
	end

	-- Patrol route
	if now < self.pauseUntil then
		return
	end
	local wp = self.route.points[self.waypoint]
	if distXZ(wp.position, self:position()) <= 3 then
		self.pauseUntil = now + (if level >= 2 then 0.5 else wp.pause)
		self.waypoint = (self.waypoint % #self.route.points) + 1
		wp = self.route.points[self.waypoint]
	end
	self:moveTo(wp.position)
end

function GuardBrain:destroy()
	if self.model then
		self.model:Destroy()
	end
end

return GuardBrain
