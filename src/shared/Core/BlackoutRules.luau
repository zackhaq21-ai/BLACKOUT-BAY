--!strict
-- Pure eligibility and effect rules for the crew-triggered blackout. The server evaluates every field;
-- nothing here reads the client.

export type Actor = { alive: boolean, jailed: boolean, seated: boolean, jobActive: boolean }
export type Cfg = { RequiresActiveJob: boolean, GuardVisionScale: number, PoliceVisionScale: number, DurationSeconds: number, CooldownSeconds: number }

local BlackoutRules = {}

-- Who may cut the grid. Returns nil when allowed, else a short reason.
function BlackoutRules.sabotageRefusal(cfg: Cfg, actor: Actor): string?
	if not actor.alive then
		return "not alive"
	end
	if actor.jailed then
		return "jailed"
	end
	if actor.seated then
		return "on foot only"
	end
	if cfg.RequiresActiveJob and not actor.jobActive then
		return "your crew needs an active job"
	end
	return nil
end

-- Who may reset the grid: anyone alive, on foot, not jailed. Counterplay must stay open to everyone.
function BlackoutRules.resetRefusal(actor: Actor): string?
	if not actor.alive then
		return "not alive"
	end
	if actor.jailed then
		return "jailed"
	end
	if actor.seated then
		return "on foot only"
	end
	return nil
end

-- NPC view distance under a blackout. Clamped so a bad config never blinds or super-sights NPCs.
function BlackoutRules.visionScale(cfg: Cfg, kind: "guard" | "cop", gridDown: boolean): number
	if not gridDown then
		return 1
	end
	local s = if kind == "guard" then cfg.GuardVisionScale else cfg.PoliceVisionScale
	if type(s) ~= "number" or s ~= s then
		return 1
	end
	return math.clamp(s, 0.25, 1)
end

-- Sanity bounds for the event definition (used to build the WorldEventRules def).
function BlackoutRules.definition(cfg: Cfg): { id: string, duration: number, cooldown: number }
	local duration = math.clamp(tonumber(cfg.DurationSeconds) or 60, 15, 180)
	local cooldown = math.clamp(tonumber(cfg.CooldownSeconds) or 300, duration, 1800)
	return { id = "blackout", duration = duration, cooldown = cooldown }
end

return BlackoutRules
