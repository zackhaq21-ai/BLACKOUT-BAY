-- Cross-config invariants: every table that another table indexes by name is complete, so a renamed state or
-- tier can never silently fall back to a default at runtime.
local Config = require("../src/shared/Config")

return function(t)
	t.test("weather states have a look factor and a weight", function()
		local W = Config.Presentation.Weather
		for _, s in ipairs(W.States) do
			t.truthy(type(W.Vision[s]) == "number", "vision for " .. s)
			t.truthy(type(W.Weights[s]) == "number", "weight for " .. s)
		end
		t.truthy(W.MinSeconds <= W.MaxSeconds and W.BlendSeconds > 0)
	end)
	t.test("every graphics tier is defined in every tier table", function()
		local G = Config.Presentation.Graphics
		for _, tier in ipairs(G.Tiers) do
			for _, tbl in ipairs({ "Bloom", "Particles", "Shadows", "DepthOfField", "RainRate" }) do
				t.truthy(G[tbl][tier] ~= nil, tbl .. "." .. tier)
			end
		end
	end)
	t.test("audio cues map to known sound groups and every engine kind is a vehicle", function()
		local groups = { Ambience = true, Weather = true, City = true, Vehicles = true, Police = true, UI = true, Interaction = true, Events = true, Interiors = true }
		for cue, group in pairs(Config.Audio.Groups) do
			t.truthy(Config.Audio.Cues[cue] ~= nil, "group for unknown cue " .. cue)
			t.truthy(groups[group], cue .. " -> unknown group " .. tostring(group))
		end
		for kind in pairs(Config.Audio.Engines) do
			t.truthy(type(Config.Vehicles[kind]) == "table", "engine for unknown vehicle " .. kind)
		end
		for _, id in pairs(Config.Audio.Cues) do t.eq(id, "", "no unverified asset ids") end
	end)
	t.test("vehicle classes are complete and the heavy class really is heavy", function()
		for kind, tune in pairs(Config.Vehicles) do
			if type(tune) == "table" then
				for _, k in ipairs({ "label", "maxSpeed", "accel", "brake", "steer", "seats", "trunk", "health", "mass" }) do
					t.truthy(tune[k] ~= nil, kind .. "." .. k)
				end
			end
		end
		t.truthy(Config.Vehicles.Armored.mass >= Config.Presentation.Vehicle.HeavyMass)
		t.truthy(Config.Vehicles.Kestrel.mass < Config.Presentation.Vehicle.HeavyMass)
		t.truthy(Config.Vehicles.WheelRadius > 0)
	end)
	t.test("world-event constants stay inside their rule bounds", function()
		local B, C = Config.WorldEvents.Blackout, Config.WorldEvents.Convoy
		t.truthy(B.DurationSeconds <= B.CooldownSeconds and B.SabotageSeconds < B.DurationSeconds and B.ResetSeconds < B.DurationSeconds)
		t.truthy(C.MaxDurationSeconds <= C.CooldownSeconds and C.AnticipationSeconds < C.MaxDurationSeconds and C.AbandonSeconds < C.MaxDurationSeconds)
		t.truthy(C.CheckpointSeconds * 2 + 60 < C.MaxDurationSeconds, "two halts still leave time to drive")
	end)
end
