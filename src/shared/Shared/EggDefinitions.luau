local Util = require(script.Parent.Util)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Layers, outermost first. Hardness = tool Power needed. HP = per patch. Value in cents.
local function layer(name, color, glow, material, hardness, hp, pieceId, pieceName, value, message)
	return {
		Name = name,
		Color = color,
		Glow = glow,
		Material = material,
		Hardness = hardness,
		HP = hp,
		PieceItem = pieceId,
		PieceName = pieceName,
		Value = value,
		Message = message, -- shown when this layer is first reached (nil for layer 1)
	}
end

local EggDefinitions = {
	Stonehatch = {
		DisplayName = "Stonehatch Egg",
		Tier = 1,
		RespawnTime = 20, -- unused: one server is one match

		-- Display scale for the durability bar (UI.Store). Durability is DERIVED from patch progress.
		MaxDurability = 300,
		StageThresholds = { 0.82, 0.64, 0.46, 0.29, 0.13 }, -- on the derived durability fraction

		-- Patches (read from ReplicatedStorage.EggPatches.Stonehatch)
		LayerSweep = 0.98, -- when this fraction of patches is past a layer, the rest of that layer breaks through
		LayerStep = 0.05, -- layer k is scaled by 1 - (k-1) * LayerStep about the Shell center
		OpenToHatch = 1.0,
		SkipBands = { 15 }, -- bands nobody can reach start already open (11 = the cap on the ground)
		Layers = {
			layer("Weathered Crust", rgb(128, 116, 104), rgb(170, 115, 80), Enum.Material.Slate, 1, 30, "CrustPlate", "Crust Plate", 8, nil),
			layer("Clay Wrap", rgb(170, 115, 80), rgb(235, 150, 40), Enum.Material.Mud, 1, 40, "ClayPlate", "Clay Plate", 14, "Clay Wrap! The stone gives way to old mud."),
			layer("Amber Resin", rgb(235, 150, 40), rgb(225, 205, 165), Enum.Material.Glass, 2, 58, "AmberPlate", "Amber Plate", 30, "Amber Resin! Warm and glowing."),
			layer("Fossil Bed", rgb(225, 205, 165), rgb(130, 100, 230), Enum.Material.Sandstone, 2, 75, "FossilPlate", "Fossil Plate", 55, "The Fossil Bed! Teeth and claws ahead."),
			layer("Crystal Lining", rgb(130, 100, 230), rgb(255, 200, 90), Enum.Material.Ice, 3, 108, "CrystalPlate", "Crystal Plate", 110, "Crystal Lining! Something is humming..."),
			layer("Sunstone Membrane", rgb(255, 190, 80), rgb(255, 235, 170), Enum.Material.Neon, 3, 138, "SunstonePlate", "Sunstone Plate", 220, "The Sunstone Membrane! Something is alive in there."),
		},

		BreakShakeDuration = 0.6,

		-- What hatches from this egg (shown on the cutscene card)
		Hatchling = { Species = "Triceratops Hatchling", Rarity = "Rare" },
	},
}

for eggId, definition in EggDefinitions do
	definition.Id = eggId
end

return Util.DeepFreeze(EggDefinitions)