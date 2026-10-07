local Util = require(script.Parent.Util)

-- Value is in CENTS. Layer is where the item is found (used later for sets).
local ItemDefinitions = {
	EggshellFlake = {
		DisplayName = "Eggshell Flake",
		Description = "A chip of the stone-hard crust. Humble, but it adds up.",
		Rarity = "Common",
		Value = 5,
		SortOrder = 1,
		Layer = "Crust",
		Icon = "",
	},
	FernFossil = {
		DisplayName = "Fern Fossil",
		Description = "A leaf pressed into stone before the mountains were mountains.",
		Rarity = "Common",
		Value = 8,
		SortOrder = 2,
		Layer = "Crust",
		Icon = "",
	},
	PetrifiedSeed = {
		DisplayName = "Petrified Seed",
		Description = "A seed turned to stone. It never got to sprout.",
		Rarity = "Uncommon",
		Value = 15,
		SortOrder = 3,
		Layer = "Crust",
		Icon = "",
	},
	AmberDrop = {
		DisplayName = "Amber Drop",
		Description = "Warm, glassy resin from the nest. Smells faintly of pine.",
		Rarity = "Uncommon",
		Value = 18,
		SortOrder = 4,
		Layer = "Mid nest",
		Icon = "",
	},
	DragonflyAmber = {
		DisplayName = "Dragonfly Amber",
		Description = "Something small is trapped inside, frozen mid-flight.",
		Rarity = "Rare",
		Value = 50,
		SortOrder = 5,
		Layer = "Mid nest",
		Icon = "",
	},
	FossilTooth = {
		DisplayName = "Fossil Tooth",
		Description = "Whoever owned this was definitely not a vegetarian.",
		Rarity = "Rare",
		Value = 65,
		SortOrder = 6,
		Layer = "Mid nest",
		Icon = "",
	},
	HookedClaw = {
		DisplayName = "Hooked Claw",
		Description = "Curved, sharp, and still impressively pointy.",
		Rarity = "Epic",
		Value = 200,
		SortOrder = 7,
		Layer = "Deep core",
		Icon = "",
	},
	GlowCrystal = {
		DisplayName = "Glow Crystal",
		Description = "It hums softly. Something deep in the egg is warm.",
		Rarity = "Epic",
		Value = 260,
		SortOrder = 8,
		Layer = "Deep core",
		Icon = "",
	},
	SunstoneYolk = {
		DisplayName = "Sunstone Yolk",
		Description = "A golden stone shaped like a heartbeat. Warm to the touch.",
		Rarity = "Legendary",
		Value = 800,
		SortOrder = 9,
		Layer = "Deep core",
		Icon = "",
	},
}

-- Plates: the pieces that fall when a patch layer breaks (Phase 6). Values in cents.
local function plate(name, description, rarity, value, order, layer)
	return {
		DisplayName = name,
		Description = description,
		Rarity = rarity,
		Value = value,
		SortOrder = order,
		Layer = layer,
		Icon = "",
	}
end
ItemDefinitions.CrustPlate = plate("Crust Plate", "A slab of weathered stone from the egg's outer skin.", "Common", 8, 10, "Weathered Crust")
ItemDefinitions.ClayPlate = plate("Clay Plate", "Old dried mud, still faintly warm.", "Common", 14, 11, "Clay Wrap")
ItemDefinitions.AmberPlate = plate("Amber Plate", "A glowing plate of ancient resin.", "Uncommon", 30, 12, "Amber Resin")
ItemDefinitions.FossilPlate = plate("Fossil Plate", "Packed with teeth and claw marks.", "Rare", 55, 13, "Fossil Bed")
ItemDefinitions.CrystalPlate = plate("Crystal Plate", "It hums when you hold it.", "Epic", 110, 14, "Crystal Lining")
ItemDefinitions.SunstonePlate = plate("Sunstone Plate", "A piece of the egg's living membrane. Warm as a heartbeat.", "Legendary", 220, 15, "Sunstone Membrane")

for itemId, definition in ItemDefinitions do
	definition.Id = itemId
end

return Util.DeepFreeze(ItemDefinitions)