-- Pure merge-safe profile transformations. Store deltas, never a stale full profile.
local Model = {}
function Model.clean(old)
	if old ~= nil and (type(old) ~= "table" or old.version ~= 1) then
		error("Unsupported profile; refuse to overwrite")
	end
	old = old or {version = 1}
	local p = {version = 1, xp = 0, runs = 0, wins = 0, entitlements = {mint = true}, receipts = {}, runsSeen = {}, equipped = "mint", decor = ""}
	for _, k in ipairs({"xp", "runs", "wins"}) do
		local v = old[k]
		if type(v) == "number" and v == v and v >= 0 and v < 1e12 then p[k] = math.floor(v) end
	end
	for _, k in ipairs({"entitlements", "receipts", "runsSeen"}) do
		if type(old[k]) == "table" then
			for key, value in pairs(old[k]) do
				if type(key) == "string" and #key <= 160 and value == true then p[k][key] = true end
			end
		end
	end
	for _, k in ipairs({"equipped", "decor"}) do
		if type(old[k]) == "string" and #old[k] < 50 then p[k] = old[k] end
	end
	return p
end

function Model.apply(old, op, catalog)
	local p = Model.clean(old)
	if op.kind == "Run" then
		if not p.runsSeen[op.id] then
			p.runsSeen[op.id] = true; p.xp += op.xp; p.runs += 1
			if op.won then p.wins += 1 end
		end
	elseif op.kind == "Receipt" then
		-- Entitlement + receipt are committed in the SAME UpdateAsync transaction.
		if not p.receipts[op.receipt] then
			p.entitlements[op.item] = true; p.receipts[op.receipt] = true
		end
	elseif op.kind == "Pass" then
		p.entitlements[op.item] = true
	elseif op.kind == "Equip" then
		local item
		for _, candidate in ipairs(catalog) do if candidate.Id == op.item then item = candidate end end
		if item and p.entitlements[item.Id] then p[item.Kind == "Decor" and "decor" or "equipped"] = item.Id end
	end
	for _, item in ipairs(catalog) do
		if type(item.EarnedXP) == "number" and p.xp >= item.EarnedXP then p.entitlements[item.Id] = true end
	end
	return p
end
return Model
