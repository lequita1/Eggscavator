-- Single source of truth for the game's look. Everything reads from here.
local Theme = {
	Colors = {
		Panel = Color3.fromRGB(30, 30, 40),
		Text = Color3.new(1, 1, 1),
		TextMuted = Color3.fromRGB(150, 150, 160),
		Gold = Color3.fromRGB(255, 190, 40),
		Primary = Color3.fromRGB(70, 190, 100),
		Secondary = Color3.fromRGB(80, 85, 105),
		Danger = Color3.fromRGB(220, 70, 70),
		Disabled = Color3.fromRGB(60, 60, 70),
	},
	Fonts = {
		Bold = Enum.Font.GothamBold,
		Regular = Enum.Font.Gotham,
	},

	TextSizes = {
		Title = 20,
		Body = 16,
		Small = 13,
	},

	Radius = UDim.new(0, 8),
}

---------------------------------------------------------------------
-- Palette presets. Change PRESET to "DigSite" or "Cave" and press Play to compare.
-- Rule of thumb: dark stone panels (60%), sandstone and cream surfaces and text (30%),
-- yolk gold for the ONE thing that matters on screen (10%). Green = money/success only.
-- Red = danger/full only. The names below are kept from the old theme so nothing breaks.
---------------------------------------------------------------------
local PRESET = "DigSite"

local PALETTES = {
	DigSite = {
		Ink = Color3.fromRGB(33, 22, 17), -- outlines (warm brown-black)
		Cream = Color3.fromRGB(255, 243, 216),
		Paper = Color3.fromRGB(232, 208, 168), -- sandstone pages
		PaperDark = Color3.fromRGB(196, 166, 120),
		PaperLine = Color3.fromRGB(150, 116, 78),
		Iron = Color3.fromRGB(84, 62, 50), -- main panels (umber stone)
		IronLight = Color3.fromRGB(126, 96, 76),
		IronDark = Color3.fromRGB(48, 35, 29), -- recessed wells
		Slate = Color3.fromRGB(56, 94, 100), -- verdigris teal (secondary surface)
		Amber = Color3.fromRGB(255, 196, 48), -- yolk gold (primary accent)
		AmberDark = Color3.fromRGB(196, 120, 20),
		Clay = Color3.fromRGB(214, 110, 72), -- terracotta
		ClayDark = Color3.fromRGB(148, 68, 44),
		Green = Color3.fromRGB(104, 192, 100),
		GreenDark = Color3.fromRGB(50, 122, 62),
		Red = Color3.fromRGB(224, 80, 72),
		RedDark = Color3.fromRGB(140, 44, 44),
		BlueInk = Color3.fromRGB(40, 92, 98), -- headings on sandstone
		MoneyGreen = Color3.fromRGB(126, 232, 120),
	},
	Cave = {
		Ink = Color3.fromRGB(12, 22, 26),
		Cream = Color3.fromRGB(240, 250, 244),
		Paper = Color3.fromRGB(226, 222, 200), -- bone pages
		PaperDark = Color3.fromRGB(184, 180, 154),
		PaperLine = Color3.fromRGB(130, 128, 104),
		Iron = Color3.fromRGB(36, 68, 74),
		IronLight = Color3.fromRGB(66, 108, 114),
		IronDark = Color3.fromRGB(20, 40, 46),
		Slate = Color3.fromRGB(150, 104, 72), -- copper
		Amber = Color3.fromRGB(255, 200, 64),
		AmberDark = Color3.fromRGB(196, 124, 24),
		Clay = Color3.fromRGB(232, 120, 88),
		ClayDark = Color3.fromRGB(158, 72, 52),
		Green = Color3.fromRGB(92, 200, 132),
		GreenDark = Color3.fromRGB(40, 124, 84),
		Red = Color3.fromRGB(232, 84, 84),
		RedDark = Color3.fromRGB(146, 44, 52),
		BlueInk = Color3.fromRGB(30, 90, 96),
		MoneyGreen = Color3.fromRGB(120, 240, 150),
	},
}

for name, color in PALETTES[PRESET] or PALETTES.DigSite do
	Theme.Colors[name] = color
end

-- Display font is used for big outlined lettering. To change the personality of the whole
-- UI, swap this one line: try Enum.Font.LuckiestGuy, Enum.Font.Bangers or Enum.Font.SpecialElite.
-- (Wider fonts like LuckiestGuy can overflow the hotbar names and chips, so check after swapping.)
Theme.Fonts.Display = Enum.Font.FredokaOne
Theme.Fonts.Body = Enum.Font.GothamBold

-- Uploaded icon IDs. Empty = symbol fallback.
Theme.Icons = {
	-- HUD
	Coin = "rbxassetid://112527424641773",
	Sell = "rbxassetid://113670932433787",
	Shop = "rbxassetid://131067776680688",
	Upgrades = "rbxassetid://84022593756521",

	-- Upgrade tracks (Journal)
	Hold = "rbxassetid://77711384212627",
	Speed = "rbxassetid://111626386116298",
	Grip = "rbxassetid://76846624629741",
	Reach = "rbxassetid://114800540137875",

	-- Tools (hotbar). The key must match the tool's Id.
	IcePick = "rbxassetid://103562071629822",
	Pickaxe = "rbxassetid://98730112128829",
	Drill = "rbxassetid://93732755551984",
	ClimbRig = "rbxassetid://104015814374088",
	Brush = "rbxassetid://93221031336090",
	Vacuum = "rbxassetid://79791759298971",
}

return Theme