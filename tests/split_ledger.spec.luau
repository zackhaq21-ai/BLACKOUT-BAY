local Split = require("../src/shared/Core/SplitLedger")

return function(t)
	t.test("equal split sums to 100 with remainder spread", function()
		local s = Split.equal({ "a", "b", "c" })
		t.eq(s.a + s.b + s.c, 100); t.eq(s.a, 34); t.eq(s.c, 33)
		t.eq(Split.equal({ "solo" }).solo, 100)
	end)

	t.test("validate rejects bad shares", function()
		t.falsy((Split.validate({ a = 60, b = 50 }, { "a", "b" }, 0)))
		t.falsy((Split.validate({ a = 100, b = 0, c = 5 }, { "a", "b" }, 0)), "non-member")
		t.falsy((Split.validate({ a = 100.5, b = -0.5 }, { "a", "b" }, 0)))
		t.truthy((Split.validate({ a = 70, b = 30 }, { "a", "b" }, 0)))
	end)

	t.test("distribute pays by share, remainder to deliverer", function()
		local out = Split.distribute(1001, { a = 50, b = 50 }, { "a", "b" }, "b")
		t.eq(out.a, 500); t.eq(out.b, 501)
	end)

	t.test("members who left forfeit their share to those present", function()
		local out = Split.distribute(3000, { a = 50, b = 25, c = 25 }, { "a", "b" }, "a")
		t.eq(out.a, 2000); t.eq(out.b, 1000); t.falsy(out.c)
	end)

	t.test("deliverer keeps all when everyone with a share has gone", function()
		local out = Split.distribute(900, { a = 100 }, { "b" }, "b")
		t.eq(out.b, 900)
		t.eq(next(Split.distribute(0, { a = 100 }, { "a" }, "a")), nil)
	end)
end
