--!nonstrict
-- Server-side helpers for talking to clients: toasts, HUD partial state, cues. Keeps remote names in one place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local Comms = {}

function Comms.toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, { text = text, kind = kind or "info" })
end

function Comms.toastAll(text: string, kind: string?)
	Net.event("Toast"):FireAllClients({ text = text, kind = kind or "info" })
end

function Comms.toastMany(players: { Player }, text: string, kind: string?)
	for _, p in ipairs(players) do
		Comms.toast(p, text, kind)
	end
end

function Comms.hud(player: Player, partial: { [string]: any })
	Net.event("HudState"):FireClient(player, partial)
end

function Comms.hudMany(players: { Player }, partial: { [string]: any })
	for _, p in ipairs(players) do
		Comms.hud(p, partial)
	end
end

function Comms.cue(player: Player, name: string)
	Net.event("Cue"):FireClient(player, { name = name })
end

function Comms.cueMany(players: { Player }, name: string)
	for _, p in ipairs(players) do
		Comms.cue(p, name)
	end
end

-- Positional cue: sound and VFX at a world position for everyone within `radius` (default 160 studs)
function Comms.cueAt(name: string, position: Vector3, radius: number?)
	local r = radius or 160
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= r then
			Net.event("Cue"):FireClient(p, { name = name, x = position.X, y = position.Y, z = position.Z })
		end
	end
end

function Comms.cueAll(name: string)
	Net.event("Cue"):FireAllClients({ name = name })
end

function Comms.key(player: Player): string
	return tostring(player.UserId)
end

function Comms.name(player: Player): string
	return player.DisplayName ~= "" and player.DisplayName or player.Name
end

return Comms
