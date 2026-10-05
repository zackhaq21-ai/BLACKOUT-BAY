local ProfileOps = require("../src/shared/Core/ProfileOps")
local Standing = require("../src/shared/Core/Standing")
local Onboarding = require("../src/shared/Core/Onboarding")
local Config = require("../src/shared/Config")

return function(t)
	local catalog = {
		{ Id = "mint", Name = "Mint courier", Kind = "Suit", EarnedXP = 0, PassId = 0, ProductId = 0, Color = { 1, 2, 3 } },
		{ Id = "amber", Name = "Amber operator", Kind = "Suit", EarnedXP = 200, PassId = 0, ProductId = 0, Color = { 1, 2, 3 } },
		{ Id = "prism", Name = "Prism suit", Kind = "Suit", EarnedXP = false, PassId = 0, ProductId = 0, Color = { 1, 2, 3 } },
	}
	local function fresh()
		return { xp = 0, wins = 0, stats = { jobs = 0 }, entitlements = {}, receipts = {}, runsSeen = {}, equipped = "mint", decor = "" }
	end

	t.test("run credited once per id; earned unlock at threshold", function()
		local p = fresh()
		local _, c1 = ProfileOps.apply(p, { kind = "Run", id = "job1", xp = 150, won = true }, catalog)
		local _, c2 = ProfileOps.apply(p, { kind = "Run", id = "job1", xp = 150, won = true }, catalog)
		t.truthy(c1); t.falsy(c2); t.eq(p.xp, 150); t.eq(p.wins, 1); t.eq(p.stats.jobs, 1)
		t.truthy(p.entitlements.mint); t.falsy(p.entitlements.amber)
		ProfileOps.apply(p, { kind = "Run", id = "job2", xp = 60, won = false }, catalog)
		t.truthy(p.entitlements.amber); t.eq(p.wins, 1)
	end)

	t.test("standing awards: once per id, diminished per source per day, day rollover, prune, onboarding monotonic", function()
		ProfileOps.configure(Standing, Onboarding, Config.Progression)
		local p = fresh()
		local _, c1 = ProfileOps.apply(p, { kind = "Standing", id = "raid:1", source = "raid", xp = 80, day = "2026-10-05" }, catalog)
		local _, c2 = ProfileOps.apply(p, { kind = "Standing", id = "raid:1", source = "raid", xp = 80, day = "2026-10-05" }, catalog)
		t.truthy(c1); t.falsy(c2); t.eq(p.xp, 80, "same id never pays twice")
		ProfileOps.apply(p, { kind = "Standing", id = "raid:2", source = "raid", xp = 80, day = "2026-10-05" }, catalog)
		ProfileOps.apply(p, { kind = "Standing", id = "raid:3", source = "raid", xp = 80, day = "2026-10-05" }, catalog)
		t.eq(p.xp, 200, "third raid of the day is halved")
		ProfileOps.apply(p, { kind = "Standing", id = "raid:4", source = "raid", xp = 80, day = "2026-10-06" }, catalog)
		t.eq(p.xp, 280, "new day resets the counter")
		t.eq(p.standingDay.day, "2026-10-06")
		ProfileOps.apply(p, { kind = "Standing", id = "bad", source = "raid", xp = 0 / 0, day = "2026-10-06" }, catalog)
		t.eq(p.xp, 280, "NaN award ignored")
		-- jobs diminish after the daily full count, with the crew bonus applied to the base
		local q = fresh()
		for i = 1, 7 do
			ProfileOps.apply(q, { kind = "Run", id = "job" .. i, xp = 100, won = true, source = "job", day = "2026-10-05", members = 1 }, catalog)
		end
		t.eq(q.xp, 650, "six full jobs then a halved seventh")
		t.eq(q.stats.jobs, 7)
		local r = fresh()
		ProfileOps.apply(r, { kind = "Run", id = "j", xp = 100, won = true, source = "job", day = "2026-10-05", members = 3 }, catalog)
		t.eq(r.xp, 120, "crew bonus")
		-- onboarding op only moves forward and validates
		local o = fresh()
		local _, oc = ProfileOps.apply(o, { kind = "Onboarding", step = 3 }, catalog)
		t.truthy(oc); t.eq(o.onboarding.step, 3)
		local _, oc2 = ProfileOps.apply(o, { kind = "Onboarding", step = 2 }, catalog)
		t.falsy(oc2)
		ProfileOps.apply(o, { kind = "Onboarding", step = 99 }, catalog)
		t.eq(o.onboarding.step, 6); t.truthy(o.onboarding.done)
		-- prune: entries older than the current day go once the set grows past the cap
		local big = fresh()
		for i = 1, Config.Progression.MaxAwardsSeen + 1 do
			ProfileOps.apply(big, { kind = "Standing", id = "x" .. i, source = "recovery", xp = 1, day = "2026-10-01" }, catalog)
		end
		ProfileOps.apply(big, { kind = "Standing", id = "today", source = "recovery", xp = 1, day = "2026-10-02" }, catalog)
		local n = 0
		for _ in pairs(big.awardsSeen) do n += 1 end
		t.truthy(n <= 2, "old award ids pruned: " .. n)
		ProfileOps.configure(nil, nil, nil)
		local plain = fresh()
		ProfileOps.apply(plain, { kind = "Standing", id = "a", source = "raid", xp = 80, day = "d" }, catalog)
		t.eq(plain.xp, 80, "without deps awards are credited plain")
	end)

	t.test("receipt replay grants exactly once; pass is idempotent", function()
		local p = fresh()
		local _, c1 = ProfileOps.apply(p, { kind = "Receipt", receipt = "r1", item = "prism" }, catalog)
		local _, c2 = ProfileOps.apply(p, { kind = "Receipt", receipt = "r1", item = "prism" }, catalog)
		t.truthy(c1); t.falsy(c2); t.truthy(p.entitlements.prism); t.truthy(p.receipts.r1)
		local _, c3 = ProfileOps.apply(p, { kind = "Pass", item = "prism" }, catalog)
		t.falsy(c3)
	end)

	t.test("equip requires ownership and never touches anything else", function()
		local p = fresh()
		local _, c = ProfileOps.apply(p, { kind = "Equip", item = "prism" }, catalog)
		t.falsy(c); t.eq(p.equipped, "mint")
		ProfileOps.apply(p, { kind = "Pass", item = "prism" }, catalog)
		local _, c2 = ProfileOps.apply(p, { kind = "Equip", item = "prism" }, catalog)
		t.truthy(c2); t.eq(p.equipped, "prism"); t.eq(p.xp, 0)
		t.falsy((ProfileOps.apply(p, { kind = "Bogus" }, catalog))[2])
	end)
end
