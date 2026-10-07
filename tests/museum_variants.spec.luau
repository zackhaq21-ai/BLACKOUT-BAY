local V = require("../src/shared/Core/MuseumVariants")
local Config = require("../src/shared/Config")
local variants = Config.MuseumVariants

return function(t)
	t.test("every configured variant is valid and materially different", function()
		local seen = {}
		for _, v in ipairs(variants) do
			t.eq(V.validate(v), nil, v.id)
			local key = table.concat(v.hall, ",") .. "|" .. table.concat(v.vault, ",") .. "|" .. v.posture.lockdownDelay .. "|" .. tostring(v.entry) .. "|" .. tostring(v.infrastructure)
			t.falsy(seen[key], v.id .. " duplicates another variant")
			seen[key] = true
		end
		t.truthy(#variants >= 4)
		t.truthy(V.validate({ id = "x", name = "x", weight = 1, hall = { "Trinket" }, vault = {}, posture = {} }))
		t.truthy(V.validate({ id = "x", name = "x", weight = 1, hall = { "Core", "Trinket", "Trinket", "Trinket", "Trinket", "Trinket" }, vault = { "Jewel", "Jewel" }, posture = { lockdownDelay = 25, guardSpeedBonus = 0, cameraSweepSeconds = 6 } }))
		t.truthy(V.validate({ id = "x", name = "x", weight = 1, hall = { "Trinket", "Trinket", "Trinket", "Trinket", "Trinket", "Trinket" }, vault = { "Jewel", "Jewel" }, posture = { lockdownDelay = 1, guardSpeedBonus = 0, cameraSweepSeconds = 6 } }))
	end)
	t.test("eligibility by weather and picking never repeats the last variant", function()
		local clear = V.eligible(variants, "Clear")
		for _, v in ipairs(clear) do t.falsy(v.id == "stormwatch", "storm variant on a clear night") end
		local storm = V.eligible(variants, "Storm")
		local hasStorm = false
		for _, v in ipairs(storm) do if v.id == "stormwatch" then hasStorm = true end end
		t.truthy(hasStorm)
		for r = 0, 0.99, 0.05 do
			local picked = V.pick(variants, "Clear", "quiet", function() return r end)
			t.truthy(picked and picked.id ~= "quiet", "repeat of last variant at roll " .. r)
		end
		local only = { variants[1] }
		t.eq(V.pick(only, "Clear", "quiet", function() return 0.5 end).id, "quiet", "single option may repeat")
		t.eq(V.pick({}, "Clear", nil, function() return 0 end), nil)
		t.eq(V.pick(variants, "Clear", nil, function() return 0 / 0 end) ~= nil, true, "NaN roll still picks")
	end)
	t.test("stock value differs between variants", function()
		local values = {}
		for k, v in pairs(Config.Economy.Loot) do values[k] = v.value end
		local quiet = V.stockValue(variants[1], values)
		local gala = V.stockValue(variants[2], values)
		t.truthy(gala > quiet, "gala is richer")
		t.truthy(quiet > 0)
	end)
end
