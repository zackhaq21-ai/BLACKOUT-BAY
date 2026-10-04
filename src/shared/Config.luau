--!strict
-- BLACKOUT BAY (internal codename Glasshouse) central tuning. Every gameplay number lives here so balance passes
-- never require hunting through systems. Values are provisional until playtested.

local Config = {}

Config.GameName = "BLACKOUT BAY"
Config.Subtitle = "The Aurora Exchange"
Config.Codename = "Glasshouse" -- internal module/log prefix; player-facing title is Blackout Bay
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
		Bundle = { value = 0, weight = "Light", label = "Stash Bundle" }, -- value set per bundle when minted
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

-- Cosmetics catalog (carried over from the prototype). Preview-only: every PassId/ProductId is 0 and commerce
-- is disabled. Paid looks never change stats, hitboxes, sight or visibility. Earned suits unlock by XP.
type CatalogItem = { Id: string, Name: string, Kind: string, EarnedXP: number | boolean, PassId: number, ProductId: number, Color: { number } }
Config.Commerce = {
	Enabled = false, -- requires a separate reviewed release; zero ids cannot purchase anyway
	Catalog = ({
		{ Id = "mint", Name = "Mint courier", Kind = "Suit", EarnedXP = 0, PassId = 0, ProductId = 0, Color = { 75, 223, 190 } },
		{ Id = "amber", Name = "Amber operator", Kind = "Suit", EarnedXP = 200, PassId = 0, ProductId = 0, Color = { 255, 187, 89 } },
		{ Id = "violet", Name = "Violet ghost", Kind = "Suit", EarnedXP = 600, PassId = 0, ProductId = 0, Color = { 175, 142, 255 } },
		{ Id = "prism", Name = "Prism suit", Kind = "Suit", EarnedXP = false, PassId = 0, ProductId = 0, Color = { 124, 199, 255 } },
	} :: { CatalogItem }),
	-- XP per closed job: base when nothing was delivered, otherwise base + delivered/100 (capped) + quiet bonus
	XpEmpty = 25,
	XpDelivered = 100,
	XpPerHundredDelivered = 1,
	XpDeliveredCap = 200,
	XpGhostBonus = 50,
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

-- Hideout stash and raids. OWNER DECISION (2026-10-04): high stakes. A successful raid exposes the FULL earned
-- stash: no protected floor, no fraction, no per-raid cap. Permanent Robux cosmetics, paid entitlements, XP and
-- unlocks are never touched by raids. Banking (stash -> wallet for a fee) remains the only protected-progression
-- path; it is a separate switch the owner can turn off.
Config.Hideout = {
	PayoutsToStash = true, -- job payouts land in the hideout safe (raidable), not the wallet
	FullExposure = true, -- a cracked safe gives up the entire stash (owner's high-stakes rule)
	BankingEnabled = true, -- owner choice: allow moving stash to the raid-proof wallet at a cost
	BankFeeFraction = 0.10, -- moving stash -> wallet costs this fee (the wallet is never raided)
	BankCooldownSeconds = 120,
	BundleValue = 2500, -- stolen stash is minted as physical bundles of at most this value
	RetainSeconds = 8, -- a bag left unattended inside a hideout for this long is absorbed into its safe
	RaidMaxSeconds = 420, -- a raid lock expires after this long (crash safety)
	RaidCooldownSeconds = 600, -- the same hideout cannot be raided again for this long
	RaidListSize = 8, -- richest offline hideouts shown on the raid board
	RecoveryWindowSeconds = 1200, -- how long a recovery opportunity stays open after a raid
	MaxClues = 12, -- clue trail entries kept per raid report
	MaxReports = 10,
	-- Six tiers. Each tier adds one defence or strengthens one; costs are paid from the stash.
	Tiers = {
		[1] = { cost = 1500, unlock = "Lock", desc = "Safe lock: cracking takes 25 s" },
		[2] = { cost = 3000, unlock = "Alarm", desc = "Alarm: owner and police are notified when the shield or safe is touched" },
		[3] = { cost = 5000, unlock = "Shield", desc = "Bay shield: entry needs the breaker (18 s) or the pier door" },
		[4] = { cost = 8000, unlock = "Lasers", desc = "Laser traps: a trip drops your bag and stuns you 3 s" },
		[5] = { cost = 12000, unlock = "Shield2", desc = "Reinforced shield: breaker takes 30 s and the pier door is barred" },
		[6] = { cost = 18000, unlock = "Lasers2", desc = "Sweeping lasers: beams move; a trip also locks the safe 20 s" },
	},
	SafeCrackSeconds = { [0] = 12, [1] = 25, [2] = 25, [3] = 25, [4] = 32, [5] = 32, [6] = 40 },
	CrackAssistFactor = 0.55, -- a second crew member on the safe multiplies the time by this
	BreakerSeconds = { [3] = 18, [4] = 18, [5] = 30, [6] = 30 },
	PierDoorSeconds = 10, -- cutting the pier back door (barred at tier 5+)
	LaserStunSeconds = 3,
	LaserSafeLockSeconds = 20,
	AlarmHeat = 80, -- police heat for raiders when the alarm trips
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
