--!nonstrict
-- Durable hideout records (stash, tier, raid lock, reports), separate from player profiles so a raider on
-- another server can act on an offline owner's hideout. Every mutation is a pure HideoutRecord transform
-- applied inside UpdateAsync on the stored value; nothing is ever written from a cached copy.
-- Falls back to an in-memory table when DataStores are unavailable (offline Studio), with the same API.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HideoutRecord = require(ReplicatedStorage.Shared.Core.HideoutRecord)

local HideoutStore = { ctx = nil :: any }

local STORE = "GlasshouseHideouts"
local INDEX = "GlasshouseHideoutIndex"
local store, index
local memory = {} -- userId -> record (fallback)
local cache = {} -- userId -> last known record (display only, never written back)
local names = {} -- userId -> last known display name
HideoutStore.backend = "memory"

local function key(userId: number): string
	return Config.Server.DevDataPrefix .. "/" .. tostring(userId)
end

function HideoutStore.init(ctx)
	HideoutStore.ctx = ctx
	local ok = pcall(function()
		store = DataStoreService:GetDataStore(STORE)
		index = DataStoreService:GetOrderedDataStore(INDEX)
	end)
	if ok and store then
		-- Probe once: offline Studio throws on first use
		local probeOk = pcall(function()
			store:GetAsync(key(0))
		end)
		HideoutStore.backend = if probeOk then "datastore" else "memory"
	end
	if HideoutStore.backend == "memory" then
		warn("[HideoutStore] DataStore unavailable; hideouts live in memory for this server only")
	end
end

function HideoutStore.start() end

function HideoutStore.nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
	end
	return names[userId] or ("Player " .. tostring(userId))
end

function HideoutStore.rememberName(userId: number, name: string)
	names[userId] = name
end

local function updateIndex(userId: number, stash: number)
	if HideoutStore.backend ~= "datastore" then
		return
	end
	task.spawn(function()
		pcall(function()
			index:SetAsync(key(userId), stash)
		end)
	end)
end

-- Read-only snapshot. Returns (record, fresh). `fresh` is false when served from cache after a failure.
function HideoutStore.load(userId: number): (HideoutRecord.Record, boolean)
	if HideoutStore.backend == "memory" then
		local r = memory[userId] or HideoutRecord.default()
		memory[userId] = r
		cache[userId] = r
		return r, true
	end
	local ok, raw = pcall(function()
		return store:GetAsync(key(userId))
	end)
	if ok then
		local r = HideoutRecord.migrate(raw)
		cache[userId] = r
		return r, true
	end
	return cache[userId] or HideoutRecord.default(), false
end

-- Apply a pure transform atomically. transform(record) -> (record | nil, result). Returns (ok, result, record).
function HideoutStore.apply(userId: number, transform)
	if HideoutStore.backend == "memory" then
		local r = memory[userId] or HideoutRecord.default()
		local snapshot = HideoutRecord.migrate(r)
		local newRec, result = transform(snapshot)
		if newRec then
			memory[userId] = newRec
			cache[userId] = newRec
			return true, result, newRec
		end
		return false, result, r
	end
	local result
	local applied = nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(userId), function(old)
			local rec = HideoutRecord.migrate(old)
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
		warn("[HideoutStore] update failed for " .. tostring(userId) .. ": " .. tostring(err))
		return false, "store unavailable", cache[userId] or HideoutRecord.default()
	end
	if applied then
		cache[userId] = applied
		updateIndex(userId, applied.stash)
		return true, result, applied
	end
	return false, result, cache[userId] or HideoutRecord.default()
end

-- Richest hideouts for the raid board. Returns { {userId, stash} }.
function HideoutStore.richest(n: number): { { userId: number, stash: number } }
	local out = {}
	if HideoutStore.backend == "memory" then
		for userId, r in pairs(memory) do
			table.insert(out, { userId = userId, stash = r.stash })
		end
		table.sort(out, function(a, b)
			return a.stash > b.stash
		end)
		while #out > n do
			table.remove(out)
		end
		return out
	end
	local ok, pages = pcall(function()
		return index:GetSortedAsync(false, n)
	end)
	if ok and pages then
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)
		if okPage then
			for _, entry in ipairs(page) do
				local userId = tonumber(string.match(entry.key, "/(%d+)$") or "")
				if userId then
					table.insert(out, { userId = userId, stash = entry.value })
				end
			end
		end
	end
	return out
end

function HideoutStore.cached(userId: number): HideoutRecord.Record?
	return cache[userId]
end

return HideoutStore
