--!strict
-- Contacts (pure): who says what, from authoritative state, limited by Standing unlocks. Lines are short.
-- Intel is deliberately partial: buckets and directions, never exact timers or positions.

export type Contact = { id: string, name: string, role: string, place: string, x: number, z: number, yaw: number, personality: string, requires: string?, intel: string }
export type Ctx = {
	xp: number,
	unlocked: (string) -> boolean,
	variant: { name: string, hint: string }?,
	jobActive: boolean,
	weather: string,
	convoy: { active: boolean, phase: string?, landmark: string?, nextInSeconds: number? },
	grid: { down: boolean, cooldownSeconds: number, durationSeconds: number, lastCutBy: string? },
	richestName: string?,
	rankName: string,
	firstVisit: boolean,
}
export type Line = { speaker: string, role: string, text: string }

local ContactRules = {}

function ContactRules.find(contacts: { Contact }, id: string): Contact?
	for _, c in ipairs(contacts) do
		if c.id == id then
			return c
		end
	end
	return nil
end

local function bucket(seconds: number?): string
	if not seconds then
		return "no word yet"
	end
	if seconds <= 60 then
		return "any minute"
	elseif seconds <= 300 then
		return "within a few minutes"
	elseif seconds <= 900 then
		return "later tonight"
	end
	return "not for a while"
end

function ContactRules.line(contact: Contact, ctx: Ctx): Line
	local function say(text: string): Line
		return { speaker = contact.name, role = contact.role, text = text }
	end
	if ctx.firstVisit then
		if contact.id == "ines" then
			return say("You're the new face at the piers. I keep the books. When the Exchange restocks I hear first. Come back when you've got a crew worth the name.")
		elseif contact.id == "teo" then
			return say("Mind the paint. If you ever need to know when the armoured runs roll, I hear every radio on this deck. Earn some Standing first.")
		elseif contact.id == "priya" then
			return say("That cabinet behind me feeds half the harbour. People keep cutting it. I keep fixing it. Don't be people.")
		end
	end
	if contact.requires and not ctx.unlocked(contact.requires) then
		if contact.id == "teo" then
			return say("Convoy talk is for Operators. Right now you're " .. ctx.rankName .. ". Run a few more jobs and come back.")
		elseif contact.id == "priya" then
			return say("You want to know about the grid? Make a name first. Runners get a straight answer.")
		end
		return say("Not yet.")
	end
	if contact.intel == "museum" then
		if ctx.variant then
			local lead = if ctx.jobActive then "You're already on it. " else ""
			local crews = if ctx.richestName then " Word is " .. ctx.richestName .. " is sitting on the fattest stash on the water." else ""
			return say(lead .. "Tonight at the Exchange: " .. ctx.variant.name .. ". " .. ctx.variant.hint .. crews)
		end
		return say("The Exchange is between stocks. Give it a few minutes.")
	elseif contact.intel == "convoy" then
		if ctx.convoy.active then
			return say("It's rolling now, " .. (ctx.convoy.phase or "moving") .. " near " .. (ctx.convoy.landmark or "the roads") .. ". The escorts see further than you think.")
		end
		local storm = if ctx.weather == "Storm" then " In this storm they'll hug the Seawall and carry one sealed crate. Heavy. Bring a van." else ""
		return say("Next armoured run: " .. bucket(ctx.convoy.nextInSeconds) .. "." .. storm)
	elseif contact.intel == "grid" then
		if ctx.grid.down then
			return say("Grid's down. " .. (if ctx.grid.lastCutBy then ctx.grid.lastCutBy .. " did that." else "Someone did that.") .. " Reset panel's on the back of the cabinet. I'd be grateful.")
		end
		if ctx.grid.cooldownSeconds > 0 then
			return say("Breakers are still warm. Nobody's cutting anything for about " .. math.ceil(ctx.grid.cooldownSeconds / 60) .. " minute" .. (if ctx.grid.cooldownSeconds > 90 then "s" else "") .. ".")
		end
		local storm = if ctx.weather == "Storm" then " Storm like this, the whole harbour's one fault away." else ""
		return say("Cut it and you get " .. math.floor(ctx.grid.durationSeconds) .. " seconds of dark. Cameras die, pier shields drop, the lighthouse and the station keep their own power." .. storm)
	end
	return say(contact.personality)
end

return ContactRules
