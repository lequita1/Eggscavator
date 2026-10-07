local Util = require(script.Parent.Util)

-- ECONOMY (Phase 11). All money is in CENTS.
-- Every match starts from zero. ShopService pays by player count (x0.25, x0.5, x0.75, x1 for 1 to 4 players),
-- so each player earns about $265 per match (a model). The whole ladder (tools, upgrades, bags, pickup gear)
-- costs about $192.60, so everyone can max everything, but only by playing nearly the whole match.
-- The Pouch is cheap on purpose: a solo player (x0.25 pay) should afford it at about 2 minutes.
local GameConfig = {
	Player = {
		StartingMoney = 0,
		StartingToolId = "IcePick", -- must exist in ToolDefinitions
	},

	Inventory = {
		StartingCapacity = 5, -- bare hands
		StartingName = "Bare Hands",
		-- Bought in order. Each entry is the NEW total capacity and its price in CENTS.
		CapacityUpgrades = {
			{ Name = "Pouch", Capacity = 15, Price = 60 },
			{ Name = "Sack", Capacity = 40, Price = 300 },
			{ Name = "Backpack", Capacity = 100, Price = 1100 },
			{ Name = "Wheelbarrow", Capacity = 250, Price = 2200 },
		},
	},

	-- Pickup gear. Reach = how far you can click a piece from. Sweep = a click also takes every piece
	-- within this many studs of the clicked one. Auto = the vacuum pulls in pieces within this many studs.
	Pickup = {
		Start = { Name = "Hand Pickup", Reach = 14, Sweep = 0, Auto = 0 },
		Upgrades = {
			{ Id = "Brush", Name = "Brush", Price = 600, Reach = 16, Sweep = 7, Interval = 0.35, Hold = false, Description = "Click to sweep up pieces around your aim." },
			{ Id = "Vacuum", Name = "Vacuum", Price = 1600, Reach = 20, Sweep = 10, Interval = 0.15, Hold = true, Description = "Hold to suck up pieces around your aim." },
		},
	},

	-- Climb Rig gear (bought in order, like the pickup gear). Tier 1 is the rig itself and unlocks ladder level 1;
	-- every later tier unlocks the next ladder level. Prices are CENTS. Modelled so the whole ladder
	-- (tools, upgrades, bags, pickup gear and this) is bought by about minute 19 of a 20 minute match.
	Climb = {
		Name = "Ladder",
		Tiers = {
			{ Name = "Ladder", Price = 200, Levels = 1, Description = "Put up a ladder with one deck, 10 studs up." },
			{ Name = "Ladder Level 2", Price = 500, Levels = 2, Description = "Add a second deck, 20 studs up." },
			{ Name = "Ladder Level 3", Price = 900, Levels = 3, Description = "Add a third deck, 30 studs up." },
			{ Name = "Ladder Level 4", Price = 1400, Levels = 4, Description = "Add a fourth deck, 40 studs up." },
			{ Name = "Ladder Level 5", Price = 2000, Levels = 5, Description = "Add the top deck, 48 studs up." },
		},
	},

	-- Max distance (studs) from the player's character to use these things.
	Interaction = {
		CollectRange = 14,
		SellRange = 16,
		ShopRange = 16,
	},

	Combat = {
		-- How far (studs) a reported hit position may be from the patch's surface.
		HitPositionTolerance = 6,
		-- Server accepts a hit if enough time passed: AttackInterval * this value.
		-- Below 1 so normal network jitter doesn't reject honest players.
		IntervalTolerance = 0.8,
	},

	Core = {
		PickupRange = 26, -- studs from the Core's center (it is 16 studs wide)
		DeliverRange = 24, -- studs from the delivery pad
		BaseWalkSpeed = 16,
		CarrySpeedMultiplier = 0.85, -- everyone walks a bit slower while carrying
	},

	Round = {
		ResultsTime = 15, -- seconds the results stay up before players return to the lobby
	},

	Mother = {
		EscortHeight = 4.2, -- studs: the hatchling held in the player's arms
		FieldHeight = 7, -- studs: the hatchling that replaces the orb on the field
		ReleaseHeight = 8, -- studs: the hatchling in the Release scene
		FootstepFadeInTime = 18,
		ReleaseCutsceneTime = 23, -- must be at least 1.5s longer than CFG.Total in ReleaseCutscene (21.2)
	},

	-- Visual settings (client-only, no gameplay effect). Only MaxCrackSegments is used by EggView now.
	FX = {
		SurfaceScale = 1,
		CrackBase = 8,
		CracksPerStage = 8,
		ChunkCount = 8,
		MaxScars = 70,
		MaxLooseChunks = 40,
		MaxCrackSegments = 300, -- crack line pieces alive at once (oldest are recycled)
		SpeckleCount = 45,
		PatchCount = 12,
	},

	-- Minimum seconds between calls to each remote, per player.
	RateLimits = {
		HitEgg = 0.05,
		CollectDrop = 0.1, -- piece pickups (PieceService)
		SellAll = 0.5,
		BuyTool = 0.5,
		EquipTool = 0.3,
		BuyCapacityUpgrade = 0.5,
		BuyUpgrade = 0.3,
	},

	Rarities = {
		Common = { Order = 1, Color = Color3.fromRGB(190, 190, 190) },
		Uncommon = { Order = 2, Color = Color3.fromRGB(100, 200, 100) },
		Rare = { Order = 3, Color = Color3.fromRGB(70, 140, 255) },
		Epic = { Order = 4, Color = Color3.fromRGB(170, 90, 255) },
		Legendary = { Order = 5, Color = Color3.fromRGB(255, 190, 40) },
		Mythic = { Order = 6, Color = Color3.fromRGB(255, 70, 110) }, -- reserved for later eggs
	},

	PlaceIds = {
		Lobby = 132933976337578,
		Game = 118082309967105,
	},
}

return Util.DeepFreeze(GameConfig)