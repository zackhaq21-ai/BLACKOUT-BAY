--!strict
-- Bounty held on a target's hideout record (so it persists across servers and while the target is offline).
-- Contributions are debited from the contributor when placed and stack here; a valid claim is paid once.
-- Pure Luau, applied inside UpdateAsync by the store.

export type Contribution = { from: string, amount: number, at: number }
export type Bounty = { total: number, contributions: { Contribution }, lastClaimedAt: number? }

local BountyRecord = {}

function BountyRecord.total(b: Bounty?): number
	return if b then b.total else 0
end

function BountyRecord.place(b: Bounty?, from: string, target: string, amount: number, now: number, minContribution: number): (Bounty?, string?)
	if from == target then
		return nil, "cannot place a bounty on yourself"
	end
	if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < minContribution then
		return nil, "contribution too small"
	end
	local bounty: Bounty = b or { total = 0, contributions = {}, lastClaimedAt = nil }
	bounty.total += amount
	table.insert(bounty.contributions, { from = from, amount = amount, at = now })
	return bounty, nil
end

-- Claim conditions: claimant is not the target, not a contributor (no self-funding), not in the target's crew
-- (collusion), and the target was not paid out within the cooldown (repeat farming). Pays once and clears.
function BountyRecord.claim(b: Bounty?, claimant: string, target: string, sameCrew: boolean, now: number, cooldown: number): (Bounty?, number, string?)
	if not b or b.total <= 0 then
		return b, 0, "no bounty"
	end
	if claimant == target then
		return b, 0, "cannot claim your own bounty"
	end
	if sameCrew then
		return b, 0, "crewmates cannot claim"
	end
	for _, c in ipairs(b.contributions) do
		if c.from == claimant then
			return b, 0, "contributors cannot claim"
		end
	end
	if b.lastClaimedAt and now - b.lastClaimedAt < cooldown then
		return b, 0, "target was claimed recently"
	end
	local payout = b.total
	return { total = 0, contributions = {}, lastClaimedAt = now }, payout, nil
end

-- Refund every contribution (e.g. target permanently gone). Returns refunds by contributor.
function BountyRecord.refund(b: Bounty?): (Bounty?, { [string]: number })
	local out: { [string]: number } = {}
	if not b then
		return b, out
	end
	for _, c in ipairs(b.contributions) do
		out[c.from] = (out[c.from] or 0) + c.amount
	end
	return { total = 0, contributions = {}, lastClaimedAt = b.lastClaimedAt }, out
end

return BountyRecord
