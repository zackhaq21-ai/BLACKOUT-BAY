--!nonstrict
-- Player profiles with session locking and explicit failure handling.
-- Rules: a profile that failed to load is NEVER saved (so defaults can't overwrite real data);
-- a profile locked by another live server is served read-only; saves use UpdateAsync and only
-- write when this server holds the lock. Dev/test data lives under a separate scope prefix.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ProfileOps = require(ReplicatedStorage.Shared.Core.ProfileOps)
local Standing = require(ReplicatedStorage.Shared.Core.Standing)
local Onboarding = require(ReplicatedStorage.Shared.Core.Onboarding)
ProfileOps.configure(Standing, Onboarding, Config.Progression)

local DataService = { ctx = nil :: any }

local STORE_NAME = "GlasshouseProfiles"
local PROFILE_VERSION = 2 -- v2: awardsSeen, standingDay, onboarding (all optional; v1 data migrates with defaults)
local LOCK_TIMEOUT = 150 -- seconds; a stale lock older than this is considered dead
local AUTOSAVE_INTERVAL = 120
local LOAD_RETRIES = 3

export type Profile = {
	data: any, -- see defaults()
	saveable: boolean, -- false when load failed or another server holds the lock
	reason: string?, -- why it is not saveable
	loadedAt: number,
	dirty: boolean,
}

local profiles: { [Player]: Profile } = {}
local store = nil
local storeOk = false

local pending: { [Player]: { any } } = {} -- ops not yet durable in the store (retried)
local flushing: { [Player]: boolean } = {}
local flush -- defined below start(); forward declared because start() schedules flushes

local function defaults()
	return {
		cash = Config.Economy.StartingCash,
		stats = { jobs = 0, delivered = 0, arrests = 0 },
		xp = 0,
		wins = 0,
		entitlements = { mint = true }, -- permanent; raids and lost runs never remove entries
		receipts = {},
		runsSeen = {},
		equipped = "mint",
		decor = "",
		awardsSeen = {}, -- Standing award ids credited (pruned past Config.Progression.MaxAwardsSeen)
		standingDay = { day = "", counts = {} }, -- per-source daily counters for diminishing
		onboarding = { step = 1, done = false },
		version = PROFILE_VERSION,
	}
end

local function keyFor(player: Player): string
	return Config.Server.DevDataPrefix .. "/" .. tostring(player.UserId)
end

local function migrate(data)
	data = data or {}
	local d = defaults()
	if type(data.cash) == "number" then
		d.cash = data.cash
	end
	if type(data.stats) == "table" then
		for k in pairs(d.stats) do
			if type(data.stats[k]) == "number" then
				d.stats[k] = data.stats[k]
			end
		end
	end
	for _, k in ipairs({ "xp", "wins" }) do
		local v = data[k]
		if type(v) == "number" and v == v and v >= 0 and v < 1e12 then
			d[k] = math.floor(v)
		end
	end
	for _, k in ipairs({ "entitlements", "receipts", "runsSeen" }) do
		if type(data[k]) == "table" then
			for key, value in pairs(data[k]) do
				if type(key) == "string" and #key <= 160 and value == true then
					d[k][key] = true
				end
			end
		end
	end
	-- legacy field from the first schema draft
	if type(data.cosmetics) == "table" then
		for key, value in pairs(data.cosmetics) do
			if type(key) == "string" and value == true then
				d.entitlements[key] = true
			end
		end
	end
	for _, k in ipairs({ "equipped", "decor" }) do
		if type(data[k]) == "string" and #data[k] < 50 then
			d[k] = data[k]
		end
	end
	-- v2 progression fields: validate every entry; anything malformed falls back to the default
	if type(data.awardsSeen) == "table" then
		for key, value in pairs(data.awardsSeen) do
			if type(key) == "string" and #key <= 120 and type(value) == "string" and #value <= 12 then
				d.awardsSeen[key] = value
			end
		end
	end
	if type(data.standingDay) == "table" and type(data.standingDay.day) == "string" and #data.standingDay.day <= 12 and type(data.standingDay.counts) == "table" then
		d.standingDay.day = data.standingDay.day
		for key, value in pairs(data.standingDay.counts) do
			if type(key) == "string" and #key <= 32 and type(value) == "number" and value == value and value >= 0 and value < 1e6 then
				d.standingDay.counts[key] = math.floor(value)
			end
		end
	end
	d.onboarding = Onboarding.fromStored(data.onboarding)
	return d
end

local function tryStore()
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = s
		storeOk = true
	else
		warn("[DataService] DataStore unavailable: " .. tostring(s) .. " — profiles will be in-memory only (not saved)")
	end
end

-- Attempts to acquire the session lock and load. Returns (data, saveable, reason).
local function loadWithLock(player: Player)
	if not storeOk then
		return defaults(), false, "DataStore unavailable in this session"
	end
	local key = keyFor(player)
	local jobId = game.JobId ~= "" and game.JobId or "studio"
	for attempt = 1, LOAD_RETRIES do
		local lockedByOther = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				old = old or {}
				local lock = old.lock
				if lock and lock.jobId ~= jobId and (os.time() - (lock.at or 0)) < LOCK_TIMEOUT then
					lockedByOther = true
					return nil -- abort: do not write
				end
				old.lock = { jobId = jobId, at = os.time() }
				old.data = old.data -- untouched
				return old
			end)
		end)
		if ok and not lockedByOther then
			local wrapped = result or {}
			return migrate(wrapped.data), true, nil
		elseif ok and lockedByOther then
			-- Another server is live with this profile. Wait a bit and retry; otherwise serve read-only.
			if attempt < LOAD_RETRIES then
				task.wait(3)
			else
				local okGet, snap = pcall(function()
					return store:GetAsync(key)
				end)
				local data = if okGet and snap then migrate(snap.data) else defaults()
				return data, false, "profile is open on another server"
			end
		else
			warn("[DataService] load failed for " .. player.Name .. ": " .. tostring(result))
			if attempt < LOAD_RETRIES then
				task.wait(2 ^ attempt)
			end
		end
	end
	return defaults(), false, "profile failed to load"
