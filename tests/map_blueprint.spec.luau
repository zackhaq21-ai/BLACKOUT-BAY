local B = require("../src/shared/MapBlueprint")

return function(t)
	local I = B.Island
	local function inside(x, z) return x >= I.minX and x <= I.maxX and z >= I.minZ and z <= I.maxZ end

	t.test("roads and buildings stay on the island", function()
		for _, r in ipairs(B.Roads) do
			t.truthy(inside(r.from.x, r.from.z) and inside(r.to.x, r.to.z), r.name)
			t.truthy(r.from.x == r.to.x or r.from.z == r.to.z, r.name .. " must be axis-aligned")
		end
		for _, b in ipairs(B.Buildings) do
			t.truthy(inside(b.x - b.w / 2, b.z - b.d / 2) and inside(b.x + b.w / 2, b.z + b.d / 2), b.name)
		end
	end)

	t.test("buildings do not overlap roads, the museum, the plaza, the deck or each other", function()
		local function rect(x, z, w, d) return { x1 = x - w / 2, x2 = x + w / 2, z1 = z - d / 2, z2 = z + d / 2 } end
		local function overlaps(a, b) return a.x1 < b.x2 and a.x2 > b.x1 and a.z1 < b.z2 and a.z2 > b.z1 end
		local reserved = {
			rect(B.Museum.x, B.Museum.z, B.Museum.w, B.Museum.d),
			rect(B.Plaza.x, B.Plaza.z, B.Plaza.w, B.Plaza.d),
			rect(B.ParkingDeck.x, B.ParkingDeck.z, B.ParkingDeck.w, B.ParkingDeck.d),
			rect(B.PoliceStation.x, B.PoliceStation.z, B.PoliceStation.w, B.PoliceStation.d),
			rect(B.PoliceLot.x, B.PoliceLot.z, B.PoliceLot.w, B.PoliceLot.d),
			rect(B.Canal.x, (B.Canal.fromZ + B.Canal.toZ) / 2, B.Canal.width, B.Canal.toZ - B.Canal.fromZ),
		}
		for _, r in ipairs(B.Roads) do
			local cx, cz = (r.from.x + r.to.x) / 2, (r.from.z + r.to.z) / 2
			local w = if r.from.x == r.to.x then r.width else math.abs(r.to.x - r.from.x) + r.width
			local d = if r.from.z == r.to.z then r.width else math.abs(r.to.z - r.from.z) + r.width
			table.insert(reserved, rect(cx, cz, w, d))
		end
		for _, h in ipairs(B.Hideouts) do table.insert(reserved, rect(h.x, h.z, h.w, h.d)) end
		local rects = {}
		for _, b in ipairs(B.Buildings) do
			local rb = rect(b.x, b.z, b.w, b.d)
			for _, res in ipairs(reserved) do t.falsy(overlaps(rb, res), b.name .. " overlaps reserved space") end
			for name, other in pairs(rects) do t.falsy(overlaps(rb, other), b.name .. " overlaps " .. name) end
			rects[b.name] = rb
		end
	end)

	t.test("the substation sits inside the crane yard, clear of roads and the canal", function()
		local S = B.Substation
		local yard
		for _, b in ipairs(B.Buildings) do if b.name == "Crane Yard" then yard = b end end
		t.truthy(yard)
		t.truthy(S.x - S.w / 2 >= yard.x - yard.w / 2 and S.x + S.w / 2 <= yard.x + yard.w / 2, "substation wider than the yard")
		t.truthy(S.z + S.d / 2 <= yard.z + yard.d / 2, "substation past the yard")
		local function overlaps(a, b) return a.x1 < b.x2 and a.x2 > b.x1 and a.z1 < b.z2 and a.z2 > b.z1 end
		local sr = { x1 = S.x - S.w / 2, x2 = S.x + S.w / 2, z1 = S.z - S.d / 2, z2 = S.z + S.d / 2 }
		for _, r in ipairs(B.Roads) do
			local rr = { x1 = math.min(r.from.x, r.to.x) - r.width / 2, x2 = math.max(r.from.x, r.to.x) + r.width / 2, z1 = math.min(r.from.z, r.to.z) - r.width / 2, z2 = math.max(r.from.z, r.to.z) + r.width / 2 }
			t.falsy(overlaps(sr, rr), "substation overlaps " .. r.name)
		end
		t.falsy(overlaps(sr, { x1 = B.Canal.x - B.Canal.width / 2, x2 = B.Canal.x + B.Canal.width / 2, z1 = B.Canal.fromZ, z2 = B.Canal.toZ }), "substation in the canal")
	end)

	t.test("convoy routes: legs on drivable roads, connected in the road graph, distinct starts, sane lengths", function()
		local RoadGraph = require("../src/shared/Core/RoadGraph")
		local Convoy = require("../src/shared/Core/ConvoyRules")
		local graph = RoadGraph.new(B.Roads)
		local function onRoadPoint(x, z)
			for _, r in ipairs(B.Roads) do
				if not r.pedestrian then
					local x1, x2 = math.min(r.from.x, r.to.x) - r.width / 2, math.max(r.from.x, r.to.x) + r.width / 2
					local z1, z2 = math.min(r.from.z, r.to.z) - r.width / 2, math.max(r.from.z, r.to.z) + r.width / 2
					if x >= x1 and x <= x2 and z >= z1 and z <= z2 then return true end
				end
			end
			return false
		end
		local function onRoad(a, b)
			local steps = math.max(1, math.floor((math.abs(b.x - a.x) + math.abs(b.z - a.z)) / 20))
			for i = 0, steps do
				local f = i / steps
				if not onRoadPoint(a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f) then return false end
			end
			return true
		end
		t.truthy(#B.ConvoyRoutes >= 3, "need several routes")
		local starts = {}
		for _, route in ipairs(B.ConvoyRoutes) do
			t.truthy(#route.waypoints >= 3, route.name)
			for i = 2, #route.waypoints do
				local a, b = route.waypoints[i - 1], route.waypoints[i]
				t.truthy(a.x == b.x or a.z == b.z, route.name .. " leg " .. i .. " not axis-aligned")
				t.truthy(onRoad(a, b), route.name .. " leg " .. i .. " leaves the drivable roads")
				t.truthy(graph:path(graph:nearest(a.x, a.z), graph:nearest(b.x, b.z)) ~= nil, route.name .. " leg " .. i .. " unreachable")
			end
			local len = Convoy.routeLength(route)
			t.truthy(len >= 1200 and len <= 3500, route.name .. " length " .. len)
			for _, c in ipairs(route.checkpoints) do t.truthy(c > 1 and c <= #route.waypoints, route.name .. " checkpoint index") end
			local s = route.waypoints[1]
			t.truthy(math.abs(s.x) ~= B.Canal.x, route.name .. " starts in the canal")
			for _, o in ipairs(starts) do t.truthy((o.x - s.x) ^ 2 + (o.z - s.z) ^ 2 >= 200 * 200, route.name .. " starts next to another route") end
			table.insert(starts, s)
		end
	end)

	t.test("six hideouts, unique ids, spaced apart", function()
		t.eq(#B.Hideouts, 6)
		local ids = {}
		for i, h in ipairs(B.Hideouts) do
			t.falsy(ids[h.id]); ids[h.id] = true
			if i > 1 then t.truthy(h.x - B.Hideouts[i - 1].x >= h.w, "hideouts overlap") end
		end
	end)

	t.test("nearest landmark lookup", function()
		t.eq(B.nearestLandmark(-205, -58), "Lantern Cross")
		t.eq(B.nearestLandmark(570, -460), "Lighthouse Point")
	end)

	t.test("every route and street car has a name", function()
		for _, r in ipairs(B.Routes) do t.truthy(#r.summary > 20, r.key) end
		for _, c in ipairs(B.StreetCars) do t.truthy(inside(c.x, c.z), c.name) end
	end)
end
