--!strict
-- The island as data. World axes: +X east, +Z south, ground surface at y = 0.
-- Builders turn this into parts; tools/map_preview.py renders it for inspection; tests check invariants.
-- Everything here is original fiction: Blackout Bay, a stylized coastal city on an island.

export type P = { x: number, z: number }
export type Road = { name: string, from: P, to: P, width: number, elevated: boolean?, pedestrian: boolean?, bridge: boolean? }
export type Building = { name: string, x: number, z: number, w: number, d: number, h: number, style: string, rot: number? }
export type Hideout = { id: string, label: string, x: number, z: number, w: number, d: number, facing: number }
export type Named = { name: string, x: number, z: number, rot: number? }

local Blueprint = {}

Blueprint.Island = { minX = -620, maxX = 620, minZ = -500, maxZ = 500, groundY = 0, seaY = -2.5 }

-- Roads. Main roads are 24 wide; lanes are 14. The Seawall Overpass carries Aurora Boulevard over the Cut.
Blueprint.Roads = {
	{ name = "Aurora Boulevard West", from = { x = -560, z = -60 }, to = { x = -480, z = -60 }, width = 24 },
	{ name = "Seawall Overpass", from = { x = -480, z = -60 }, to = { x = -280, z = -60 }, width = 24, elevated = true },
	{ name = "Aurora Boulevard", from = { x = -280, z = -60 }, to = { x = 560, z = -60 }, width = 24 },
	{ name = "Seawall Road", from = { x = -560, z = -400 }, to = { x = -560, z = 400 }, width = 24 },
	{ name = "Harbor Road", from = { x = -200, z = -60 }, to = { x = -200, z = 300 }, width = 24 },
	{ name = "Market Street", from = { x = 280, z = -440 }, to = { x = 280, z = 300 }, width = 24 },
	{ name = "Dockside Street", from = { x = -560, z = 300 }, to = { x = 560, z = 300 }, width = 24, bridge = true },
	{ name = "Station Road", from = { x = -200, z = 140 }, to = { x = 560, z = 140 }, width = 24 },
	{ name = "East Coast Road", from = { x = 560, z = -440 }, to = { x = 560, z = 400 }, width = 24 },
	{ name = "Lighthouse Road", from = { x = 280, z = -440 }, to = { x = 560, z = -440 }, width = 14 },
	{ name = "North Row", from = { x = -560, z = -400 }, to = { x = -200, z = -400 }, width = 14 },
	{ name = "Canal Lane", from = { x = -360, z = -440 }, to = { x = 280, z = -440 }, width = 14, pedestrian = true },
	{ name = "Canal Walk", from = { x = -360, z = -440 }, to = { x = -360, z = 300 }, width = 10, pedestrian = true },
}

-- The Cut: a canal running north-south. Crossed by the Seawall Overpass (elevated) and Dockside (low bridge).
Blueprint.Canal = { x = -395, fromZ = -440, toZ = 300, width = 30 }

-- Key places
Blueprint.Museum = { x = 0, z = -280, w = 240, d = 200, h = 26 } -- front faces +Z (south) onto the plaza
Blueprint.Plaza = { x = 0, z = -130, w = 300, d = 100 }
Blueprint.ParkingDeck = { x = 215, z = -280, w = 100, d = 160, h = 14 } -- east of the museum; roof links to the museum roof
Blueprint.PoliceStation = { x = 460, z = 215, w = 120, d = 100, h = 16 }
Blueprint.PoliceLot = { x = 460, z = 90, w = 120, d = 60 }
Blueprint.Lighthouse = { x = 575, z = -470 }
Blueprint.LanternCross = { x = -200, z = -60, signX = -232, signZ = -94 }

-- Harbor hideouts: pier units on the south side of Dockside Street, garage doors facing north (-Z).
Blueprint.Hideouts = {} :: { Hideout }
do
	local labels = { "Pier A", "Pier B", "Pier C", "Pier D", "Pier E", "Pier F" }
	for i = 1, 6 do
		table.insert(Blueprint.Hideouts, { id = "pier" .. i, label = labels[i], x = -540 + (i - 1) * 60, z = 365, w = 48, d = 70, facing = 0 })
	end
end

