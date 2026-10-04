--!strict
-- Explicit rules for how much of a stash a raid can take (all of it, by owner decision), what tiers cost and
-- unlock, and how stolen value is minted as physical bundles. Pure Luau, unit-tested.

export type Cfg = {
	FullExposure: boolean,
	BankFeeFraction: number,
	BundleValue: number,
	Tiers: { [number]: { cost: number, unlock: string, desc: string } },
	SafeCrackSeconds: { [number]: number },
	CrackAssistFactor: number,
	BreakerSeconds: { [number]: number },
}

local StashRules = {}

-- Amount a successful raid takes from a stash of `stash`. Owner's rule: the whole earned stash.
-- The function stays as the single place to change if that decision ever changes.
function StashRules.exposed(cfg: Cfg, stash: number): number
	if cfg.FullExposure then
		return math.max(0, math.floor(stash))
	end
	return math.max(0, math.floor(stash))
end

-- Split a stolen amount into bundle values (largest first, none above BundleValue).
function StashRules.bundles(cfg: Cfg, amount: number): { number }
	local out = {}
	local left = amount
	while left > 0 do
		local v = math.min(cfg.BundleValue, left)
		table.insert(out, v)
		left -= v
	end
	return out
end

function StashRules.maxTier(cfg: Cfg): number
	local n = 0
	while cfg.Tiers[n + 1] do
		n += 1
	end
	return n
end

function StashRules.upgradeCost(cfg: Cfg, currentTier: number): number?
	local t = cfg.Tiers[currentTier + 1]
	return t and t.cost or nil
end

-- Which defences a tier provides.
function StashRules.defences(cfg: Cfg, tier: number): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for level = 1, tier do
		local t = cfg.Tiers[level]
		if t then
			out[t.unlock] = true
		end
	end
	return out
end

function StashRules.safeCrackSeconds(cfg: Cfg, tier: number, crackers: number): number
	local base = cfg.SafeCrackSeconds[math.clamp(tier, 0, StashRules.maxTier(cfg))] or 20
	if crackers >= 2 then
		return math.ceil(base * cfg.CrackAssistFactor)
	end
	return base
end

function StashRules.breakerSeconds(cfg: Cfg, tier: number): number?
	return cfg.BreakerSeconds[tier]
end

-- Banking: moves stash into the wallet minus the fee. Returns (toWallet, fee).
function StashRules.bank(cfg: Cfg, amount: number): (number, number)
	local fee = math.floor(amount * cfg.BankFeeFraction)
	return amount - fee, fee
end

return StashRules
