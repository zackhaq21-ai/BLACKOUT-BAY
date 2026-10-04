--!strict
-- Token bucket per key. Used by the server to bound client request rates.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: { rate: number, burst: number, buckets: { [string]: { tokens: number, at: number } } }, RateLimiter))

function RateLimiter.new(ratePerSecond: number, burst: number): RateLimiter
	return setmetatable({ rate = ratePerSecond, burst = burst, buckets = {} }, RateLimiter)
end

function RateLimiter.allow(self: RateLimiter, key: string, now: number, cost: number?): boolean
	local c = cost or 1
	local b = self.buckets[key]
	if not b then
		b = { tokens = self.burst, at = now }
		self.buckets[key] = b
	end
	b.tokens = math.min(self.burst, b.tokens + (now - b.at) * self.rate)
	b.at = now
	if b.tokens >= c then
		b.tokens -= c
		return true
	end
	return false
end

function RateLimiter.forget(self: RateLimiter, key: string)
	self.buckets[key] = nil
end

return RateLimiter
