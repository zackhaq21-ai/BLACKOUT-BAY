local C = require("../src/shared/Core/ContactRules")
local S = require("../src/shared/Core/Standing")
local Config = require("../src/shared/Config")
local contacts = Config.Contacts

local function ctx(xp, over)
	local base = {
		xp = xp,
		unlocked = function(key) return S.unlocked(Config.Progression, xp, key) end,
		variant = { name = "Gala Stock", hint = "Jewels on the floor." },
		jobActive = false,
		weather = "Clear",
		convoy = { active = false, nextInSeconds = 400 },
		grid = { down = false, cooldownSeconds = 0, durationSeconds = 75 },
		richestName = "Mara",
		rankName = S.rankFor(Config.Progression, xp).name,
		firstVisit = false,
	}
	for k, v in pairs(over or {}) do base[k] = v end
	return base
end

return function(t)
	t.test("three original contacts with places inside the island and valid unlock keys", function()
		t.eq(#contacts, 3)
		for _, c in ipairs(contacts) do
			t.truthy(#c.name > 3 and #c.role > 2 and #c.personality > 10, c.id)
			if c.requires then t.truthy(Config.Progression.Unlocks[c.requires], c.id .. " unknown unlock " .. c.requires) end
		end
		t.truthy(C.find(contacts, "priya")); t.falsy(C.find(contacts, "nobody"))
	end)
	t.test("first visits introduce; locked intel refuses with the rank; unlocked intel is partial", function()
		local teo = C.find(contacts, "teo")
		t.truthy(C.line(teo, ctx(0, { firstVisit = true })).text:find("Standing"))
		t.truthy(C.line(teo, ctx(0)).text:find("Drifter"))
		local line = C.line(teo, ctx(600)).text
		t.truthy(line:find("later tonight"), line)
		t.falsy(line:find("400"), "no exact timer leaks")
		t.truthy(C.line(teo, ctx(600, { weather = "Storm" })).text:find("Seawall"))
		t.truthy(C.line(teo, ctx(600, { convoy = { active = true, phase = "Checkpoint", landmark = "Lantern Cross" } })).text:find("Lantern Cross"))
	end)
	t.test("grid contact only reveals cooldown state and duration from config", function()
		local priya = C.find(contacts, "priya")
		t.truthy(C.line(priya, ctx(0)).text:find("Runners"))
		t.truthy(C.line(priya, ctx(200)).text:find("75 seconds"))
		t.truthy(C.line(priya, ctx(200, { grid = { down = false, cooldownSeconds = 200, durationSeconds = 75 } })).text:find("4 minutes"))
		t.truthy(C.line(priya, ctx(200, { grid = { down = true, cooldownSeconds = 0, durationSeconds = 75, lastCutBy = "Mara" } })).text:find("Mara"))
	end)
	t.test("dockmaster briefs the live variant and the richest stash", function()
		local ines = C.find(contacts, "ines")
		local line = C.line(ines, ctx(0)).text
		t.truthy(line:find("Gala Stock") and line:find("Mara"))
		t.truthy(C.line(ines, ctx(0, { variant = false })).text:find("between stocks"))
		t.truthy(C.line(ines, ctx(0, { jobActive = true })).text:find("already on it"))
	end)
end
