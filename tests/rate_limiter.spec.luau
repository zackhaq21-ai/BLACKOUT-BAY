local RateLimiter = require("../src/shared/Core/RateLimiter")

return function(t)
	t.test("burst then refill", function()
		local R = RateLimiter.new(2, 3)
		t.truthy(R:allow("p", 0)); t.truthy(R:allow("p", 0)); t.truthy(R:allow("p", 0))
		t.falsy(R:allow("p", 0))
		t.truthy(R:allow("p", 0.5), "one token refilled after 0.5s at 2/s")
		t.falsy(R:allow("p", 0.5))
		t.truthy(R:allow("q", 0), "independent keys")
		R:forget("p"); t.truthy(R:allow("p", 0.5))
	end)
end
