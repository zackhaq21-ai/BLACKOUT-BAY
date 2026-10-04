local SecurityState = require("../src/shared/Core/SecurityState")

return function(t)
	local cfg = { fillPerSecond = 0.5, sneakMultiplier = 0.5, decayPerSecond = 0.25, suspiciousThreshold = 0.5, alertThreshold = 1, lockdownDelay = 10, calmSeconds = 30 }

	t.test("exposure escalates quiet -> suspicious -> alert with a reason", function()
		local S = SecurityState.new(cfg)
		local changes = {}
		S:onChange(function(level, reason) table.insert(changes, { level, reason }) end)
		S:report("g1", "Gallery Guard", "alice", 1, false, 0)
		t.eq(S.level, 1); t.eq(changes[1][2], "Gallery Guard noticed something")
		S:report("g1", "Gallery Guard", "alice", 1, false, 1)
		t.eq(S.level, 2); t.eq(S.reason, "Spotted by Gallery Guard"); t.eq(S.reasonPlayer, "alice")
	end)

	t.test("sneaking halves exposure rate", function()
		local S = SecurityState.new(cfg)
		local v = S:report("g1", "Guard", "alice", 1, true, 0)
		t.near(v, 0.25)
		t.eq(S.level, 0)
	end)

	t.test("suspicion decays and the system calms down level by level", function()
		local S = SecurityState.new(cfg)
		S:report("g1", "Guard", "alice", 1, false, 0)
		S:step(2, 2)
		t.eq(S:suspicionOf("alice"), 0)
		S:step(1, 31)
		t.eq(S.level, 0)
	end)

	t.test("alert leads to lockdown after delay; lockdown calms straight to quiet", function()
		local S = SecurityState.new(cfg)
		S:noise("Front glass smashed", "bob", 0)
		t.eq(S.level, 2)
		S:step(1, 9); t.eq(S.level, 2)
		S:step(1, 10); t.eq(S.level, 3)
		S:step(1, 41); t.eq(S.level, 0)
		t.falsy(S.alertAt)
	end)

	t.test("cameras and power cut windows", function()
		local S = SecurityState.new(cfg)
		t.truthy(S:camerasActive(0))
		S:disableCameras(0, 10); t.falsy(S:camerasActive(5)); t.truthy(S:camerasActive(10))
		S:cutPower(20, 5); t.truthy(S:powerCutActive(24)); t.falsy(S:camerasActive(24)); t.falsy(S:powerCutActive(25))
	end)

	t.test("reset clears everything", function()
		local S = SecurityState.new(cfg)
		S:noise("x", nil, 0); S:reset(1)
		t.eq(S.level, 0); t.eq(S.reason, nil)
	end)
end
