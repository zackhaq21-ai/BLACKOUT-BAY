--!strict
-- Bounties funded with earned currency. Contributions are deducted by the caller when placed,
-- stack on the target, are held in the pool, and pay out exactly once to a valid claim.

export type Cfg = { minContribution: number, claimCooldownSeconds: number }

export type Contribution = { from: string, amount: number, at: number }

export type Bounty = { target: string, total: number, contributions: { Contribution }, lastClaimedAt: number? }

local BountyPool = {}
BountyPool.__index = BountyPool

export type BountyPool = typeof(setmetatable({} :: { cfg: Cfg, bounties: { [string]: Bounty }, claimsPaid: number }, BountyPool))

function BountyPool.new(cfg: Cfg): BountyPool
	return setmetatable({ cfg = cfg, bounties = {}, claimsPaid = 0 }, BountyPool)
end

function BountyPool.place(self: BountyPool, from: string, target: string, amount: number, now: number): (boolean, string?)
	if from == target then
		return false, "cannot place a bounty on yourself"
	end
	if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < self.cfg.minContribution then
		return false, "contribution too small"
	end
	local b = self.bounties[target]
	if not b then
		local nb: Bounty = { target = target, total = 0, contributions = {}, lastClaimedAt = nil }
		self.bounties[target] = nb
		b = nb
	end
	b.total += amount
	table.insert(b.contributions, { from = from, amount = amount, at = now })
	return true, nil
end

function BountyPool.totalOn(self: BountyPool, target: string): number
	local b = self.bounties[target]
	return if b then b.total else 0
end

export type WantedRow = { target: string, total: number }

function BountyPool.wanted(self: BountyPool): { WantedRow }
	local out: { WantedRow } = {}
	for target, b in pairs(self.bounties) do
		if b.total > 0 then
			table.insert(out, { target = target, total = b.total })
		end
	end
	table.sort(out, function(a: WantedRow, b: WantedRow)
		return a.total > b.total
	end)
	return out
end

-- Claim conditions: claimant is not the target, is not a contributor (no self-funding),
-- is not in the target's crew (collusion), and the target was not claimed within the cooldown
-- (repeat farming). Pays once and clears the pool for that target.
function BountyPool.claim(self: BountyPool, claimant: string, target: string, sameCrew: boolean, now: number): (boolean, string?, number)
	local b = self.bounties[target]
	if not b or b.total <= 0 then
		return false, "no bounty", 0
	end
	if claimant == target then
		return false, "cannot claim your own bounty", 0
	end
	if sameCrew then
		return false, "crewmates cannot claim", 0
	end
	for _, c in ipairs(b.contributions) do
		if c.from == claimant then
			return false, "contributors cannot claim", 0
		end
	end
	if b.lastClaimedAt and now - b.lastClaimedAt < self.cfg.claimCooldownSeconds then
		return false, "target claimed recently", 0
	end
	local payout = b.total
	b.total = 0
	b.contributions = {}
	b.lastClaimedAt = now
	self.claimsPaid += 1
	return true, nil, payout
end

-- Refund every contribution on a target (e.g. target left permanently). Returns refunds by contributor.
function BountyPool.refund(self: BountyPool, target: string): { [string]: number }
	local b = self.bounties[target]
	local out: { [string]: number } = {}
	if not b then
		return out
	end
	for _, c in ipairs(b.contributions) do
		out[c.from] = (out[c.from] or 0) + c.amount
	end
	b.total = 0
	b.contributions = {}
	return out
end

return BountyPool
