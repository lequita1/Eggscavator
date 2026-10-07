local Util = require(script.Parent.Util)

-- DPS = Damage / AttackInterval (before upgrades)
-- Power = the hardest layer the tool can break (layer Hardness <= tool Power). Server-enforced.
-- Upgrade Kinds:
--   Hold  = unlocks hold-to-hit (1 level)
--   Speed = each level cuts AttackInterval by PerLevel (0.07 = 7%)
--   Grip  = each level adds DamagePerLevel damage per hit
--   Reach = each level adds RangePerLevel studs of range
-- Prices[i] = cents to buy level i. The number of prices is the number of levels.
-- Phase 11 pricing: every match starts from zero and sell pay depends on the player count (see ShopService),
-- so each player earns about $265 per match. The whole ladder (tools, upgrades, bags, pickup gear) is about $196.
local ToolDefinitions = {
	IcePick = {
		DisplayName = "Ice Pick",
		Description = "Fast and light. Chips away at the outer layers.",
		ShopOrder = 1,
		Price = 0, -- free starter tool
		ToolType = "Precision",
		Power = 1,
		Damage = 4,
		AttackInterval = 0.2, -- seconds between hits
		Range = 10, -- studs

		UpgradeOrder = { "Hold", "Speed", "Grip" },
		Upgrades = {
			Hold = {
				DisplayName = "Hold",
				Description = "Hold the button to keep chipping.",
				Kind = "Hold",
				Prices = { 200 },
			},
			Speed = {
				DisplayName = "Speed",
				Description = "Strike faster.",
				Kind = "Speed",
				PerLevel = 0.07,
				Prices = { 300, 400 },
			},
			Grip = {
				DisplayName = "Grip",
				Description = "Hit harder: +4 damage per hit.",
				Kind = "Grip",
				DamagePerLevel = 4,
				Prices = { 300, 600 },
			},
		},
	},

	Pickaxe = {
		DisplayName = "Pickaxe",
		Description = "Heavy swings that break through tougher layers.",
		ShopOrder = 2,
		Price = 1200,
		ToolType = "Impact",
		Power = 2,
		Damage = 28,
		AttackInterval = 0.7,
		Range = 12,

		UpgradeOrder = { "Hold", "Speed", "Grip" },
		Upgrades = {
			Hold = {
				DisplayName = "Hold",
				Description = "Hold the button to keep swinging.",
				Kind = "Hold",
				Prices = { 300 },
			},
			Speed = {
				DisplayName = "Speed",
				Description = "Swing faster.",
				Kind = "Speed",
				PerLevel = 0.07,
				Prices = { 400, 800 },
			},
			Grip = {
				DisplayName = "Grip",
				Description = "Hit harder: +8 damage per swing.",
				Kind = "Grip",
				DamagePerLevel = 8,
				Prices = { 500, 1000 },
			},
		},
	},

	Drill = {
		DisplayName = "Drill",
		Description = "Hold it on the egg. Steady damage, and the only tool for the deepest layers.",
		ShopOrder = 3,
		Price = 2800,
		ToolType = "Continuous",
		Power = 3,
		Damage = 16, -- per tick
		AttackInterval = 0.2, -- tick rate while held
		Range = 8, -- short: you have to get close
		SpinUpTime = 1.0, -- seconds to reach full speed

		UpgradeOrder = { "Speed", "Grip", "Reach" },
		Upgrades = {
			Speed = {
				DisplayName = "Speed",
				Description = "Spin faster.",
				Kind = "Speed",
				PerLevel = 0.07,
				Prices = { 600, 1200 },
			},
			Grip = {
				DisplayName = "Grip",
				Description = "Hit harder: +4 damage per tick.",
				Kind = "Grip",
				DamagePerLevel = 4,
				Prices = { 800, 1600 },
			},
			Reach = {
				DisplayName = "Reach",
				Description = "Drill from +2 studs farther away.",
				Kind = "Reach",
				RangePerLevel = 2,
				Prices = { 400 },
			},
		},
	},
}

for toolId, definition in ToolDefinitions do
	definition.Id = toolId
end

return Util.DeepFreeze(ToolDefinitions)