--!nonstrict
-- GLASSHOUSE server entry point: build the world, create remotes, initialise services in dependency order.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local WorldBuilder = require(script.Builders.WorldBuilder)

Players.RespawnTime = Config.Player.RespawnSeconds
Players.CharacterAutoLoads = true

local started = os.clock()
local world = WorldBuilder.build()
Net.createAll()

local services = {}
local ctx = { world = world, services = services, config = Config }

local ORDER = { "EventLog", "Data", "Economy", "Commerce", "Cosmetics", "Movement", "HideoutStore", "Raid", "Hideout", "Crew", "Loot", "Security", "Mission", "Vehicle", "Police", "Interaction" }
for _, name in ipairs(ORDER) do
	services[name] = require(script.Services[if name == "HideoutStore" then name else name .. "Service"])
end
for _, name in ipairs(ORDER) do
	services[name].init(ctx)
end
for _, name in ipairs(ORDER) do
	services[name].start()
end
require(script.ServerContext).ctx = ctx
script:SetAttribute("Ready", true)

print(string.format("[GLASSHOUSE] %s ready in %.2f s (%d parts)", Config.BuildTag, os.clock() - started, #world.root:GetDescendants()))
