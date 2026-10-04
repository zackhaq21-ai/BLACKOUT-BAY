--!strict
-- Payout agreements. Shares are integer percents that sum to 100. A share is a promise about
-- delivered value only; it never changes who physically holds a bag.

local SplitLedger = {}

export type Shares = { [string]: number }

function SplitLedger.equal(memberIds: { string }): Shares
	local shares: Shares = {}
	local n = #memberIds
	if n == 0 then
		return shares
	end
	local base = math.floor(100 / n)
	local remainder = 100 - base * n
	for i, id in ipairs(memberIds) do
		shares[id] = base + (if i <= remainder then 1 else 0)
	end
	return shares
end

function SplitLedger.validate(shares: Shares, memberIds: { string }, minPercent: number): (boolean, string?)
	local total = 0
	local seen = {}
	for _, id in ipairs(memberIds) do
		local s = shares[id]
		if type(s) ~= "number" or s ~= s or s ~= math.floor(s) then
			return false, "share for " .. id .. " must be a whole percent"
		end
		if s < minPercent or s > 100 then
			return false, "share for " .. id .. " out of range"
		end
		total += s
		seen[id] = true
	end
	for id in pairs(shares) do
		if not seen[id] then
			return false, "share for non-member " .. id
		end
	end
	if total ~= 100 then
		return false, "shares sum to " .. total .. ", need 100"
	end
	return true, nil
end

-- Distribute a delivered total. Members absent from `present` forfeit their share; it is
-- redistributed in proportion to the remaining shares. Rounding remainder goes to the deliverer.
function SplitLedger.distribute(total: number, shares: Shares, present: { string }, delivererId: string?): { [string]: number }
	local out: { [string]: number } = {}
	if total <= 0 then
		return out
	end
	local presentShareTotal = 0
	for _, id in ipairs(present) do
		presentShareTotal += shares[id] or 0
	end
	if presentShareTotal <= 0 then
		-- everyone with a share is gone: the deliverer keeps it, or the first present member
		local target = delivererId or present[1]
		if target then
			out[target] = total
		end
		return out
	end
	local paid = 0
	for _, id in ipairs(present) do
		local s = shares[id] or 0
		local amount = math.floor(total * s / presentShareTotal)
		out[id] = amount
		paid += amount
	end
	local remainder = total - paid
	if remainder > 0 then
		local target = if delivererId and out[delivererId] ~= nil then delivererId else present[1]
		out[target] = (out[target] or 0) + remainder
	end
	return out
end

return SplitLedger
