--!nonstrict
-- Server-verified accomplishments: evaluate pure rules on server-known facts, grant exactly once per player
-- through the Accomplish profile op (own Standing, no diminishing), note the crew milestone on the ledger.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Accomplishments = require(ReplicatedStorage.Shared.Core.Accomplishments)
local Standing = require(ReplicatedStorage.Shared.Core.Standing)
local Comms = require(script.Parent.Comms)

local AccomplishmentService = {}
AccomplishmentService.ctx = nil :: any

local DEFS = Config.Accomplishments

function AccomplishmentService.grant(player: Player, id: string): boolean
	local S = AccomplishmentService.ctx.services
	local def = Accomplishments.find(DEFS, id)
	if not def or not player.Parent then
		return false
	end
	local before = S.Progression.xp(player)
	local rankBefore = Standing.rankFor(Config.Progression, before)
	local applied = S.Data.applyOp(player, { kind = "Accomplish", id = id, xp = def.standing, day = Standing.dayKey(os.time()) })
	if not applied then
		return false
	end
	Comms.toast(player, string.format("Accomplishment: %s. %s (+%d Standing)", def.name, def.blurb, def.standing), "good")
	Comms.cue(player, "Payout")
	S.Progression.announce(player, S.Progression.xp(player) - before, rankBefore)
	S.Cosmetics.push(player)
	local crew = S.Crew.crewOf(player)
	if crew then
		S.Crew.note(crew.id, "accomplishment", def.standing, Comms.name(player) .. " earned " .. def.name, id)
	end
	S.Telemetry.track("accomplishment", { id = id })
	return true
end

-- Evaluate an event for a set of players (each gets any accomplishment they have not got yet).
function AccomplishmentService.check(event: string, ctx, players: { Player })
	local ids = Accomplishments.evaluate(event, ctx)
	if #ids == 0 then
		return
	end
	for _, p in ipairs(players) do
		for _, id in ipairs(ids) do
			AccomplishmentService.grant(p, id)
		end
	end
end

-- Museum entries live on the profile; evaluate Three Doors after each new entry
function AccomplishmentService.noteEntry(player: Player, entry: string)
	local S = AccomplishmentService.ctx.services
	local applied = S.Data.applyOp(player, { kind = "Entry", item = entry })
	if not applied then
		return
	end
	local profile = S.Data.get(player)
	if profile then
		AccomplishmentService.check("entries", profile.data.entries, { player })
	end
end

function AccomplishmentService.list(player: Player)
	local profile = AccomplishmentService.ctx.services.Data.get(player)
	local out = {}
	for _, d in ipairs(DEFS) do
		table.insert(out, { id = d.id, name = d.name, blurb = d.blurb, standing = d.standing, earned = profile and profile.data.accomplishments and profile.data.accomplishments[d.id] ~= nil })
	end
	return out
end

function AccomplishmentService.init(ctx)
	AccomplishmentService.ctx = ctx
end

function AccomplishmentService.start() end

return AccomplishmentService
