--!nonstrict
-- Per-crew evidence log. Betrayal, theft, arrests and payouts are explainable from these lines.
-- Also keeps a server-wide economy ledger in memory for diagnosing duplication or inflation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local EventLogService = { ctx = nil :: any }
EventLogService.__index = EventLogService

local MAX_CREW_LINES = 40
local MAX_LEDGER = 500

function EventLogService.init(ctx)
	EventLogService.ctx = ctx
	EventLogService.crewLogs = {} -- crewId -> { {t, text} }
	EventLogService.ledger = {} -- economy entries
end

function EventLogService.start() end

local function push(list, entry, max)
	table.insert(list, entry)
	if #list > max then
		table.remove(list, 1)
	end
end

function EventLogService.crew(crewId: string, text: string, kind: string?)
	local list = EventLogService.crewLogs[crewId]
	if not list then
		list = {}
		EventLogService.crewLogs[crewId] = list
	end
	push(list, { t = os.time(), text = text, kind = kind or "info" }, MAX_CREW_LINES)
	local crewService = EventLogService.ctx.services.Crew
	if crewService then
		for _, p in ipairs(crewService.playersOf(crewId)) do
			Net.event("EventLog"):FireClient(p, { entries = list })
		end
	end
end

function EventLogService.sendTo(player: Player, crewId: string)
	Net.event("EventLog"):FireClient(player, { entries = EventLogService.crewLogs[crewId] or {} })
end

function EventLogService.money(userKey: string, delta: number, reason: string, balance: number)
	push(EventLogService.ledger, { t = os.time(), user = userKey, delta = delta, reason = reason, balance = balance }, MAX_LEDGER)
end

function EventLogService.dump(): { any }
	return EventLogService.ledger
end

return EventLogService
