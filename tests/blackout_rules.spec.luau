local R = require("../src/shared/Core/BlackoutRules")
local cfg = { RequiresActiveJob = true, GuardVisionScale = 0.55, PoliceVisionScale = 0.6, DurationSeconds = 75, CooldownSeconds = 300 }
local function actor(over)
	local a = { alive = true, jailed = false, seated = false, jobActive = true }
	for k, v in pairs(over or {}) do a[k] = v end
	return a
end

return function(t)
	t.test("sabotage eligibility", function()
		t.eq(R.sabotageRefusal(cfg, actor()), nil)
		t.eq(R.sabotageRefusal(cfg, actor({ alive = false })), "not alive")
		t.eq(R.sabotageRefusal(cfg, actor({ jailed = true })), "jailed")
		t.eq(R.sabotageRefusal(cfg, actor({ seated = true })), "on foot only")
		t.eq(R.sabotageRefusal(cfg, actor({ jobActive = false })), "your crew needs an active job")
		local relaxed = table.clone(cfg); relaxed.RequiresActiveJob = false
		t.eq(R.sabotageRefusal(relaxed, actor({ jobActive = false })), nil)
	end)
	t.test("reset is open to anyone on foot", function()
		t.eq(R.resetRefusal(actor({ jobActive = false })), nil)
		t.eq(R.resetRefusal(actor({ jailed = true })), "jailed")
		t.eq(R.resetRefusal(actor({ seated = true })), "on foot only")
	end)
	t.test("vision scale is clamped and only applies while the grid is down", function()
		t.eq(R.visionScale(cfg, "guard", false), 1)
		t.eq(R.visionScale(cfg, "guard", true), 0.55)
		t.eq(R.visionScale(cfg, "cop", true), 0.6)
		local bad = table.clone(cfg); bad.GuardVisionScale = 0; bad.PoliceVisionScale = 0 / 0
		t.eq(R.visionScale(bad, "guard", true), 0.25)
		t.eq(R.visionScale(bad, "cop", true), 1)
	end)
	t.test("definition bounds duration and cooldown", function()
		local d = R.definition(cfg); t.eq(d.duration, 75); t.eq(d.cooldown, 300); t.eq(d.id, "blackout")
		local silly = R.definition({ RequiresActiveJob = true, GuardVisionScale = 1, PoliceVisionScale = 1, DurationSeconds = 9999, CooldownSeconds = 1 })
		t.eq(silly.duration, 180); t.eq(silly.cooldown, 180)
	end)
end
