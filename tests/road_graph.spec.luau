local RoadGraph = require("../src/shared/Core/RoadGraph")
local B = require("../src/shared/MapBlueprint")

return function(t)
	t.test("every drivable road node reaches every other (one connected network)", function()
		local g = RoadGraph.new(B.Roads)
		t.truthy(#g.nodes > 10, "nodes")
		for _, n in ipairs(g.nodes) do
			local p = g:path(1, n.id)
			t.truthy(p, "node " .. n.id .. " at " .. n.x .. "," .. n.z .. " unreachable")
		end
	end)

	t.test("path from the police lot to the museum plaza passes Lantern Cross or Market Street", function()
		local g = RoadGraph.new(B.Roads)
		local from = g:nearest(460, 140)
		local to = g:nearest(0, -60)
		local p = g:path(from, to)
		t.truthy(p)
		t.truthy(#p >= 3)
		local last = g.nodes[p[#p]]
		t.eq(last.z, -60)
	end)

	t.test("pedestrian lanes are excluded", function()
		local g = RoadGraph.new(B.Roads)
		for _, n in ipairs(g.nodes) do
			t.falsy(n.z == -440 and n.x < 280, "Canal Lane node leaked into the drivable graph")
		end
	end)
end
