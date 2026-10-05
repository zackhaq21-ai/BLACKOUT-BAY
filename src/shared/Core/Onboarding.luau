--!strict
-- Pure first-session state machine. Steps advance only forward from observed play; nothing here locks
-- progression, so a broken or stale step can never block a player. Hints are short lines for the idle
-- objective panel, never a wall of text.

export type State = { step: number, done: boolean }

local Onboarding = {}

Onboarding.Steps = { "move", "board", "job", "loot", "deliver", "done" }

local HINTS = {
	move = { "Welcome to Blackout Bay", "Walk out of your pier. Shift sprints, C sneaks. The job board is on the back wall." },
	board = { "Open the job board", "Walk up to the board on the back wall of your pier and hold the prompt." },
	job = { "Start the Aurora Exchange job", "Press Start on the board. Your crew code is on the crew card if friends want in." },
	loot = { "Take something", "Inside the museum: cut a case and lift the piece. Guards watch; sneaking keeps you quieter." },
	deliver = { "Get it home", "Carry the bag to the DROP THE HAUL HERE table at your pier. A car from the garage is faster." },
	done = { "Open the job board at your pier", "Run solo now, or share your crew code and run it together." },
}

-- Event -> the minimum step reached after it
local ADVANCE = { moved = 2, boardOpened = 3, jobStarted = 4, lootPicked = 5, delivered = 6, jobPaid = 6 }

function Onboarding.new(): State
	return { step = 1, done = false }
end

-- Validate stored data (malformed -> fresh).
function Onboarding.fromStored(raw: any): State
	if type(raw) ~= "table" then
		return Onboarding.new()
	end
	local step = raw.step
	if type(step) ~= "number" or step ~= step or step < 1 or step > #Onboarding.Steps then
		return Onboarding.new()
	end
	step = math.floor(step)
	return { step = step, done = raw.done == true or step >= #Onboarding.Steps }
end

function Onboarding.stepName(state: State): string
	return Onboarding.Steps[math.clamp(state.step, 1, #Onboarding.Steps)]
end

-- Advance on an observed event; returns (newState, changed). Never moves backward.
function Onboarding.advance(state: State, event: string): (State, boolean)
	local target = ADVANCE[event]
	if not target or state.done then
		return state, false
	end
	if target <= state.step then
		return state, false
	end
	local out = { step = target, done = target >= #Onboarding.Steps }
	return out, true
end

function Onboarding.complete(_state: State): State
	return { step = #Onboarding.Steps, done = true }
end

-- Objective line + detail for the idle HUD at this step.
function Onboarding.hint(state: State): (string, string)
	local h = HINTS[Onboarding.stepName(state)] or HINTS.done
	return h[1], h[2]
end

return Onboarding
