local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Shared = ReplicatedStorage:WaitForChild("Glasshouse")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Profiles = require(script.Parent.ProfileService)
local Commerce = require(script.Parent.CommerceService)
local World = require(script.Parent.World)

local net = Instance.new("Folder"); net.Name = "Net"; net.Parent = Shared
local stateEvent = Instance.new("RemoteEvent"); stateEvent.Name = "State"; stateEvent.Parent = net
local command = Instance.new("RemoteEvent"); command.Name = "Command"; command.Parent = net
local toastEvent = Instance.new("RemoteEvent"); toastEvent.Name = "Toast"; toastEvent.Parent = net
local s, w
local runId, finishedAt = "", 0
local ready, jobs, lastCommand, lastPrompt, exposure, stasisAt, motion, grace, lootTaken = {}, {}, {}, {}, {}, {}, {}, {}, {}
local peers = {}
local equipAt = {}
local teleportRevision = {}
local pulse, patrolTick, runCounter = 0, 0, 0

Lighting.ClockTime = 18.4; Lighting.Brightness = 2
Lighting.Ambient = Color3.fromRGB(105, 125, 151); Lighting.OutdoorAmbient = Color3.fromRGB(135, 147, 167)
Lighting.FogColor = Color3.fromRGB(101, 150, 170); Lighting.FogStart = 280; Lighting.FogEnd = 700

local function notify(player, message)
	if player and player.Parent == Players then toastEvent:FireClient(player, message) end
end

