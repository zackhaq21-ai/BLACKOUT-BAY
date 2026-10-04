--!nonstrict
-- Dumps MapBlueprint as JSON for tools/map_preview.py (run with the luau CLI).
local B = require("../src/shared/MapBlueprint")

local function enc(v, indent)
	local tv = type(v)
	if tv == "number" then return tostring(v) end
	if tv == "boolean" then return tostring(v) end
	if tv == "string" then return string.format("%q", v) end
	if tv == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in ipairs(v) do table.insert(parts, enc(x, indent)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do table.insert(keys, k) end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do table.insert(parts, string.format("%q:%s", k, enc(v[k], indent))) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local out = {}
for _, k in ipairs({ "Island", "Roads", "Canal", "Museum", "Plaza", "ParkingDeck", "PoliceStation", "PoliceLot", "Lighthouse", "LanternCross", "Hideouts", "Buildings", "StreetCars", "Bollards", "PolicePatrol", "Barricade", "Landmarks" }) do
	out[k] = B[k]
end
print(enc(out))