-- Armored convoy routes: waypoints are drivable road nodes (axis-aligned legs along one road each).
-- `checkpoints` are waypoint indices where the convoy makes a planned halt. Validated by tests/map_blueprint.spec.
Blueprint.ConvoyRoutes = {
	{ name = "Lighthouse Run", waypoints = { { x = 560, z = -440 }, { x = 560, z = 300 }, { x = -200, z = 300 }, { x = -200, z = 140 }, { x = 560, z = 140 } }, checkpoints = { 2, 3 } },
	{ name = "Boulevard Express", waypoints = { { x = -560, z = -400 }, { x = -560, z = -60 }, { x = -200, z = -60 }, { x = 280, z = -60 }, { x = 560, z = -60 }, { x = 560, z = 140 } }, checkpoints = { 3, 4 } },
	{ name = "Station Circuit", waypoints = { { x = 560, z = 140 }, { x = -200, z = 140 }, { x = -200, z = -60 }, { x = 280, z = -60 }, { x = 280, z = 300 }, { x = 560, z = 300 } }, checkpoints = { 2, 4 } },
	{ name = "Seawall Loop", waypoints = { { x = -200, z = -400 }, { x = -560, z = -400 }, { x = -560, z = -60 }, { x = -560, z = 300 }, { x = 280, z = 300 } }, checkpoints = { 3, 4 } },
}

-- Harbour Substation: the grid cabinet a crew can sabotage (crew-triggered blackout). In the crane yard.
Blueprint.Substation = { x = -440, z = 14, w = 36, d = 22 }

-- Breakwater Lockup: where an offline owner's hideout is instantiated for a raid (same footprint as a pier unit).
Blueprint.Lockup = { id = "lockup", label = "Breakwater Lockup", x = -180, z = 365, w = 48, d = 70, facing = 0 } :: Hideout

-- City blocks. Style keys are interpreted by the builder (Stone, Warm, Industrial, Glass, Brick).
Blueprint.Buildings = {
	-- North-west residential rows (between Seawall Rd, North Row, the Cut and Aurora Blvd)
	{ name = "Terrace 1", x = -500, z = -330, w = 70, d = 60, h = 22, style = "Stone" },
	{ name = "Terrace 2", x = -500, z = -240, w = 70, d = 70, h = 18, style = "Warm" },
	{ name = "Terrace 3", x = -500, z = -150, w = 70, d = 60, h = 26, style = "Stone" },
	{ name = "Gasworks", x = -440, z = -250, w = 40, d = 160, h = 30, style = "Industrial" },
	-- Industrial waterfront (south-west, between Seawall Rd, Aurora Blvd, the Cut and Dockside)
	{ name = "Warehouse 1", x = -500, z = 30, w = 80, d = 80, h = 20, style = "Industrial" },
	{ name = "Warehouse 2", x = -500, z = 150, w = 80, d = 90, h = 24, style = "Industrial" },
	{ name = "Cold Store", x = -440, z = 220, w = 40, d = 60, h = 28, style = "Industrial" },
	{ name = "Crane Yard", x = -440, z = 60, w = 40, d = 100, h = 6, style = "Yard" },
	-- Inner city west (between the Cut, Harbor Rd, Aurora Blvd, Dockside)
	{ name = "Arcade", x = -300, z = 10, w = 90, d = 80, h = 30, style = "Glass" },
	{ name = "Tenement 1", x = -300, z = 130, w = 90, d = 70, h = 34, style = "Brick" },
	{ name = "Tenement 2", x = -300, z = 230, w = 90, d = 60, h = 26, style = "Brick" },
	{ name = "Fishmarket", x = -230, z = 240, w = 30, d = 60, h = 12, style = "Warm" },
	-- North-west of museum (between the Cut, museum, North Row/Canal Lane, Aurora Blvd)
	{ name = "Printworks", x = -300, z = -340, w = 90, d = 80, h = 24, style = "Brick" },
	{ name = "Chandlery", x = -300, z = -220, w = 90, d = 80, h = 20, style = "Warm" },
	{ name = "Glass Tower", x = -300, z = -120, w = 70, d = 60, h = 70, style = "Glass" },
	{ name = "Hotel Meridian", x = -190, z = -300, w = 50, d = 120, h = 44, style = "Stone" },
	-- East of museum / parking deck (between deck, Market St)
	-- North-east (between Market St, Lighthouse Rd, East Coast Rd, Aurora Blvd)
	{ name = "Aurora Annex", x = 350, z = -370, w = 90, d = 60, h = 18, style = "Stone" },
	{ name = "Observatory", x = 450, z = -370, w = 80, d = 80, h = 36, style = "Stone" },
	{ name = "Boathouse", x = 525, z = -370, w = 40, d = 60, h = 14, style = "Warm" },
	{ name = "Vantage Flats", x = 350, z = -250, w = 90, d = 100, h = 40, style = "Glass" },
	{ name = "Signal House", x = 450, z = -250, w = 70, d = 70, h = 30, style = "Brick" },
	{ name = "Lighthouse Keep", x = 520, z = -250, w = 50, d = 90, h = 22, style = "Stone" },
	{ name = "Row Shops", x = 350, z = -130, w = 90, d = 50, h = 16, style = "Warm" },
	{ name = "Harbour Court", x = 470, z = -130, w = 120, d = 50, h = 24, style = "Stone" },
	-- South-east (between Market St, Station Rd/Dockside, East Coast Rd, Aurora Blvd)
	{ name = "Exchange Offices", x = 350, z = 30, w = 90, d = 90, h = 48, style = "Glass" },
	{ name = "Depot", x = 470, z = 10, w = 100, d = 60, h = 18, style = "Industrial" },
	{ name = "Courthouse", x = 350, z = 215, w = 90, d = 90, h = 28, style = "Stone" },
	-- Centre south (between Harbor Rd, Market St, Aurora Blvd, Station Rd)
	{ name = "Lantern Hall", x = -120, z = 40, w = 90, d = 110, h = 32, style = "Warm" },
	{ name = "Bank of the Bay", x = 20, z = 40, w = 120, d = 110, h = 36, style = "Stone" },
	{ name = "Tram Shed", x = 170, z = 40, w = 100, d = 110, h = 20, style = "Industrial" },
	-- Centre south of Station Rd (between Harbor Rd, Market St, Station Rd, Dockside)
	{ name = "Rooming House", x = -120, z = 225, w = 90, d = 90, h = 24, style = "Brick" },
	{ name = "Harbour Office", x = 20, z = 225, w = 120, d = 90, h = 20, style = "Stone" },
	{ name = "Netloft", x = 170, z = 225, w = 100, d = 90, h = 16, style = "Warm" },
	-- Far east coast
	{ name = "Ferry Terminal", x = 460, z = 360, w = 160, d = 60, h = 14, style = "Glass" },
}

