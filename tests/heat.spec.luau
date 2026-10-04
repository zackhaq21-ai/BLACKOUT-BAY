local Heat = require("../src/shared/Core/Heat")

return function(t)
	local cfg = { heatPerLevel = 100, maxHeat = 300, decayPerSecond = 10, unseenGrace = 5, recognitionSeconds = 30 }

	t.test("levels, clamp, listeners", function()
		local H = Heat.new(cfg)
		local changes = {}
		H:onLevelChange(function(_key, from, to, reason) table.insert(changes, { from, to, reason }) end)
		H:add("p", 120, "alarm", 0)
		t.eq(H:levelOf("p"), 1); t.eq(changes[1][3], "alarm")
		H:add("p", 1000, "ram", 0)
		t.eq(H:heatOf("p"), 300); t.eq(H:levelOf("p"), 3)
		t.eq(#H:wanted(), 1)
	end)

	t.test("decays only while unseen past the grace period", function()
		local H = Heat.new(cfg)
		H:add("p", 150, "alarm", 0)
		H:step(1, 1); t.eq(H:heatOf("p"), 150)
		H:step(1, 6); t.eq(H:heatOf("p"), 140)
		H:seen("p", 6); H:step(1, 7); t.eq(H:heatOf("p"), 140)
		H:clear("p", "arrested"); t.eq(H:levelOf("p"), 0)
	end)

	t.test("vehicle recognition expires", function()
		local H = Heat.new(cfg)
		H:recognizeVehicle("v", 0)
		t.truthy(H:isVehicleRecognized("v", 29)); t.falsy(H:isVehicleRecognized("v", 30))
		H:step(1, 31); t.eq(next(H.vehicles), nil)
	end)
end
