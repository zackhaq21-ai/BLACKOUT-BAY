--!nonstrict
-- Small server-authoritative world-event framework. One instance per event id, bounded duration, cooldown,
-- handlers registered by the owning service, state replicated to every client (and to late joiners).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local WorldEventRules = require(ReplicatedStorage.Shared.Core.WorldEventRules)

local WorldEventService = {}
WorldEventService.ctx = nil :: any

local rules
local handlers: { [string]: any } = {}
local labels: { [string]: string } = {}
local heartbeat: thread?

local function now(): number
	return workspace:GetServerTimeNow()
end

local function payload(id: string, reason: string?)
	local a = rules:get(id)
	return {
		id = id,
		label = labels[id] or id,
		active = a ~= nil,
		endsAt = a and a.endsAt or nil,
		secondsLeft = if a then math.max(0, a.endsAt - now()) else 0,
		startedBy = a and a.startedBy or nil,
		reason = reason,
	}
end

local function broadcast(id: string, reason: string?)
	Net.event("WorldEvent"):FireAllClients(payload(id, reason))
end

-- def: {id, duration, cooldown}; spec: {label, onStart(active, player?), onEnd(active, reason)}
function WorldEventService.register(def, spec)
	rules.defs[def.id] = { id = def.id, duration = def.duration, cooldown = def.cooldown }
	handlers[def.id] = spec
	labels[def.id] = spec.label or def.id
end

function WorldEventService.canStart(id: string): (boolean, string?)
	return rules:canStart(id, now())
end

function WorldEventService.isActive(id: string): boolean
	return rules:get(id) ~= nil
end

function WorldEventService.secondsLeft(id: string): number
	return rules:secondsLeft(id, now())
end

function WorldEventService.trigger(id: string, player: Player?, data)
	local active, err = rules:start(id, now(), player and player.Name or nil, data)
	if not active then
		return nil, err
	end
	local spec = handlers[id]
	if spec and spec.onStart then
		local ok, e = pcall(spec.onStart, active, player)
		if not ok then
			warn("[WorldEvent] onStart " .. id .. " failed: " .. tostring(e))
		end
	end
	broadcast(id, "started")
	return active, nil
end

local function finish(id: string, active, reason: string)
	local spec = handlers[id]
	if spec and spec.onEnd then
		local ok, e = pcall(spec.onEnd, active, reason)
		if not ok then
			warn("[WorldEvent] onEnd " .. id .. " failed: " .. tostring(e))
		end
	end
	broadcast(id, reason)
end

function WorldEventService.cancel(id: string, reason: string)
	local active = rules:stop(id, now())
	if not active then
		return nil
	end
	finish(id, active, reason)
	return active
end

-- Current state of every registered event (bootstrap / reconnect).
function WorldEventService.snapshot()
	local out = {}
	for id in pairs(rules.defs) do
		out[id] = payload(id, nil)
	end
	return out
end

function WorldEventService.init(ctx)
	WorldEventService.ctx = ctx
	rules = WorldEventRules.new({})
end

function WorldEventService.start()
	heartbeat = task.spawn(function()
		while true do
			task.wait(0.5)
			for _, active in ipairs(rules:step(now())) do
				finish(active.id, active, "expired")
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		for id in pairs(rules.defs) do
			if rules:get(id) then
				Net.event("WorldEvent"):FireClient(player, payload(id, nil))
			end
		end
	end)
	game:BindToClose(function()
		if heartbeat then
			task.cancel(heartbeat)
			heartbeat = nil
		end
	end)
end

return WorldEventService
