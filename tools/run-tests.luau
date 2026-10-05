--!nonstrict
-- Minimal test runner for pure Luau modules (run with the luau CLI, no Roblox required).
local SPECS = {
	"../tests/loot_ledger.spec",
	"../tests/split_ledger.spec",
	"../tests/mission_flow.spec",
	"../tests/security_state.spec",
	"../tests/rate_limiter.spec",
	"../tests/rare_car_cycle.spec",
	"../tests/bounty_record.spec",
	"../tests/world_event_rules.spec",
	"../tests/blackout_rules.spec",
	"../tests/convoy_rules.spec",
	"../tests/weather_rules.spec",
	"../tests/camera_feel.spec",
	"../tests/vehicle_feel.spec",
	"../tests/config_consistency.spec",
	"../tests/heat.spec",
	"../tests/map_blueprint.spec",
	"../tests/road_graph.spec",
	"../tests/stash_rules.spec",
	"../tests/hideout_record.spec",
	"../tests/profile_ops.spec",
}

local passed, failed = 0, 0
local failures = {}

local function makeT(specName)
	local t = {}
	function t.test(name, fn)
		local ok, err = pcall(fn)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, string.format("%s :: %s\n    %s", specName, name, tostring(err)))
		end
	end
	function t.eq(actual, expected, label)
		if actual ~= expected then
			error(string.format("%s expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
		end
	end
	function t.truthy(v, label)
		if not v then
			error((label or "value") .. " expected truthy", 2)
		end
	end
	function t.falsy(v, label)
		if v then
			error((label or "value") .. " expected falsy, got " .. tostring(v), 2)
		end
	end
	function t.near(actual, expected, eps, label)
		if math.abs(actual - expected) > (eps or 1e-6) then
			error(string.format("%s expected ~%s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
		end
	end
	return t
end

for _, path in ipairs(SPECS) do
	local spec = require(path)
	spec(makeT(path))
end

print(string.format("tests: %d passed, %d failed", passed, failed))
for _, f in ipairs(failures) do
	print("FAIL " .. f)
end
if failed > 0 then
	error("test failures", 0)
end
