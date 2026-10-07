--!nonstrict
-- Durable crew records: DataStore "GlasshouseCrews" keyed by owner user id, with the same pure-transform-in-
-- UpdateAsync pattern as HideoutStore and an in-memory fallback when DataStores are unavailable.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local CrewRecord = require(ReplicatedStorage.Shared.Core.CrewRecord)

local CrewStore = { ctx = nil :: any }

local STORE = "GlasshouseCrews"
local store = nil
local memory = {} -- ownerUserId -> record
local cache = {}
CrewStore.backend = "memory"

local function key(ownerUserId: number): string
	return Config.Server.DevDataPrefix .. "/crew/" .. tostring(ownerUserId)
end

function CrewStore.init(ctx)
	CrewStore.ctx = ctx
	local ok = pcall(function()
		store = DataStoreService:GetDataStore(STORE)
	end)
	local probeOk = ok and pcall(function()
		store:GetAsync(Config.Server.DevDataPrefix .. "/crew/probe")
	end)
	CrewStore.backend = if probeOk then "datastore" else "memory"
	if CrewStore.backend == "memory" then
		warn("[CrewStore] DataStore unavailable; crew records live in memory for this server only")
	end
end

function CrewStore.start() end

local function migrate(raw, ownerUserId: number, ownerName: string)
	return CrewRecord.migrate(raw, ownerUserId, ownerName, os.time(), Config.Crews)
end

function CrewStore.load(ownerUserId: number, ownerName: string): (CrewRecord.Record, boolean)
	if CrewStore.backend == "memory" then
		local r = migrate(memory[ownerUserId], ownerUserId, ownerName)
		memory[ownerUserId] = r
		cache[ownerUserId] = r
		return r, true
	end
	local ok, raw = pcall(function()
		return store:GetAsync(key(ownerUserId))
	end)
	if ok then
		local r = migrate(raw, ownerUserId, ownerName)
		cache[ownerUserId] = r
		return r, true
	end
	return cache[ownerUserId] or migrate(nil, ownerUserId, ownerName), false
end

-- transform(record) -> (record | nil, result). Returns (ok, result, record).
function CrewStore.apply(ownerUserId: number, ownerName: string, transform)
	if CrewStore.backend == "memory" then
		local snapshot = migrate(memory[ownerUserId], ownerUserId, ownerName)
		local newRec, result = transform(snapshot)
		if newRec then
			memory[ownerUserId] = newRec
			cache[ownerUserId] = newRec
			return true, result, newRec
		end
		return false, result, cache[ownerUserId] or snapshot
	end
	local result, applied = nil, nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(ownerUserId), function(old)
			local rec = migrate(old, ownerUserId, ownerName)
			local newRec, res = transform(rec)
			result = res
			if newRec then
				applied = newRec
				return newRec
			end
			return nil
		end)
	end)
	if not ok then
		warn("[CrewStore] update failed for " .. tostring(ownerUserId) .. ": " .. tostring(err))
		return false, "store unavailable", cache[ownerUserId] or migrate(nil, ownerUserId, ownerName)
	end
	if applied then
		cache[ownerUserId] = applied
		return true, result, applied
	end
	return false, result, cache[ownerUserId] or migrate(nil, ownerUserId, ownerName)
end

function CrewStore.cached(ownerUserId: number)
	return cache[ownerUserId]
end

return CrewStore
