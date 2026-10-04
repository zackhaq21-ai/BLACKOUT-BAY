--!nonstrict
-- Interface look: dark glass panels with sea-glass and gold accents, readable on small screens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Palette)

local Theme = {
	Panel = Color3.fromRGB(18, 22, 30),
	PanelAlt = Color3.fromRGB(28, 34, 46),
	Stroke = Color3.fromRGB(70, 90, 110),
	Text = Palette.PaleStone,
	Muted = Color3.fromRGB(150, 160, 175),
	Accent = Palette.SeaGlass,
	Gold = Palette.Gold,
	Good = Color3.fromRGB(110, 220, 170),
	Warn = Palette.SecurityAmber,
	Alarm = Palette.SecurityRed,
	Police = Palette.PoliceLight,
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	Body = 16,
	Small = 14,
	Title = 20,
	Big = 28,
	Radius = 10,
	MinButton = 44, -- touch target
	CrewColors = Palette.CrewColors,
}

function Theme.kindColor(kind: string?): Color3
	if kind == "good" then
		return Theme.Good
	elseif kind == "warn" then
		return Theme.Warn
	elseif kind == "alarm" then
		return Theme.Alarm
	end
	return Theme.Accent
end

return Theme