-- Street cars anyone can take. Positions are at the kerb, facing along the road (rot in degrees).
Blueprint.StreetCars = {
	{ name = "Plaza West", x = -150, z = -78, rot = 90 },
	{ name = "Plaza East", x = 150, z = -78, rot = 90 },
	{ name = "Market Kerb", x = 298, z = 60, rot = 0 },
	{ name = "Dockside Kerb", x = 0, z = 284, rot = 90 },
	{ name = "Station Kerb", x = 300, z = 124, rot = 90 },
}

-- Vehicle-blocking bollards (pedestrian routes stay walkable; heavy carriers slow down).
Blueprint.Bollards = {
	{ name = "Canal Lane East", x = 264, z = -440, rot = 0 },
	{ name = "Canal Walk North", x = -360, z = -430, rot = 90 },
	{ name = "Canal Walk South", x = -360, z = 286, rot = 90 },
	{ name = "Canal Walk at North Row (north)", x = -360, z = -412, rot = 90 },
	{ name = "Canal Walk at North Row (south)", x = -360, z = -388, rot = 90 },
}

-- Police patrol loop (NPC cruisers follow this when idle) and the barricade point for high heat.
Blueprint.PolicePatrol = {
	{ x = 460, z = 140 }, { x = 280, z = 140 }, { x = 280, z = -60 }, { x = -200, z = -60 },
	{ x = -200, z = 300 }, { x = 280, z = 300 }, { x = 460, z = 300 }, { x = 560, z = 140 },
}
Blueprint.Barricade = { x = -200, z = -60 } -- Lantern Cross

-- Landmarks with readable names (used by hints, logs and the prep board).
Blueprint.Landmarks = {
	{ name = "Lantern Cross", x = -200, z = -60 },
	{ name = "Aurora Plaza", x = 0, z = -130 },
	{ name = "Seawall Overpass", x = -380, z = -60 },
	{ name = "Canal Walk", x = -360, z = -70 },
	{ name = "Harbour Piers", x = -390, z = 365 },
	{ name = "Lighthouse Point", x = 575, z = -470 },
	{ name = "Police Station", x = 460, z = 215 },
	{ name = "Harbour Substation", x = -440, z = 14 },
	{ name = "Parking Deck", x = 215, z = -280 },
	{ name = "Canal Lane", x = -80, z = -440 },
}

-- Pre-authored route intel shown on the prep board. Readable, honest about tradeoffs.
Blueprint.Routes = {
	{ key = "front", title = "Front: Aurora Plaza", summary = "Smash the glass doors. 3 seconds in, instant alarm. Cars can wait on the Boulevard. Cameras cover the plaza." },
	{ key = "service", title = "Service: Loading Dock", summary = "Keypad door off Canal Lane. The code is on the security office board; the office guard patrols out every minute. The lane is bollarded: no cars until Market Street or Dockside." },
	{ key = "roof", title = "Roof: Parking Deck", summary = "Climb the gantry from the deck roof, drop through the skylight. Quiet. Heavy loot cannot climb back out: throw light bags off the roof, or exit another way." },
}

function Blueprint.nearestLandmark(x: number, z: number): string
	local best, bestD = "the island", math.huge
	for _, l in ipairs(Blueprint.Landmarks) do
		local d = (l.x - x) ^ 2 + (l.z - z) ^ 2
		if d < bestD then
			best, bestD = l.name, d
		end
	end
	return best
end

return Blueprint
