--!strict
-- Server-verified accomplishments (pure evaluation). Each event carries only server-known facts; evaluate
-- returns the ids earned by that event. Exactly-once is enforced by the profile op, not here.

export type Def = { id: string, name: string, blurb: string, standing: number }

local Accomplishments = {}

function Accomplishments.find(defs: { Def }, id: string): Def?
	for _, d in ipairs(defs) do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- events:
--   jobClosed    {headline, delivered, members, arrests, weather, heatLevel, raid}
--   crateFenced  {variant, breachedDuringBlackout}
--   blackoutReset {resetterKey, cutterKey}
--   bountyClaimed {payout}
--   recoveryDone {lost, owed}
--   entries      {front, dock, roof}
function Accomplishments.evaluate(event: string, ctx: any): { string }
	local out = {}
	local function add(id: string)
		table.insert(out, id)
	end
	if type(ctx) ~= "table" then
		return out
	end
	if event == "jobClosed" and not ctx.raid then
		local delivered = type(ctx.delivered) == "number" and ctx.delivered or 0
		if delivered > 0 then
			if ctx.headline == "GHOST CREW" then
				add("glass_ghost")
			end
			if type(ctx.heatLevel) == "number" and ctx.heatLevel >= 2 then
				add("hot_hands")
			end
			if type(ctx.members) == "number" and ctx.members >= 3 and (ctx.arrests or 0) == 0 then
				add("everyone_home")
			end
			if ctx.weather == "Storm" then
				add("storm_runner")
			end
		end
	elseif event == "crateFenced" then
		if ctx.variant == "storm" then
			add("seawall_haul")
		end
		if ctx.breachedDuringBlackout == true then
			add("lights_out_lift")
		end
	elseif event == "blackoutReset" then
		if type(ctx.resetterKey) == "string" and ctx.resetterKey ~= ctx.cutterKey then
			add("grid_warden")
		end
	elseif event == "bountyClaimed" then
		if type(ctx.payout) == "number" and ctx.payout >= 1000 then
			add("price_on_the_mist")
		end
	elseif event == "recoveryDone" then
		if type(ctx.lost) == "number" and type(ctx.owed) == "number" and ctx.owed > 0 and ctx.lost >= ctx.owed then
			add("made_whole")
		end
	elseif event == "entries" then
		if ctx.front == true and ctx.dock == true and ctx.roof == true then
			add("three_doors")
		end
	end
	return out
end

return Accomplishments