-- SERVER_STARTUP follows the world binding functions.
local function announce(message) toastEvent:FireAllClients(message) end
local function rootOf(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return nil end
	return root, hum
end
local function crew()
	local list = Players:GetPlayers(); table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end
local function host() return crew()[1] end
local function teleport(player, position)
	local root, hum = rootOf(player)
	if root then
		local id = player.UserId
		teleportRevision[id] = (teleportRevision[id] or 0) + 1
		local revision = teleportRevision[id]
		local seat = hum.SeatPart
		hum.Sit = false
		-- Detach only this character's seat weld before moving its assembly.
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld and weld:IsA("Weld") and weld.Part1 and weld.Part1:IsDescendantOf(player.Character) then weld:Destroy() end
		-- Hold authority briefly so an in-flight client physics update cannot undo a
		-- capture, entry or retry relocation. Normal character ownership then resumes.
		if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
		root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
		player.Character:PivotTo(CFrame.new(position))
		grace[id] = os.clock() + 2; motion[id] = {position = position, time = os.clock()}
		task.delay(0.5, function()
			-- Do not give a server-owned car to this client if it seated during the
			-- relocation window; restore the character once it leaves that seat.
			while teleportRevision[id] == revision and root.Parent and player.Character == root.Parent and hum.SeatPart do task.wait(0.1) end
			if teleportRevision[id] == revision and root.Parent and player.Character == root.Parent and not hum.SeatPart and root:CanSetNetworkOwnership() then
				root:SetNetworkOwnershipAuto()
			end
		end)
	end
end
local function aliveMember(player) return s and Rules.available(s, player.UserId) end
local function distanceOK(player, target, maximum)
	local root = rootOf(player)
	if not root or not target or not target.Parent then return false end
	local distance = (root.Position - target.Position).Magnitude
	return distance == distance and distance <= maximum
end
local function lineOfSight(player, target)
	local root = rootOf(player); if not root then return false end
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {w.geometry}
	-- Ground pads can share a plane with the floor. Aim above the target surface so
	-- the floor at the ray endpoint cannot incorrectly cancel recovery/extraction.
	-- Upright props use their center: raising the curator ray would hit its head.
	local padOffset = target.Size.Y <= 1 and target.Size.Y / 2 + 0.2 or 0
	local aim = target.Position + Vector3.new(0, padOffset, 0)
	return workspace:Raycast(root.Position, aim - root.Position, params) == nil
end

-- Tap a native prompt, then stay nearby. Timing and continuous checks belong to the server.
local function interact(player, target, seconds, prompt, text, allowed, complete)
	local id, now = player.UserId, os.clock()
	if not peers[id] or not prompt.Enabled or jobs[id] then return end
	if now - (lastPrompt[id] or -10) < 0.25 then return end
	lastPrompt[id] = now
	if not distanceOK(player, target, Config.InteractionDistance) or not lineOfSight(player, target) or not allowed() then return end
	jobs[id] = {target = target, prompt = prompt, duration = seconds, finish = now + seconds, text = text, allowed = allowed, complete = complete}
	notify(player, text .. " — stay nearby for " .. seconds .. "s; move away to cancel")
end

local function applyCosmetics(player)
	local profile = Profiles.get(player); local char = player.Character
	if not profile or not char then return end
	local chosen
	for _, item in ipairs(Config.Catalog) do if item.Id == profile.equipped and profile.entitlements[item.Id] then chosen = item end end
	if not chosen then return end
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Color = Color3.fromRGB(unpack(chosen.Color)); p.Material = Enum.Material.SmoothPlastic
		end
	end
end

local function updateDisplays()
	for i, pad in ipairs(w.decorPads) do
		local old = pad:FindFirstChild("Decoration"); if old then old:Destroy() end
		local player = crew()[i]; local p = player and Profiles.get(player)
		if p and p.decor ~= "" and p.entitlements[p.decor] then
			local item
			for _, c in ipairs(Config.Catalog) do if c.Id == p.decor then item = c end end
			if item then
				local ornament = World.part(pad, "Decoration", Vector3.new(2.6, 3, 2.6), pad.Position + Vector3.new(0, 2, 0), Color3.fromRGB(unpack(item.Color)), Enum.Material.Neon)
				ornament.Shape = Enum.PartType.Ball; ornament.CanCollide = false
				World.label(ornament, player.DisplayName .. " / " .. item.Name)
			end
		end
	end
end

local function broadcast()
	local roster = {}; local leader = host()
	for _, p in ipairs(crew()) do
		local member = s and s.members[p.UserId]
		table.insert(roster, {id = p.UserId, name = p.DisplayName, ready = ready[p.UserId] == true, role = member and member.role or "Next crew", captured = member and member.captured or false})
	end
	for _, player in ipairs(crew()) do
		local profile = Profiles.get(player); local job = jobs[player.UserId]; local member = s and s.members[player.UserId]
		stateEvent:FireClient(player, {
			status = s and s.status or "Lobby", roster = roster, host = leader and leader.UserId,
			member = member, seed = s and s.seed, mode = s and s.mode,
			vault = s and s.vault, heat = s and math.floor(s.heat) or 0,
			timeLeft = s and math.ceil(s.timeLeft) or Config.RunSeconds,
			signals = s and s.signalCount or 0, needed = s and s.needed or 2,
			powerOff = s and s.powerOff or false, vaultOpen = s and s.vaultOpen or false,
			core = s and s.core or "Vault", carrier = s and s.carrier,
			curator = s and s.curator or "Waiting", watchedEntrance = s and s.watchedEntrance,
			result = s and s.result, exit = s and s.exit, alarmed = s and s.alarmed or false,
			xp = profile and profile.xp or 0, wins = profile and profile.wins or 0,
			entitlements = profile and profile.entitlements or {}, equipped = profile and profile.equipped or "mint",
			decor = profile and profile.decor or "", saveStatus = Profiles.status[player.UserId] or "Loading",
			commerce = Commerce.enabled(), exposure = exposure[player.UserId] or 0,
			job = job and {text = job.text, remaining = math.max(0, job.finish - os.clock()), duration = job.duration} or nil,
			reward = s and Rules.reward(s, player.UserId) or 0,
		})
	end
end

local bindCore
local function dropCore(_position)
	if not s or s.core ~= "Dropped" then return end
	-- Recovery pedestal is known clear: a disconnect atop a solid exhibit cannot bury the core.
	local safe = Vector3.new(0, 2.5, 37)
	World.makeCore(w, safe); bindCore()
end
local function capture(player, reason)
	if not aliveMember(player) then return end
	local root = rootOf(player); local position = root and root.Position or Vector3.new(0, 3, 35)
	local hadCore = s.carrier == player.UserId
	if Rules.capture(s, player.UserId) then
		jobs[player.UserId] = nil; exposure[player.UserId] = 0
		if hadCore then dropCore(position) end
		teleport(player, w.recovery)
		notify(player, reason .. ". Recover for free at the coral pad; carried bonus prisms were lost.")
	end
end
bindCore = function()
	World.prompt(w.core, "Take core", "Aurora core", 1.5, function(player, target, seconds, prompt)
		interact(player, target, seconds, prompt, "Securing core", function()
			return aliveMember(player) and s.vaultOpen and (s.core == "Vault" or s.core == "Dropped")
		end, function()
			if Rules.takeCore(s, player.UserId) then
				w.core:Destroy(); w.core = nil; announce(player.DisplayName .. " has the core. Regroup at an extraction!")
			end
		end)
	end)
end

local function bindWorld()
	for name, entry in pairs(w.entrances) do
		World.prompt(entry.part, "Enter", name .. " approach", 1, function(player, target, seconds, prompt)
			interact(player, target, seconds, prompt, "Taking " .. name .. " route", function()
				local m = s and s.members[player.UserId]
				return s and s.status == "Active" and m and not m.entered and not m.captured
			end, function()
				if Rules.enter(s, player.UserId, name) then teleport(player, entry.destination) end
			end)
		end)
	end
	World.prompt(w.recoveryPad, "Recover", "Free / costs 15 mission seconds", 4, function(player, target, seconds, prompt)
		interact(player, target, seconds, prompt, "Recovering", function()
			return s and s.status == "Active" and s.members[player.UserId] and s.members[player.UserId].captured
		end, function()
			if Rules.recover(s, player.UserId) then teleport(player, w.spawn); notify(player, "Choose an entrance and rejoin the crew.") end
		end)
	end)
	World.prompt(w.returnGate, "Leave gallery", "Car or on-foot escape", 1, function(player, target, seconds, prompt)
		interact(player, target, seconds, prompt, "Opening getaway gate", function() return aliveMember(player) end, function()
			teleport(player, Vector3.new(22, 4, 66))
		end)
	end)
	for index, node in ipairs(w.nodes) do
		World.prompt(node, "Sync signal", "Signal " .. index, 3, function(player, target, seconds, prompt)
			interact(player, target, seconds, prompt, "Syncing signal " .. index, function()
				return aliveMember(player) and not s.signals[index] and s.signalCount < s.needed
			end, function()
				if Rules.signal(s, player.UserId, index) then node.Color = World.colors.ink; prompt.Enabled = false end
			end)
		end)
	end
	World.prompt(w.power, "Cut light grid", "Dim patrol range / quiet vault", 4, function(player, target, seconds, prompt)
		interact(player, target, seconds, prompt, "Rerouting light grid", function() return aliveMember(player) and not s.powerOff end, function()
			if Rules.power(s, player.UserId) then
				w.power.Color = World.colors.ink; Lighting.Brightness = 1.3; prompt.Enabled = false
				for _, p in ipairs(w.geometry:GetChildren()) do
					if p.Name == "Gallery light" or p.Name == "Warm windows" then p.Material = Enum.Material.SmoothPlastic; p.Color = World.colors.ink end
				end
				announce("LIGHT GRID DOWN. Patrol sight range reduced. Quiet vault route available.")
			end
		end)
	end)
	World.prompt(w.curator, "Release", "Open canal / lower heat", 2, function(player, target, seconds, prompt)
		interact(player, target, seconds, prompt, "Helping curator leave", function() return aliveMember(player) and s.curator ~= "Released" end, function()
			if Rules.curator(s, player.UserId, "Release") then w.curator.Color = World.colors.mint; announce("Curator released. Canal extraction unlocked.") end
		end)
	end)
	World.prompt(w.curator, "Capture", "+1 signal / +25 heat", 2, function(player, target, seconds, prompt)
		interact(player, target, seconds, prompt, "Detaining curator", function() return aliveMember(player) and s.curator == "Waiting" end, function()
			if Rules.curator(s, player.UserId, "Capture") then w.curator.Color = World.colors.coral; announce("Curator detained: one signal gained, crew heat +25.") end
		end)
	end, Enum.KeyCode.F)
	for name, vault in pairs(w.vaults) do
		for _, forced in ipairs({false, true}) do
			World.prompt(vault, forced and "Force vault" or "Open quietly", forced and "+65 heat / no signals needed" or "Signals + light grid required", forced and 9 or 5, function(player, target, seconds, prompt)
				if s and s.vault ~= name then notify(player, "Empty display vault. The core is in the " .. s.vault .. " wing."); return end
				if not forced and s and (s.signalCount < s.needed or not s.powerOff) then notify(player, "Sync signals and cut the light grid first."); return end
				interact(player, target, seconds, prompt, forced and "Forcing vault / +65 heat" or "Opening quietly", function()
					return aliveMember(player) and s.vault == name and not s.vaultOpen and (forced or (s.signalCount >= s.needed and s.powerOff))
				end, function()
					if Rules.vault(s, player.UserId, forced) then
						vault.Color = World.colors.gold; World.makeCore(w, vault.Position + Vector3.new(0, 4, 0)); bindCore()
						announce("VAULT OPEN. Secure the core; choose your escape.")
					end
				end)
			end, forced and Enum.KeyCode.F or Enum.KeyCode.E)
		end
	end
	for index, p in ipairs(w.loot) do
		World.prompt(p, "Take prism", "Bonus lost if captured", 1, function(player, target, seconds, prompt)
			interact(player, target, seconds, prompt, "Taking bonus prism", function() return aliveMember(player) and not lootTaken[index] end, function()
				lootTaken[index] = true; s.members[player.UserId].bonus += 1; p.Transparency = 1; prompt.Enabled = false
				p.Label.Enabled = false
			end)
		end)
	end
	for name, exit in pairs(w.exits) do
		World.prompt(exit, "Extract crew", "Core carrier / crew within 20 studs", name == "Tunnel" and 8 or 4, function(player, target, seconds, prompt)
			if s and not Rules.canExit(s, name) then notify(player, name == "Tram" and "Tram closed at 75 heat. Use the tunnel." or "Release the curator to unlock the canal."); return end
			if s and s.carrier ~= player.UserId then notify(player, "The core carrier must start extraction. Regroup here first."); return end
			interact(player, target, seconds, prompt, "Extracting / crew regroup now", function()
				return aliveMember(player) and s.carrier == player.UserId and Rules.canExit(s, name)
			end, function()
				local nearby = {}
				for _, p in ipairs(crew()) do nearby[p.UserId] = distanceOK(p, target, 20) end
				if Rules.extract(s, player.UserId, name, nearby) then announce(s.result .. " / " .. tostring(s.escapedCount) .. " crew escaped") end
			end)
		end)
	end
end

local function rebuild()
	w = World.build(); bindWorld(); World.makeCar(w); updateDisplays()
end

local function begin(player, mode)
	if player ~= host() or (s and s.status == "Active") or (s and os.clock() - finishedAt < 5) then return end
	local ids = {}
	for _, p in ipairs(crew()) do
		if not Profiles.get(p) then notify(player, "Waiting for crew profiles."); return end
		if p ~= player and not ready[p.UserId] then notify(player, p.DisplayName .. " must choose Ready first."); return end
		table.insert(ids, p.UserId)
	end
	if #ids == 0 or #ids > Config.MaxPlayers then return end
	runCounter += 1
	local day = math.floor(os.time() / 86400)
	local seed = mode == "Daily" and day or ((os.time() + runCounter * 7919) % 2147483646)
	s = Rules.new(ids, seed, mode, day); s.timeLeft = Config.RunSeconds
	runId = HttpService:GenerateGUID(false); jobs = {}; exposure = {}; stasisAt = {}; lootTaken = {}
	rebuild(); Lighting.Brightness = 2
	World.makeGuards(w, math.min(4, 1 + math.ceil(#ids / 2)), s.patrolOffset)
	for _, guard in ipairs(w.guards) do
		World.prompt(guard.part, "Stasis", "Free tool / 3 charges per run", 0.7, function(p, target, seconds, prompt)
			interact(p, target, seconds, prompt, "Stasis pulse", function()
				local m = s.members[p.UserId]
				return aliveMember(p) and m.stasis > 0 and os.clock() - (stasisAt[p.UserId] or -100) >= 15 and guard.frozenUntil <= os.clock()
			end, function()
				s.members[p.UserId].stasis -= 1; stasisAt[p.UserId] = os.clock(); guard.frozenUntil = os.clock() + 12
				exposure[p.UserId] = 0; guard.part.Color = World.colors.blue
			end)
		end)
	end
	for _, p in ipairs(crew()) do
		teleport(p, w.spawn + Vector3.new((table.find(ids, p.UserId) - 1) * 4, 0, 0)); applyCosmetics(p)
	end
	announce("Contract started. Core: " .. s.vault .. " wing. " .. s.watchedEntrance .. " entrance is watched (+12 heat).")
	print("GLASSHOUSE_RUN_START", runId, mode, seed, #ids)
end

command.OnServerEvent:Connect(function(player, action, value)
	local id, now = player.UserId, os.clock()
	if not peers[id] or type(action) ~= "string" or #action > 20 then return end
	if now - (lastCommand[id] or -10) < 0.35 then return end
	lastCommand[id] = now
	if action == "Sync" then broadcast()
	elseif action == "Ready" then
		if not s or s.status ~= "Active" then ready[id] = not ready[id] end
	elseif action == "Start" and (value == "Daily" or value == "Shuffle") then begin(player, value)
	elseif action == "Equip" and type(value) == "string" and #value <= 40 then
		local p = Profiles.get(player)
		if p and p.entitlements[value] then
			if value == p.equipped or value == p.decor or now - (equipAt[id] or -10) < 5 then return end
			equipAt[id] = now
			task.spawn(function() Profiles.queue(id, {kind = "Equip", item = value}); applyCosmetics(player); updateDisplays() end)
		else notify(player, "Earn this cosmetic first. No gameplay tools require a purchase.") end
	elseif action == "Buy" and type(value) == "string" and #value <= 40 then
		if s and s.status == "Active" then notify(player, "Cosmetics are available between runs."); return end
		task.spawn(function() local _, message = Commerce.prompt(player, value); notify(player, message) end)
	elseif action == "Cancel" then jobs[id] = nil
	end
end)

local function characterAdded(player, char)
	local hum = char:WaitForChild("Humanoid", 10); local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root or player.Parent ~= Players then return end
	hum.WalkSpeed = 18
	teleport(player, s and s.members[player.UserId] and s.members[player.UserId].captured and w.recovery or w.spawn)
	applyCosmetics(player)
	hum.Died:Connect(function() capture(player, "Crew member down"); jobs[player.UserId] = nil end)
end

local function playerAdded(player)
	if peers[player.UserId] then return end
	if #Players:GetPlayers() > Config.MaxPlayers then player:Kick("This prototype supports up to 5 players per server."); return end
	peers[player.UserId] = true; ready[player.UserId] = false
	player.CharacterAdded:Connect(function(char) characterAdded(player, char) end)
	if player.Character then task.spawn(characterAdded, player, player.Character) end
	task.spawn(function()
		Profiles.load(player)
		if player.Parent == Players then Commerce.reconcile(player); applyCosmetics(player); updateDisplays(); broadcast() end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local id = player.UserId
	local root = rootOf(player); local position = root and root.Position or Vector3.new(0, 3, 35)
	if s and Rules.remove(s, id) then dropCore(position) end
	peers[id] = nil; ready[id] = nil; jobs[id] = nil; lastCommand[id] = nil; lastPrompt[id] = nil; equipAt[id] = nil
	teleportRevision[id] = nil
	exposure[id] = nil; stasisAt[id] = nil; motion[id] = nil; grace[id] = nil
	task.spawn(Profiles.flush, id)
end)

local function finishRun()
	if not s or s.status == "Active" or s.credited then return end
	s.credited = true; finishedAt = os.clock(); jobs = {}
	local completed, completedId = s, runId
	for id in pairs(completed.members) do
		local reward = Rules.reward(completed, id)
		task.spawn(Profiles.queue, id, {kind = "Run", id = completedId, xp = reward, won = completed.status == "Success" and completed.members[id].escaped})
	end
	print("GLASSHOUSE_RUN_END", completedId, completed.result, math.floor(completed.elapsed), completed.heat, completed.captures, completed.exit or "None")
	announce(completed.result .. ". Free retry is available in 5 seconds.")
end

local function patrols(dt)
	if not s or s.status ~= "Active" then return end
	local detected = {}
	for _, guard in ipairs(w.guards) do
		local p = guard.part
		if os.clock() >= guard.frozenUntil then
			p.Color = World.colors.coral
			local goal = guard.path[guard.target]; local delta = goal - p.Position
			if delta.Magnitude <= 0.8 then guard.target = guard.target % #guard.path + 1
			else
				local pos = p.Position + delta.Unit * math.min(delta.Magnitude, dt * 6)
				p.CFrame = CFrame.lookAt(pos, goal)
			end
			guard.beam.CFrame = p.CFrame * CFrame.new(0, -3.35, -9); guard.beam.Transparency = 0.25
			for _, player in ipairs(crew()) do
				local root = rootOf(player)
				if root and aliveMember(player) then
					local deltaToPlayer = root.Position - p.Position; local distance = deltaToPlayer.Magnitude
					if distance < (s.powerOff and 17 or 27) and (distance < 6 or p.CFrame.LookVector:Dot(deltaToPlayer.Unit) > 0.55) then
						local ray = RaycastParams.new(); ray.FilterType = Enum.RaycastFilterType.Include; ray.FilterDescendantsInstances = {w.geometry}
						if not workspace:Raycast(p.Position, deltaToPlayer, ray) then detected[player.UserId] = true end
					end
				end
			end
		else guard.beam.Transparency = 1 end
	end
	for _, player in ipairs(crew()) do
		local id = player.UserId
		if aliveMember(player) then
			if detected[id] then
				exposure[id] = math.min(3.8, (exposure[id] or 0) + dt); Rules.addHeat(s, dt * 3)
				if exposure[id] >= 3.8 then capture(player, "Tagged by a security drone") end
			else exposure[id] = math.max(0, (exposure[id] or 0) - dt * 1.6) end
		end
	end
end

local function moveCars(dt)
	for _, car in ipairs(w.cars) do
		local driver = car.seat.Occupant and Players:GetPlayerFromCharacter(car.seat.Occupant.Parent)
		local allowed = driver and aliveMember(driver)
		local throttle = allowed and car.seat.ThrottleFloat or 0; local steer = allowed and car.seat.SteerFloat or 0
		car.yaw -= steer * dt * 1.7 * (throttle ~= 0 and math.sign(throttle) or 0)
		car.upright.CFrame = CFrame.Angles(0, car.yaw, 0)
		local forward = CFrame.Angles(0, car.yaw, 0).LookVector; local current = car.chassis.AssemblyLinearVelocity
		local speed = throttle * 42
		car.chassis.AssemblyLinearVelocity = Vector3.new(forward.X * speed, math.clamp(current.Y, -60, 60), forward.Z * speed)
		if car.chassis.Position.Y < -10 or math.abs(car.chassis.Position.X) > 182 or math.abs(car.chassis.Position.Z + 25) > 215 then
			car.model:PivotTo(car.origin); car.yaw = math.pi/2; car.chassis.AssemblyLinearVelocity = Vector3.zero
			for _, p in ipairs(crew()) do grace[p.UserId] = os.clock() + 2 end
		end
	end
end

local function checkMotion(player)
	local root, hum = rootOf(player); if not root then return end
	local id, pos, now = player.UserId, root.Position, os.clock()
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z or pos.Magnitude > 5000 then teleport(player, w.spawn); return end
	if pos.Y < -14 then
		if aliveMember(player) then capture(player, "Rescued from the water") else teleport(player, w.spawn) end
		return
	end
	local last = motion[id]
	local seated = hum.SeatPart and hum.SeatPart:IsDescendantOf(w.model)
	if last and now > (grace[id] or 0) then
		local displacement = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(last.position.X, 0, last.position.Z)).Magnitude
		if displacement > (seated and 65 or 32) * (now - last.time) + 9 then
			teleport(player, last.position); jobs[id] = nil; return
		end
	end
	motion[id] = {position = pos, time = now}
end

rebuild()
Players.PlayerAdded:Connect(playerAdded)
for _, player in ipairs(Players:GetPlayers()) do playerAdded(player) end
RunService.Heartbeat:Connect(function(dt)
	moveCars(math.min(dt, 0.1))
	if s then Rules.tick(s, dt) end
	for id, job in pairs(jobs) do
		local player = Players:GetPlayerByUserId(id)
		if not player or not job.target.Parent or not job.prompt.Enabled or not distanceOK(player, job.target, Config.InteractionDistance) or not lineOfSight(player, job.target) or not job.allowed() then
			jobs[id] = nil
		elseif os.clock() >= job.finish then jobs[id] = nil; job.complete() end
	end
	patrolTick += dt; pulse += dt
	if patrolTick >= 0.1 then patrols(math.min(patrolTick, 0.3)); patrolTick = 0 end
	if pulse >= 0.25 then
		pulse = 0
		for _, player in ipairs(crew()) do checkMotion(player) end
		finishRun(); broadcast()
	end
end)
print("GLASSHOUSE_READY | 1–5 players | purchases disabled: " .. tostring(not Commerce.enabled()))
