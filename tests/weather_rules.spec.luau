local W = require("../src/shared/Core/WeatherRules")
local Config = require("../src/shared/Config")
local cfg = Config.Presentation.Weather

return function(t)
	t.test("next state is always a different, known state; weights respected", function()
		local seq = { 0, 0.2, 0.5, 0.8, 0.999 }
		for _, r in ipairs(seq) do
			local s = W.next(cfg, "Clear", function() return r end)
			t.truthy(s ~= "Clear" and W.isState(cfg, s), s)
		end
		t.eq(W.next({ States = { "Clear" }, Weights = {} }, "Clear", function() return 0.5 end), "Clear", "single state stays")
		-- Storm is rare: with Clear excluded, the first chunk of the roll is Overcast
		t.eq(W.next(cfg, "Clear", function() return 0 end), "Overcast")
	end)
	t.test("durations and lightning gaps are bounded", function()
		t.eq(W.duration(cfg, function() return 0 end), cfg.MinSeconds)
		t.eq(W.duration(cfg, function() return 1 end), cfg.MaxSeconds)
		t.truthy(W.duration({ MinSeconds = 1, MaxSeconds = 99999 }, function() return 1 end) <= 3600)
		local g = W.lightningGap(cfg, function() return 0.5 end)
		t.truthy(g >= cfg.LightningMinGap and g <= cfg.LightningMaxGap)
	end)
	t.test("vision factor never blinds NPCs", function()
		t.eq(W.visionFactor(cfg, "Clear"), 1)
		t.eq(W.visionFactor(cfg, "Fog"), cfg.Vision.Fog)
		t.eq(W.visionFactor({ Vision = { X = 0 } }, "X"), 0.5)
		t.eq(W.visionFactor({ Vision = { X = 0 / 0 } }, "X"), 1)
		t.eq(W.visionFactor(cfg, "Nonsense"), 1)
	end)
	t.test("blend keeps the world readable, including under a blackout", function()
		local a = W.blend(W.look("Clear"), W.look("Fog"), 0.5, 0)
		t.truthy(a.fogEnd >= 260 and a.fogStart <= a.fogEnd - 120)
		local b = W.blend(W.look("Storm"), W.look("Storm"), 1, 1)
		for i = 1, 3 do t.truthy(b.ambient[i] >= 20 and b.outdoorAmbient[i] >= 28, "ambient floor") end
		t.truthy(b.brightness > 0.5, "never black")
		t.eq(b.rain, 1)
		local c = W.blend(W.look("Clear"), W.look("Rain"), 0 / 0, 0 / 0)
		t.truthy(c.fogEnd == c.fogEnd and c.rain == W.look("Rain").rain, "NaN inputs resolve to the target, no blackout")
		t.eq(W.look("Unknown").rain, 0)
	end)
end
