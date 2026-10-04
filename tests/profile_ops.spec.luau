local ProfileOps = require("../src/shared/Core/ProfileOps")

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
