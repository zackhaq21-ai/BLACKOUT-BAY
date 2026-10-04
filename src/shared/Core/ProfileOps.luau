--!strict
-- Pure, merge-safe profile operations, carried over from the Studio-tested prototype's ProfileModel and
-- adapted to this profile schema. Ops are applied to the STORED value inside UpdateAsync (never a stale
-- full profile), so XP, wins, entitlements and receipts cannot be lost or duplicated:
--   Run      {id, xp, won}      credited once per run id
--   Receipt  {receipt, item}    entitlement + receipt committed together, idempotent per receipt
--   Pass     {item}             ownership confirmed by Roblox (game pass)
--   Equip    {item}             only owned items; never changes stats

export type CatalogItem = { Id: string, Name: string, Kind: string, EarnedXP: number | boolean, PassId: number, ProductId: number, Color: { number } }

export type Op = { kind: string, id: string?, xp: number?, won: boolean?, receipt: string?, item: string? }

local ProfileOps = {}

local function applyEarned(p: any, catalog: { CatalogItem })
	for _, item in ipairs(catalog) do
		if type(item.EarnedXP) == "number" and p.xp >= item.EarnedXP then
			p.entitlements[item.Id] = true
		end
	end
end

-- Mutates and returns `p` (a migrated profile data table). Returns (p, changed).
function ProfileOps.apply(p: any, op: Op, catalog: { CatalogItem }): (any, boolean)
	local changed = false
	if op.kind == "Run" and type(op.id) == "string" and type(op.xp) == "number" then
		if not p.runsSeen[op.id] then
			p.runsSeen[op.id] = true
			p.xp += math.max(0, math.floor(op.xp))
			p.stats.jobs += 1
			if op.won then
				p.wins += 1
			end
			changed = true
		end
	elseif op.kind == "Receipt" and type(op.receipt) == "string" and type(op.item) == "string" then
		if not p.receipts[op.receipt] then
			p.receipts[op.receipt] = true
			p.entitlements[op.item] = true
			changed = true
		end
	elseif op.kind == "Pass" and type(op.item) == "string" then
		if not p.entitlements[op.item] then
			p.entitlements[op.item] = true
			changed = true
		end
	elseif op.kind == "Equip" and type(op.item) == "string" then
		for _, item in ipairs(catalog) do
			if item.Id == op.item and p.entitlements[item.Id] then
				local slot = if item.Kind == "Decor" then "decor" else "equipped"
				if p[slot] ~= item.Id then
					p[slot] = item.Id
					changed = true
				end
			end
		end
	end
	applyEarned(p, catalog)
	return p, changed
end

-- Entitlements are permanent: nothing in a raid or a lost run may remove them.
function ProfileOps.owns(p: any, itemId: string): boolean
	return p.entitlements[itemId] == true
end

function ProfileOps.find(catalog: { CatalogItem }, itemId: string): CatalogItem?
	for _, item in ipairs(catalog) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

return ProfileOps
