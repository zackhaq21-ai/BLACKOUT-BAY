--!nonstrict
-- Contacts: three original people placed in the world with a Talk prompt. Lines come from ContactRules with
-- authoritative state (variant, convoy, grid, Standing). No client input beyond the prompt itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Standing = require(ReplicatedStorage.Shared.Core.Standing)
local ContactRules = require(ReplicatedStorage.Shared.Core.ContactRules)
local Rig = require(script.Parent.Parent.NPC.Rig)
local Builder = require(script.Parent.Parent.Builders.Builder)

local ContactService = {}
ContactService.ctx = nil :: any

local rigs = {}
local visited: { [Player]: { [string]: boolean } } = {}

local function context(player: Player)
	local S = ContactService.ctx.services
	local xp = S.Progression.xp(player)
	local crew = S.Crew.crewOf(player)
	local variant = S.Security.variant()
	local convoy = S.Convoy.snapshot()
	local richest = S.HideoutStore.richest(1)
	local richestName = richest[1] and richest[1].userId ~= player.UserId and S.HideoutStore.nameOf(richest[1].userId) or nil
	return {
		xp = xp,
		unlocked = function(key)
			return Standing.unlocked(Config.Progression, xp, key)
		end,
		variant = variant and { name = variant.name, hint = variant.hint } or false,
		jobActive = crew ~= nil and S.Mission.isJobActive(crew.id),
		weather = S.Environment.state(),
		convoy = { active = convoy.active == true, phase = convoy.phase, landmark = convoy.landmark, nextInSeconds = S.Convoy.secondsUntilNext() },
		grid = S.Blackout.intel(),
		richestName = richestName,
		rankName = Standing.rankFor(Config.Progression, xp).name,
		firstVisit = false,
	}
end

function ContactService.talk(player: Player, contactId: string)
	local contact = ContactRules.find(Config.Contacts, contactId)
	if not contact then
		return nil
	end
	local ctx = context(player)
	visited[player] = visited[player] or {}
	ctx.firstVisit = not visited[player][contactId]
	visited[player][contactId] = true
	local line = ContactRules.line(contact, ctx)
	Net.event("Dialogue"):FireClient(player, { speaker = line.speaker, role = line.role, text = line.text })
	ContactService.ctx.services.Telemetry.track("contact_talk", { id = contactId, first = ctx.firstVisit })
	return line
end

function ContactService.onTalk(player: Player, prompt: ProximityPrompt)
	ContactService.talk(player, tostring(prompt:GetAttribute("ContactId")))
end

function ContactService.init(ctx)
	ContactService.ctx = ctx
end

function ContactService.start()
	local world = ContactService.ctx.world
	local colors = { ines = Palette.SeaGlassDeep, teo = Palette.Rust, priya = Palette.SecurityAmber }
	for _, c in ipairs(Config.Contacts) do
		local cf = CFrame.new(c.x, 3, c.z) * CFrame.Angles(0, math.rad(c.yaw), 0)
		local model = Rig.create("Contact_" .. c.id, colors[c.id] or Palette.Industrial, c.name .. "\n" .. c.role, world.npcFolder, cf)
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if root then
			local anchor = root :: BasePart
			anchor.Anchored = true
			Builder.prompt(anchor, "Talk", c.name .. " · " .. c.role, 0, "Contact", { ContactId = c.id })
		end
		rigs[c.id] = model
	end
	Players.PlayerRemoving:Connect(function(player)
		visited[player] = nil
	end)
end

return ContactService
