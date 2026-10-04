--!strict
-- Remote contract. The server creates these under ReplicatedStorage.Remotes; the client waits for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"Toast", -- {text, kind}
	"HudState", -- partial HUD state table
	"CrewState", -- crew snapshot
	"MissionState", -- crew job snapshot
	"Results", -- end-of-job summary
	"Detection", -- {level 0..1, dirX, dirZ, source}
	"SecurityLevel", -- {level, label, reason}
	"Heat", -- {heat, level, label}
	"Carry", -- {itemId?, label?, weight?}
	"EventLog", -- {entries}
	"OpenKeypad", -- {targetId}
	"CloseKeypad",
	"Cue", -- {name}
	"Jail", -- {state, secondsLeft}
	"HideoutState", -- {stash, tier, unread, reports?, raidActive}
	"RaidTargets", -- {targets}
	"RaidState", -- raider/defender raid snapshot or {active=false}
	-- client -> server
	"CrewRequest", -- {action, ...}
	"MissionRequest", -- {action, ...}
	"KeypadSubmit", -- {targetId, code}
	"DropCarry",
	"SetSneak", -- bool
	"SetSprint", -- bool
	"HideoutRequest", -- {action, ...}: upgrade, bank, markRead, listTargets, startRaid, crackSafe
}

Net.Functions = {
	"GetBootstrap", -- -> {cash, crew, config subset}
}

function Net.folder(): Folder
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
		if not f then
			local nf = Instance.new("Folder")
			nf.Name = "Remotes"
			nf.Parent = ReplicatedStorage
			f = nf
		end
		return f :: Folder
	end
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	local f = Net.folder()
	if RunService:IsServer() then
		local e = f:FindFirstChild(name)
		if not e then
			local ne = Instance.new("RemoteEvent")
			ne.Name = name
			ne.Parent = f
			e = ne
		end
		return e :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	local f = Net.folder()
	if RunService:IsServer() then
		local e = f:FindFirstChild(name)
		if not e then
			local ne = Instance.new("RemoteFunction")
			ne.Name = name
			ne.Parent = f
			e = ne
		end
		return e :: RemoteFunction
	end
	return f:WaitForChild(name) :: RemoteFunction
end

function Net.createAll()
	for _, name in ipairs(Net.Events) do
		Net.event(name)
	end
	for _, name in ipairs(Net.Functions) do
		Net.func(name)
	end
end

return Net
