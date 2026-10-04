-- Native Roblox prototype. No external assets, plugins, or live commerce required.
return {
	Title = "BLACKOUT BAY",
	Subtitle = "THE AURORA EXCHANGE",
	MaxPlayers = 5,
	RunSeconds = 480,
	InteractionDistance = 12,
	DataStoreEnabled = false, -- Local play uses memory. Never enable Studio production-store access.
	DataStoreName = "Glasshouse_Prototype_v1",
	CommerceEnabled = false, -- Requires a separate reviewed release; zero IDs cannot purchase.
	Catalog = {
		{Id = "mint", Name = "Mint courier", Kind = "Suit", EarnedXP = 0, PassId = 0, ProductId = 0, Color = {75, 223, 190}},
		{Id = "amber", Name = "Amber operator", Kind = "Suit", EarnedXP = 200, PassId = 0, ProductId = 0, Color = {255, 187, 89}},
		{Id = "violet", Name = "Violet ghost", Kind = "Suit", EarnedXP = 600, PassId = 0, ProductId = 0, Color = {175, 142, 255}},
		{Id = "prism", Name = "Prism suit", Kind = "Suit", EarnedXP = false, PassId = 0, ProductId = 0, Color = {124, 199, 255}},
		{Id = "moonlamp", Name = "Moon lamp", Kind = "Decor", EarnedXP = 350, PassId = 0, ProductId = 0, Color = {242, 221, 159}},
		{Id = "auroraplant", Name = "Aurora sculpture", Kind = "Decor", EarnedXP = false, PassId = 0, ProductId = 0, Color = {238, 150, 221}},
	},
}
