--!strict
-- Road network as a graph: nodes at segment endpoints and intersections, edges along segments.
-- Pure Luau so NPC driving can be tested without Roblox. Pedestrian roads are excluded.

export type Node = { id: number, x: number, z: number }
export type Road = { name: string, from: { x: number, z: number }, to: { x: number, z: number }, width: number, elevated: boolean?, pedestrian: boolean?, bridge: boolean? }

local RoadGraph = {}
RoadGraph.__index = RoadGraph

export type RoadGraph = typeof(setmetatable({} :: { nodes: { Node }, adj: { [number]: { { to: number, cost: number } } } }, RoadGraph))

local function key(x: number, z: number): string
	return string.format("%d,%d", math.round(x), math.round(z))
end

function RoadGraph.new(roads: { Road }): RoadGraph
	local nodes: { Node } = {}
	local adj: { [number]: { { to: number, cost: number } } } = {}
	local self = setmetatable({ nodes = nodes, adj = adj }, RoadGraph)
	local lookup: { [string]: number } = {}
	local function node(x: number, z: number): number
		local k = key(x, z)
		local existing = lookup[k]
		if existing then
			return existing
		end
		local id: number = #nodes + 1
		nodes[id] = { id = id, x = x, z = z }
		adj[id] = {}
		lookup[k] = id
		return id
	end
	local drivable = {}
	for _, r in ipairs(roads) do
		if not r.pedestrian then
			table.insert(drivable, r)
		end
	end
	-- Collect split points per segment: endpoints plus intersections with every other segment
	local points: { { number } } = {}
	for i, r in ipairs(drivable) do
		local pts = { r.from.x == r.to.x and r.from.z or r.from.x, r.from.x == r.to.x and r.to.z or r.to.x }
		local vertical = r.from.x == r.to.x
		for j, o in ipairs(drivable) do
			if i ~= j then
				local oVertical = o.from.x == o.to.x
				if vertical ~= oVertical then
					local vx = if vertical then r.from.x else o.from.x
					local hz = if vertical then o.from.z else r.from.z
					local vz1, vz2 = math.min((if vertical then r else o).from.z, (if vertical then r else o).to.z), math.max((if vertical then r else o).from.z, (if vertical then r else o).to.z)
					local hx1, hx2 = math.min((if vertical then o else r).from.x, (if vertical then o else r).to.x), math.max((if vertical then o else r).from.x, (if vertical then o else r).to.x)
					if vx >= hx1 and vx <= hx2 and hz >= vz1 and hz <= vz2 then
						table.insert(pts, if vertical then hz else vx)
					end
				end
			end
		end
		table.sort(pts)
		points[i] = pts
	end
	for i, r in ipairs(drivable) do
		local vertical = r.from.x == r.to.x
		local prev: number? = nil
		local lastT: number? = nil
		for _, t in ipairs(points[i]) do
			if lastT == nil or math.abs(t - lastT) > 0.5 then
				local id = if vertical then node(r.from.x, t) else node(t, r.from.z)
				if prev then
					local cost = math.abs(t - (lastT :: number))
					table.insert(self.adj[prev], { to = id, cost = cost })
					table.insert(self.adj[id], { to = prev, cost = cost })
				end
				prev = id
				lastT = t
			end
		end
	end
	return self
end

function RoadGraph.nearest(self: RoadGraph, x: number, z: number): number
	local best, bestD = 1, math.huge
	for _, n in ipairs(self.nodes) do
		local d = (n.x - x) ^ 2 + (n.z - z) ^ 2
		if d < bestD then
			best, bestD = n.id, d
		end
	end
	return best
end

-- Dijkstra. Returns the node id list from `from` to `to` (inclusive), or nil if unreachable.
function RoadGraph.path(self: RoadGraph, from: number, to: number): { number }?
	local dist: { [number]: number } = { [from] = 0 }
	local prev: { [number]: number } = {}
	local visited: { [number]: boolean } = {}
	while true do
		local u, best = nil, math.huge
		for id, d in pairs(dist) do
			if not visited[id] and d < best then
				u, best = id, d
			end
		end
		if not u then
			break
		end
		if u == to then
			break
		end
		visited[u] = true
		for _, e in ipairs(self.adj[u]) do
			local nd = best + e.cost
			if dist[e.to] == nil or nd < dist[e.to] then
				dist[e.to] = nd
				prev[e.to] = u
			end
		end
	end
	if dist[to] == nil then
		return nil
	end
	local out = {}
	local cur: number? = to
	while cur do
		table.insert(out, 1, cur)
		cur = prev[cur]
	end
	return out
end

return RoadGraph
