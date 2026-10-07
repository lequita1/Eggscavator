local Util = require(script.Parent.Util)

-- The museum curator at the sell station. Change the name and lines freely.
-- Keep lines short (about 38 characters): they appear in a toast.
local Curator = {
	Name = "Prof. Yanah",

	-- Reactions to the best item sold (only used for Rare and better)
	ByItem = {
		EggshellFlake = "Eggshell! Humble, but it adds up.",
		FernFossil = "A fern from before the mountains.",
		PetrifiedSeed = "A seed turned to stone. Patient!",
		AmberDrop = "Warm amber! The dig is paying off.",
		DragonflyAmber = "A dragonfly frozen mid-flight!",
		FossilTooth = "A tooth! Not a vegetarian, that one.",
		HookedClaw = "That claw could open a door. Splendid!",
		GlowCrystal = "It's humming... please don't drop it.",
		SunstoneYolk = "A Sunstone Yolk! I need to sit down.",
	},

	-- Used when nothing special was sold, chosen by the total
	Small = { "Every flake counts. Dig on!", "Steady work. Keep digging!" },
	Medium = { "A fine haul! The museum thanks you.", "Now we're getting somewhere!" },
	Large = { "Now THAT is a haul!", "Marvelous! Simply marvelous!" },
}

local RARE_RANK = 3 -- rarity Order of Rare

-- Picks the line for a sale. bestItemId may be nil. bestRank is the rarity Order of the best item.
function Curator.PickLine(bestItemId: string?, bestRank: number, totalCents: number): string
	if bestItemId and bestRank >= RARE_RANK and Curator.ByItem[bestItemId] then
		return Curator.ByItem[bestItemId]
	end
	local pool = if totalCents >= 1500 then Curator.Large elseif totalCents >= 400 then Curator.Medium else Curator.Small
	return pool[math.random(1, #pool)]
end

return Util.DeepFreeze(Curator)