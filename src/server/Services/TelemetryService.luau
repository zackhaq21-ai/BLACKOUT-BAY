--!nonstrict
-- Privacy-conscious internal instrumentation: named events with small field tables, kept in a bounded ring
-- buffer for the engine tests and printed only in Studio. No third-party dependency, no personal data beyond
-- the opaque user key already used everywhere else.
local RunService = game:GetService("RunService")

local TelemetryService = {}
TelemetryService.ctx = nil :: any

local RING = 200
local buffer = {}
local head = 0
local counts: { [string]: number } = {}

function TelemetryService.track(name: string, fields)
	if type(name) ~= "string" or #name > 48 then
		return
	end
	local entry = { t = workspace:GetServerTimeNow(), name = name, fields = if type(fields) == "table" then fields else {} }
	head = (head % RING) + 1
	buffer[head] = entry
	counts[name] = (counts[name] or 0) + 1
	if RunService:IsStudio() then
		local parts = {}
		for k, v in pairs(entry.fields) do
			table.insert(parts, tostring(k) .. "=" .. tostring(v))
		end
		table.sort(parts)
		print("[GLASSHOUSE telemetry] " .. name .. " " .. table.concat(parts, " "))
	end
end

function TelemetryService.counts()
	return table.clone(counts)
end

function TelemetryService.recent(limit: number?)
	local out = {}
	local n = math.min(limit or 50, RING)
	for i = 0, n - 1 do
		local idx = ((head - 1 - i) % RING) + 1
		local e = buffer[idx]
		if e then
			table.insert(out, e)
		end
	end
	return out
end

function TelemetryService.init(ctx)
	TelemetryService.ctx = ctx
end

function TelemetryService.start() end

return TelemetryService