end

local function save(player: Player, releaseLock: boolean): boolean
	local profile = profiles[player]
	if not profile or not profile.saveable or not storeOk then
		return false
	end
	local key = keyFor(player)
	local jobId = game.JobId ~= "" and game.JobId or "studio"
	local snapshot = profile.data
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			old = old or {}
			local lock = old.lock
			if lock and lock.jobId ~= jobId and (os.time() - (lock.at or 0)) < LOCK_TIMEOUT then
				return nil -- we lost the lock; never overwrite the other server's writes
			end
			old.data = snapshot
			old.lock = if releaseLock then nil else { jobId = jobId, at = os.time() }
			old.savedAt = os.time()
			return old
		end)
	end)
	if not ok then
		warn("[DataService] save failed for " .. player.Name .. ": " .. tostring(err))
		return false
	end
	profile.dirty = false
	return true
end

function DataService.init(ctx)
	DataService.ctx = ctx
	tryStore()
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		DataService.onPlayerAdded(player)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			flush(player)
			save(player, true)
			profiles[player] = nil
			pending[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in pairs(profiles) do
				if DataService.hasPending(player) then
					flush(player)
				end
				if profile.dirty then
					save(player, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		-- Wait for in-flight op flushes (bounded), then snapshot everything with the lock released.
		local deadline = os.clock() + 20
		for player in pairs(profiles) do
			flush(player)
		end
		while os.clock() < deadline do
			local busy = false
			for player in pairs(profiles) do
				if flushing[player] then
					busy = true
				end
			end
			if not busy then
				break
			end
			task.wait(0.2)
		end
		for player in pairs(profiles) do
			save(player, true)
		end
	end)
end

function DataService.onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local data, saveable, reason = loadWithLock(player)
	if not player.Parent then
		return
	end
	profiles[player] = { data = data, saveable = saveable, reason = reason, loadedAt = os.time(), dirty = false }
	player:SetAttribute("ProfileLoaded", true)
	player:SetAttribute("ProfileSaveable", saveable)
	if not saveable then
		warn(string.format("[DataService] %s is read-only: %s", player.Name, tostring(reason)))
	end
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Blocks until the profile exists (or the player leaves). Used by services that need cash at join.
function DataService.waitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 15)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.markDirty(player: Player)
	local p = profiles[player]
	if p then
		p.dirty = true
	end
end

-- Apply a ProfileOps operation to the stored value (UpdateAsync, lock-checked) and to memory.
-- Returns true only when the op is durable (or the profile is memory-only by design).
local function storeOp(player: Player, op): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not profile.saveable or not storeOk then
		return false
	end
	local key = keyFor(player)
	local jobId = game.JobId ~= "" and game.JobId or "studio"
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			old = old or {}
			local lock = old.lock
			if lock and lock.jobId ~= jobId and (os.time() - (lock.at or 0)) < LOCK_TIMEOUT then
				return nil
			end
			local data = migrate(old.data)
			ProfileOps.apply(data, op, Config.Commerce.Catalog)
			old.data = data
			old.lock = { jobId = jobId, at = os.time() }
			old.savedAt = os.time()
			return old
		end)
	end)
	if not ok then
		warn("[DataService] op store failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

flush = function(player: Player)
	if flushing[player] then
		return
	end
	flushing[player] = true
	local queue = pending[player]
	while queue and #queue > 0 and player.Parent do
		if storeOp(player, queue[1]) then
			table.remove(queue, 1)
		else
			break
		end
	end
	flushing[player] = nil
end

-- Returns (applied, durable). `durable` is false while the op waits in the retry queue.
function DataService.applyOp(player: Player, op): (boolean, boolean)
	local profile = profiles[player]
	if not profile then
		return false, false
	end
	local _, changed = ProfileOps.apply(profile.data, op, Config.Commerce.Catalog)
	if not changed then
		return false, true
	end
	profile.dirty = true
	if not profile.saveable or not storeOk then
		return true, false
	end
	pending[player] = pending[player] or {}
	table.insert(pending[player], op)
	flush(player)
	return true, (pending[player] == nil or #pending[player] == 0)
end

function DataService.isLive(player: Player): boolean
	local profile = profiles[player]
	return storeOk and profile ~= nil and profile.saveable
end

function DataService.hasPending(player: Player): boolean
	return pending[player] ~= nil and #pending[player] > 0
end

return DataService
