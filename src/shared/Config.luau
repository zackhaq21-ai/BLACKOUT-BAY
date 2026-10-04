--!strict
-- GLASSHOUSE central tuning. Every gameplay number lives here so balance passes
-- never require hunting through systems. Values are provisional until playtested.

local Config = {}

Config.GameName = "GLASSHOUSE"
Config.BuildTag = "m2-first-heist"

Config.Server = {
	MaxPlayers = 12, -- server capacity is a separate decision from crew size
	MaxCrewSize = 5,
	HideoutUnits = 6, -- pier units available for crews on one server
	DevDataPrefix = "dev", -- DataStore scope prefix for development/test data
}

Config.Player = {
	WalkSpeed = 16,
	SprintSpeed = 21,
	SneakSpeed = 9,
	HeavyCarrySpeed = 11, -- carrying a heavy item: no sprint, no climbing
	LightCarrySprintSpeed = 19,
	RespawnSeconds = 4,
	MaxCarry = 1, -- physical bags carried at once
}

Config.Economy = {
	StartingCash = 500,
	MinSplitPercent = 0,
	-- Loot values (fictional currency "Marks")
	Loot = {
		Trinket = { value = 350, weight = "Light", label = "Sea-Glass Trinket" },
		Relic = { value = 900, weight = "Light", label = "Harbour Relic" },
		Jewel = { value = 1800, weight = "Light", label = "Aurora Jewel" },
		Core = { value = 7500, weight = "Heavy", label = "Aurora Core" },
	},
}

Config.Museum = {
	-- Museum (Aurora Exchange) security
	GuardCount = 4,
	GuardWalkSpeed = 12,
	GuardAlertSpeed = 15,
	GuardViewDistance = 38,
	GuardViewAngle = 70, -- degrees, full cone
	CameraViewDistance = 34,
	CameraViewAngle = 60,
	CameraSweepDegrees = 50,
	CameraSweepSeconds = 6,
	SuspicionFillPerSecond = 0.55, -- full exposure fills in ~1.8 s
	SuspicionSneakMultiplier = 0.5,
	SuspicionDecayPerSecond = 0.35,
	SuspiciousThreshold = 0.5,
	AlertThreshold = 1.0,
	LockdownDelaySeconds = 25, -- after Alert, shutters close on the front
	CalmSeconds = 75, -- no reports for this long -> security stands down one level
	PowerCutSeconds = 45, -- junction box disables cameras + lifts shutters
	PowerCutCooldownSeconds = 150,
	CameraSwitchSeconds = 90, -- security-office switch disables cameras
	CodeLength = 4,
	GlassCutSeconds = 4,
	FrontSmashSeconds = 3,
	DrillSeconds = 30,
	DualSwipeWindowSeconds = 4,
	PickpocketSeconds = 2.5,
	RestockDelaySeconds = 90, -- after the vault is emptied or the job cycle expires
	RestockCycleSeconds = 600,
	DetainRange = 6,
	DetainSeconds = 2.2,
	DetainBreakRange = 11,
}

Config.Police = {
	NpcFallbackCount = 10,
	-- Unresolved design: how NPC difficulty is selected. Prototype: fixed config value.
	NpcDifficulty = "Medium", -- "Medium" | "Hard"
	Difficulty = {
		Medium = { cruiserSpeed = 58, viewDistance = 70, cuffSeconds = 2.5, responseSeconds = 14, maxPursuers = 3 },
		Hard = { cruiserSpeed = 66, viewDistance = 90, cuffSeconds = 2.0, responseSeconds = 8, maxPursuers = 5 },
	},
	HeatPerLevel = 100,
	MaxHeat = 300,
	HeatDecayPerSecond = 2.5, -- only while unseen
	UnseenGraceSeconds = 20,
	AlarmHeat = 120, -- being inside the museum when the alarm goes to Alert
	SeenWithLootHeat = 60,
	RamHeat = 40,
	VehicleRecognitionSeconds = 90,
	ArrestRange = 9,
	ArrestBreakRange = 14,
	JailAutoReleaseSeconds = 90,
	JailLockpickSeconds = 25,
	BarricadeHeatLevel = 2, -- cruisers block Lantern Cross at this level
}

Config.Vehicles = {
	Kestrel = { label = "Kestrel", maxSpeed = 70, accel = 32, brake = 60, steer = 0.55, seats = 2, trunk = 2, health = 120, mass = 1 },
	Courier = { label = "Courier Van", maxSpeed = 48, accel = 22, brake = 50, steer = 0.45, seats = 4, trunk = 5, health = 220, mass = 1.4 },
	Commuter = { label = "Commuter", maxSpeed = 54, accel = 24, brake = 50, steer = 0.5, seats = 4, trunk = 1, health = 100, mass = 1 },
	Cruiser = { label = "Police Cruiser", maxSpeed = 64, accel = 30, brake = 60, steer = 0.55, seats = 2, trunk = 0, health = 200, mass = 1.2 },
	RamDamage = 25, -- vehicle health lost when a cruiser rams at pursuit speed
	DisabledSmokeSeconds = 120,
	RespawnSeconds = 45,
}

Config.Mission = {
	StartWindowSeconds = 900, -- a job auto-closes after this long
	CloseGraceSeconds = 25, -- after the last bag is delivered or lost, the job stays open this long for another trip
	ResultsSeconds = 12,
	TutorialHints = true,
}

Config.Net = {
	RequestsPerSecond = 8,
	Burst = 12,
	InteractRange = 12, -- server re-validates proximity
}

Config.Audio = {
	-- Asset ids are intentionally blank: none could be verified in this environment.
	-- Fill with owned/licensed ids. Every cue also has a visual equivalent in the HUD.
	Cues = {
		Pickup = "", Drop = "", Deliver = "", Alarm = "", Suspicious = "", Lockdown = "",
		Smash = "", Drill = "", Keypad = "", Unlock = "", Siren = "", Payout = "", Arrest = "", PowerCut = "",
	},
}

-- Rare-car weekly cycle (logic implemented; not yet in the player flow)
Config.RareCar = {
	WeekAnchorUnix = 0, -- Thursday 1970-01-01 00:00 UTC; weeks counted from here
	WeekSeconds = 7 * 24 * 3600,
	BreakInSeconds = 120,
	Seats = 2,
}

Config.Bounty = {
	MinContribution = 100,
	ClaimCooldownSeconds = 300, -- same target cannot be claimed again for this long
}

return Config
