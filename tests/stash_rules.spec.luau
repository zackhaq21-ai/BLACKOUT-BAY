local StashRules = require("../src/shared/Core/StashRules")

return function(t)
	local cfg = {
		FullExposure = true, BankFeeFraction = 0.1, BundleValue = 2500,
		Tiers = { [1] = { cost = 1500, unlock = "Lock", desc = "" }, [2] = { cost = 3000, unlock = "Alarm", desc = "" }, [3] = { cost = 5000, unlock = "Shield", desc = "" } },
		SafeCrackSeconds = { [0] = 12, [1] = 25, [2] = 25, [3] = 25 }, CrackAssistFactor = 0.55, BreakerSeconds = { [3] = 18 },
	}
	t.test("a raid exposes the full earned stash: no floor, no fraction, no cap", function()
		t.eq(StashRules.exposed(cfg, 0), 0); t.eq(StashRules.exposed(cfg, 1000), 1000)
		t.eq(StashRules.exposed(cfg, 11000), 11000); t.eq(StashRules.exposed(cfg, 1000000), 1000000)
		t.eq(StashRules.exposed(cfg, 12.9), 12)
	end)
	t.test("bundles never exceed the bundle value and sum to the amount", function()
		local b = StashRules.bundles(cfg, 6100)
		t.eq(#b, 3); t.eq(b[1] + b[2] + b[3], 6100); t.eq(b[3], 1100)
		t.eq(#StashRules.bundles(cfg, 0), 0)
	end)
	t.test("tiers, defences, costs, crack times", function()
		t.eq(StashRules.maxTier(cfg), 3); t.eq(StashRules.upgradeCost(cfg, 0), 1500); t.eq(StashRules.upgradeCost(cfg, 3), nil)
		local d = StashRules.defences(cfg, 2); t.truthy(d.Lock); t.truthy(d.Alarm); t.falsy(d.Shield)
		t.eq(StashRules.safeCrackSeconds(cfg, 0, 1), 12); t.eq(StashRules.safeCrackSeconds(cfg, 3, 2), 14)
		t.eq(StashRules.breakerSeconds(cfg, 3), 18); t.eq(StashRules.breakerSeconds(cfg, 1), nil)
	end)
	t.test("banking fee", function()
		local w, f = StashRules.bank(cfg, 1000); t.eq(w, 900); t.eq(f, 100)
	end)
end
