local C = require("../src/shared/Core/CameraFeel")
local Config = require("../src/shared/Config")
local cfg = Config.Presentation.Camera
local function st(over)
	local s = { speed = 0, topSpeed = 21, sprinting = false, sneaking = false, seated = false, vehicleSpeed = 0, vehicleTopSpeed = 70, downed = false }
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

return function(t)
	t.test("field of view follows state and stays bounded", function()
		t.eq(C.targetFov(cfg, st()), cfg.BaseFov)
		t.eq(C.targetFov(cfg, st({ sprinting = true, speed = 21 })), cfg.SprintFov)
		t.truthy(C.targetFov(cfg, st({ sprinting = true, speed = 10 })) < cfg.SprintFov)
		t.eq(C.targetFov(cfg, st({ sneaking = true })), cfg.SneakFov)
		t.eq(C.targetFov(cfg, st({ downed = true, sprinting = true })), cfg.DownedFov, "downed wins")
		t.eq(C.targetFov(cfg, st({ seated = true, vehicleSpeed = 0 })), cfg.BaseFov)
		t.eq(C.targetFov(cfg, st({ seated = true, vehicleSpeed = 70 })), cfg.VehicleFovMax)
		t.truthy(C.targetFov(cfg, st({ seated = true, vehicleSpeed = 20 })) == cfg.BaseFov, "no pumping at town speeds")
		local silly = table.clone(cfg); silly.VehicleFovMax = 170
		t.truthy(C.targetFov(silly, st({ seated = true, vehicleSpeed = 999 })) <= 85, "clamped")
		t.eq(C.targetFov(cfg, st({ speed = 0 / 0 })), cfg.BaseFov, "NaN speed ignored")
	end)
	t.test("landing dip scales with fall speed and is clamped", function()
		t.eq(C.landingDip(cfg, 5), 0)
		t.eq(C.landingDip(cfg, cfg.LandingDipMinFall), 0)
		t.truthy(C.landingDip(cfg, 40) > 0 and C.landingDip(cfg, 40) < cfg.LandingDipMax)
		t.eq(C.landingDip(cfg, 500), cfg.LandingDipMax)
		t.eq(C.landingDip(cfg, 0 / 0), 0)
	end)
	t.test("smoothing never overshoots and tolerates bad dt", function()
		local v = C.approach(70, 80, cfg.FovSmoothing, 0.016)
		t.truthy(v > 70 and v < 80)
		t.truthy(C.approach(70, 80, cfg.FovSmoothing, 100) <= 80)
		t.eq(C.approach(0 / 0, 80, 6, 0.016), 80)
		t.eq(C.approach(70, 70, 6, 0.016), 70)
	end)
end
