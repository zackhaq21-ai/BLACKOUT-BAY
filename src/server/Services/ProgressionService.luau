--!nonstrict
-- Standing (durable XP) awards, ranks and option unlocks. Every award is a merge-safe profile op credited once
-- per id with per-source daily diminishing applied against the STORED counters, so two servers, a retry or a
-- reconnect cannot double-credit. Gating is checked here, server-side, where the action happens.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Standing = require(ReplicatedStorage.Shared.Core.Standing)
local Comms = require(script.Parent.Comms)

local ProgressionService = {}
ProgressionService.ctx = nil :: any

local PC = Config.Progression

local function xpOf(player: Player): number
	local profile = ProgressionService.ctx.services.Data.get(player)
	return profile and profile.data.xp or 0
end

function ProgressionService.xp(player: Player): number
	return xpOf(player)
end

-- Snapshot for ProfileState / tests
function ProgressionService.rankInfo(player: Player)
	local xp = xpOf(player)
	local rank = Standing.rankFor(PC, xp)
	local nextRank = Standing.nextRank(PC, xp)
	local unlocked = {}
	for key in pairs(PC.Unlocks) do
		unlocked[key] = Standing.unlocked(PC, xp, key)
	end
	return {
		xp = xp,
		rank = rank.id,
		rankName = rank.name,
		nextRank = nextRank and nextRank.name or nil,
		nextXp = nextRank and nextRank.xp or nil,
		nextUnlocks = nextRank and Standing.unlocksAt(PC, nextRank.id) or {},
		unlocked = unlocked,
		unlockLabels = PC.UnlockLabels,
	}
end

-- Gate: nil when allowed, else the reason (also toasted to the player).
function ProgressionService.requires(player: Player, key: string): string?
	local why = Standing.lockReason(PC, xpOf(player), key)
	if why then
		Comms.toast(player, why .. ".", "warn")
		ProgressionService.ctx.services.Telemetry.track("unlock_blocked", { key = key, rank = Standing.rankFor(PC, xpOf(player)).id })
	end
	return why
end

-- Award Standing from a server-side source. `uniqueKey` dedupes the award for life (raid id, crate id...).
-- `members` is the number of present crew members for the cooperation bonus.
function ProgressionService.award(player: Player, source: string, uniqueKey: string, members: number?)
	local S = ProgressionService.ctx.services
	local base = Standing.baseAward(PC, source)
	if base <= 0 or not player.Parent then
		return
	end
	local before = xpOf(player)
	local rankBefore = Standing.rankFor(PC, before)
	local applied = S.Data.applyOp(player, { kind = "Standing", id = source .. ":" .. uniqueKey, source = source, xp = base, day = Standing.dayKey(os.time()), members = members or 1 })
	if not applied then
		return
	end
	local after = xpOf(player)
	local gained = after - before
	S.Telemetry.track("standing_award", { source = source, xp = gained, rank = Standing.rankFor(PC, after).id })
	ProgressionService.announce(player, gained, rankBefore)
	S.Cosmetics.push(player)
end

-- Shared notice for any Standing change (jobs call this after their own Run op)
function ProgressionService.announce(player: Player, gained: number, rankBefore)
	if gained <= 0 then
		return
	end
	local after = xpOf(player)
	local rank = Standing.rankFor(PC, after)
	if rankBefore and rank.id ~= rankBefore.id then
		local keys = Standing.unlocksAt(PC, rank.id)
		local labels = {}
		for _, k in ipairs(keys) do
			table.insert(labels, PC.UnlockLabels[k] or k)
		end
		Comms.toast(player, string.format("Standing: %s. %s", rank.name, if #labels > 0 then "Unlocked: " .. table.concat(labels, ", ") .. "." else "The bay is starting to know your name."), "good")
		Comms.cue(player, "Payout")
	else
		Comms.toast(player, string.format("+%d Standing (%s)", gained, rank.name), "info")
	end
end

function ProgressionService.init(ctx)
	ProgressionService.ctx = ctx
end

function ProgressionService.start()
	local _ = Players
end

return ProgressionService
