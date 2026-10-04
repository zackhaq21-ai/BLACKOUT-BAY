local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Config = require(game.ReplicatedStorage.Glasshouse.Config)
local Model = require(script.Parent.ProfileModel)
local Service = {profiles = {}, pending = {}, status = {}, busy = {}}
local live = Config.DataStoreEnabled and not RunService:IsStudio()
local store = live and DataStoreService:GetDataStore(Config.DataStoreName) or nil

function Service.load(player)
	local id = player.UserId
	if Service.status[id] then return end
	Service.status[id] = "Loading"
	Service.pending[id] = {}
	if not live then
		Service.profiles[id] = Model.clean(nil)
		Service.status[id] = "Session only"
		return
	end
	for attempt = 1, 3 do
		local ok, data = pcall(function() return Model.clean(store:GetAsync("p_" .. id)) end)
		if ok then Service.profiles[id] = data; Service.status[id] = "Saved"; return end
		warn("Glasshouse profile load failed; existing data will not be overwritten", id, attempt)
		task.wait(attempt)
	end
	Service.profiles[id] = Model.clean(nil)
	Service.status[id] = "Unavailable / unsaved session"
end

function Service.get(player)
	return Service.profiles[player.UserId]
end

function Service.transaction(id, op)
	local began = os.clock()
	while Service.busy[id] and os.clock() - began < 8 do task.wait(0.1) end
	if Service.busy[id] or not Service.profiles[id] then return false end
	Service.busy[id] = true
	local ok, updated
	if live and Service.status[id] ~= "Unavailable / unsaved session" then
		ok, updated = pcall(function()
			return store:UpdateAsync("p_" .. id, function(old)
				return Model.apply(old, op, Config.Catalog)
			end)
		end)
	else
		ok, updated = pcall(Model.apply, Service.profiles[id], op, Config.Catalog)
	end
	if ok then
		Service.profiles[id] = updated
		if live and Service.status[id] ~= "Unavailable / unsaved session" then Service.status[id] = "Saved" end
	elseif live then
		Service.status[id] = "Save pending"
		warn("Glasshouse save failed; operation retained for retry", id, op.kind)
	end
	Service.busy[id] = nil
	return ok
end

function Service.queue(id, op)
	Service.pending[id] = Service.pending[id] or {}
	table.insert(Service.pending[id], op)
	Service.flush(id)
end

function Service.flush(id)
	if Service.flushing and Service.flushing[id] then return end
	Service.flushing = Service.flushing or {}; Service.flushing[id] = true
	local queue = Service.pending[id]
	while queue and #queue > 0 do
		if not Service.transaction(id, queue[1]) then break end
		table.remove(queue, 1)
	end
	Service.flushing[id] = nil
end

function Service.canCommerce(id)
	return live and Service.profiles[id] ~= nil and Service.status[id] == "Saved"
end

function Service.canPersist(id)
	return live and Service.profiles[id] ~= nil and (Service.status[id] == "Saved" or Service.status[id] == "Save pending")
end

task.spawn(function()
	while task.wait(30) do
		for id, queue in pairs(Service.pending) do if #queue > 0 then task.spawn(Service.flush, id) end end
	end
end)

game:BindToClose(function()
	local deadline = os.clock() + 25
	while os.clock() < deadline do
		local unfinished = false
		for id, queue in pairs(Service.pending) do
			if #queue > 0 or Service.busy[id] or (Service.flushing and Service.flushing[id]) then
				unfinished = true
				if not Service.busy[id] and not (Service.flushing and Service.flushing[id]) then task.spawn(Service.flush, id) end
			end
		end
		if not unfinished then break end
		task.wait(0.2)
	end
end)
return Service
