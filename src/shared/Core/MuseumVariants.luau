--!strict
-- Curated museum variation (pure). The server picks one variant per restock from the eligible list, never the
-- same as the last, weighted. Every variant is validated so a bad config cannot stock an impossible museum.

export type Variant = {
	id: string, name: string, weight: number, hint: string,
	hall: { string }, vault: { string },
	posture: { lockdownDelay: number, guardSpeedBonus: number, cameraSweepSeconds: number },
	entry: string?, infrastructure: string?, weather: { string }?,
}

local MuseumVariants = {}

local KINDS = { Trinket = true, Relic = true, Jewel = true }

function MuseumVariants.validate(v: any): string?
	if type(v) ~= "table" or type(v.id) ~= "string" or type(v.name) ~= "string" then
		return "missing id/name"
	end
	if type(v.hall) ~= "table" or #v.hall ~= 6 then
		return v.id .. ": hall must list six case kinds"
	end
	for _, k in ipairs(v.hall) do
		if not KINDS[k] then
			return v.id .. ": unknown hall kind " .. tostring(k)
		end
	end
	if type(v.vault) ~= "table" or #v.vault ~= 2 then
		return v.id .. ": vault must list two case kinds"
	end
	for _, k in ipairs(v.vault) do
		if not KINDS[k] then
			return v.id .. ": unknown vault kind " .. tostring(k)
		end
	end
	local p = v.posture
	if type(p) ~= "table" or type(p.lockdownDelay) ~= "number" or p.lockdownDelay < 5 or p.lockdownDelay > 120 then
		return v.id .. ": lockdownDelay out of range"
	end
	if type(p.guardSpeedBonus) ~= "number" or p.guardSpeedBonus < 0 or p.guardSpeedBonus > 6 then
		return v.id .. ": guardSpeedBonus out of range"
	end
	if type(p.cameraSweepSeconds) ~= "number" or p.cameraSweepSeconds < 2 or p.cameraSweepSeconds > 20 then
		return v.id .. ": cameraSweepSeconds out of range"
	end
	if v.entry ~= nil and v.entry ~= "service" then
		return v.id .. ": unknown entry " .. tostring(v.entry)
	end
	if v.infrastructure ~= nil and v.infrastructure ~= "powerCut" then
		return v.id .. ": unknown infrastructure " .. tostring(v.infrastructure)
	end
	if type(v.weight) ~= "number" or v.weight <= 0 then
		return v.id .. ": weight must be positive"
	end
	return nil
end

function MuseumVariants.eligible(variants: { Variant }, weather: string): { Variant }
	local out = {}
	for _, v in ipairs(variants) do
		if MuseumVariants.validate(v) == nil then
			if v.weather == nil or table.find(v.weather, weather) then
				table.insert(out, v)
			end
		end
	end
	return out
end

-- Weighted pick excluding the last id when another option exists. `roll` returns [0, 1).
function MuseumVariants.pick(variants: { Variant }, weather: string, lastId: string?, roll: () -> number): Variant?
	local pool = MuseumVariants.eligible(variants, weather)
	if #pool == 0 then
		return nil
	end
	local candidates = {}
	for _, v in ipairs(pool) do
		if v.id ~= lastId then
			table.insert(candidates, v)
		end
	end
	if #candidates == 0 then
		candidates = pool
	end
	local total = 0
	for _, v in ipairs(candidates) do
		total += v.weight
	end
	local r = math.clamp(roll(), 0, 0.999999) * total
	for _, v in ipairs(candidates) do
		r -= v.weight
		if r < 0 then
			return v
		end
	end
	return candidates[#candidates]
end

-- Expected hall value for the brief (sum of case values from the economy table)
function MuseumVariants.stockValue(v: Variant, lootValues: { [string]: number }): number
	local total = 0
	for _, k in ipairs(v.hall) do
		total += lootValues[k] or 0
	end
	for _, k in ipairs(v.vault) do
		total += lootValues[k] or 0
	end
	return total
end

return MuseumVariants
