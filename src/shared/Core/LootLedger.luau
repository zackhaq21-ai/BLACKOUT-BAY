--!strict
-- Authoritative registry for physical loot. One identity per item, one valid location state,
-- every transition logged. Pure Luau: no Roblox globals, so it is unit-tested with the luau CLI.

export type ItemState = "InCase" | "Carried" | "Dropped" | "InVehicle" | "Delivered" | "Destroyed"

export type Item = {
	id: string,
	kind: string,
	label: string,
	value: number,
	weight: "Light" | "Heavy",
	state: ItemState,
	holder: string?, -- player key when Carried
	vehicle: string?, -- vehicle key when InVehicle
	position: any?, -- opaque (Vector3 in Roblox) when Dropped/InCase
	deliveredTo: string?, -- crew job id when Delivered
	deliveredBy: string?,
	origin: string?, -- e.g. "AuroraExchange"
	history: { Transition },
}

export type Transition = { t: number, from: ItemState, to: ItemState, actor: string?, note: string? }

local LootLedger = {}
LootLedger.__index = LootLedger

export type LootLedger = typeof(setmetatable({} :: { items: { [string]: Item }, now: () -> number }, LootLedger))

function LootLedger.new(now: (() -> number)?): LootLedger
	return setmetatable({ items = {}, now = now or function()
		return 0
	end }, LootLedger)
end

local function record(self: LootLedger, item: Item, to: ItemState, actor: string?, note: string?)
	table.insert(item.history, { t = self.now(), from = item.state, to = to, actor = actor, note = note })
	item.state = to
end

function LootLedger.register(self: LootLedger, spec: { id: string, kind: string, label: string, value: number, weight: "Light" | "Heavy", position: any?, origin: string? }): (boolean, string?)
	if self.items[spec.id] then
		return false, "duplicate id"
	end
	if type(spec.value) ~= "number" or spec.value < 0 then
		return false, "bad value"
	end
	self.items[spec.id] = {
		id = spec.id,
		kind = spec.kind,
		label = spec.label,
		value = spec.value,
		weight = spec.weight,
		state = "InCase",
		position = spec.position,
		origin = spec.origin,
		history = {},
	}
	return true, nil
end

function LootLedger.get(self: LootLedger, id: string): Item?
	return self.items[id]
end

function LootLedger.carriedBy(self: LootLedger, playerKey: string): { Item }
	local out = {}
	for _, item in pairs(self.items) do
		if item.state == "Carried" and item.holder == playerKey then
			table.insert(out, item)
		end
	end
	return out
end

function LootLedger.inVehicle(self: LootLedger, vehicleKey: string): { Item }
	local out = {}
	for _, item in pairs(self.items) do
		if item.state == "InVehicle" and item.vehicle == vehicleKey then
			table.insert(out, item)
		end
	end
	return out
end

function LootLedger.countInState(self: LootLedger, state: ItemState): number
	local n = 0
	for _, item in pairs(self.items) do
		if item.state == state then
			n += 1
		end
	end
	return n
end

-- Pick up from a case or the ground. maxCarry enforces the player's hands.
function LootLedger.pickUp(self: LootLedger, id: string, playerKey: string, maxCarry: number): (boolean, string?)
	local item = self.items[id]
	if not item then
		return false, "no such item"
	end
	if item.state ~= "InCase" and item.state ~= "Dropped" then
		return false, "not available"
	end
	if #self:carriedBy(playerKey) >= maxCarry then
		return false, "hands full"
	end
	item.holder = playerKey
	item.position = nil
	record(self, item, "Carried", playerKey, if item.state == "InCase" then "taken from case" else "picked up")
	return true, nil
end

function LootLedger.drop(self: LootLedger, id: string, playerKey: string, position: any?, note: string?): (boolean, string?)
	local item = self.items[id]
	if not item then
		return false, "no such item"
	end
	if item.state ~= "Carried" or item.holder ~= playerKey then
		return false, "not carried by player"
	end
	item.holder = nil
	item.position = position
	record(self, item, "Dropped", playerKey, note or "dropped")
	return true, nil
end

function LootLedger.dropAllFromPlayer(self: LootLedger, playerKey: string, position: any?, note: string?): { Item }
	local dropped = {}
	for _, item in ipairs(self:carriedBy(playerKey)) do
		self:drop(item.id, playerKey, position, note)
		table.insert(dropped, item)
	end
	return dropped
end

function LootLedger.stow(self: LootLedger, id: string, playerKey: string, vehicleKey: string, capacity: number): (boolean, string?)
	local item = self.items[id]
	if not item then
		return false, "no such item"
	end
	if item.state ~= "Carried" or item.holder ~= playerKey then
		return false, "not carried by player"
	end
	if #self:inVehicle(vehicleKey) >= capacity then
		return false, "trunk full"
	end
	item.holder = nil
	item.vehicle = vehicleKey
	record(self, item, "InVehicle", playerKey, "stowed in " .. vehicleKey)
	return true, nil
end

function LootLedger.takeFromVehicle(self: LootLedger, id: string, playerKey: string, vehicleKey: string, maxCarry: number): (boolean, string?)
	local item = self.items[id]
	if not item then
		return false, "no such item"
	end
	if item.state ~= "InVehicle" or item.vehicle ~= vehicleKey then
		return false, "not in that vehicle"
	end
	if #self:carriedBy(playerKey) >= maxCarry then
		return false, "hands full"
	end
	item.vehicle = nil
	item.holder = playerKey
	record(self, item, "Carried", playerKey, "taken from " .. vehicleKey)
	return true, nil
end

function LootLedger.dropAllFromVehicle(self: LootLedger, vehicleKey: string, position: any?, note: string?): { Item }
	local dropped = {}
	for _, item in ipairs(self:inVehicle(vehicleKey)) do
		item.vehicle = nil
		item.position = position
		record(self, item, "Dropped", nil, note or ("fell out of " .. vehicleKey))
		table.insert(dropped, item)
	end
	return dropped
end

-- Deliver value exactly once. Returns the value credited.
function LootLedger.deliver(self: LootLedger, id: string, playerKey: string, jobId: string): (boolean, string?, number)
	local item = self.items[id]
	if not item then
		return false, "no such item", 0
	end
	if item.state ~= "Carried" or item.holder ~= playerKey then
		return false, "not carried by player", 0
	end
	item.holder = nil
	item.deliveredTo = jobId
	item.deliveredBy = playerKey
	record(self, item, "Delivered", playerKey, "delivered to " .. jobId)
	return true, nil, item.value
end

function LootLedger.destroy(self: LootLedger, id: string, note: string?): boolean
	local item = self.items[id]
	if not item or item.state == "Delivered" or item.state == "Destroyed" then
		return false
	end
	item.holder = nil
	item.vehicle = nil
	record(self, item, "Destroyed", nil, note or "destroyed")
	return true
end

-- Remove terminal items (used on restock so ids never collide with live items).
function LootLedger.purgeTerminal(self: LootLedger): number
	local n = 0
	for id, item in pairs(self.items) do
		if item.state == "Delivered" or item.state == "Destroyed" then
			self.items[id] = nil
			n += 1
		end
	end
	return n
end

function LootLedger.history(self: LootLedger, id: string): { Transition }
	local item = self.items[id]
	return if item then item.history else {}
end

return LootLedger
