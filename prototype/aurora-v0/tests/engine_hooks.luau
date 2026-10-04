-- Appended to Main only in an isolated test copy by the trusted local plugin.
local hook = Instance.new("BindableFunction"); hook.Name = "GlasshouseEngineHook"; hook.Parent = game.ServerStorage
hook.OnInvoke = function(action, player, value)
	if action == "profilesReady" then
		for _, p in ipairs(crew()) do if not Profiles.get(p) then return false end end
		return true
	elseif action == "start" then
		for _, p in ipairs(crew()) do ready[p.UserId] = true end
		begin(host(), "Daily")
	elseif action == "state" then return s
	elseif action == "world" then return w
	elseif action == "profile" then return Profiles.get(player)
	elseif action == "diagnostic" then
		local r,h = rootOf(player)
		return {actor = player.UserId, member = s and s.members[player.UserId], status = s and s.status,
			root = r and tostring(r.Position) or "missing", health = h and h.Health or -1,
			humanoidState = h and h:GetState().Name or "none", seat = h and h.SeatPart and h.SeatPart.Name or "none",
			velocity = r and tostring(r.AssemblyLinearVelocity) or "none", jump = h and h.Jump or false,
			distance = r and value and (r.Position-value.Position).Magnitude or -1,
			line = r and value and lineOfSight(player,value) or false,
			target = value and tostring(value.Position) or "none"}
	elseif action == "job" then return jobs[player.UserId]
	elseif action == "move" then teleport(player, value)
	elseif action == "capture" then capture(player, "Engine test capture")
	elseif action == "freezePatrols" then for _, g in ipairs(w.guards) do g.frozenUntil = os.clock() + 600 end
	elseif action == "trigger" then
		assert(World._engineCallbacks[value], "Prompt callback not registered")
		World._engineCallbacks[value](player)
	end
end
