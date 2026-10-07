local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local ItemDefinitions = require(Shared.ItemDefinitions)
local ToolDefinitions = require(Shared.ToolDefinitions)
local Util = require(Shared.Util)
local Curator = require(Shared.Curator)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local ToolService = require(script.Parent.ToolService)

local ShopService = {}

local Remotes: Folder
local shopCounter: BasePart

local canSell = Util.MakeRateLimiter(GameConfig.RateLimits.SellAll)
local canBuyTool = Util.MakeRateLimiter(GameConfig.RateLimits.BuyTool)
local canBuyCapacity = Util.MakeRateLimiter(GameConfig.RateLimits.BuyCapacityUpgrade)
local canBuyPickup = Util.MakeRateLimiter(GameConfig.RateLimits.BuyCapacityUpgrade)
local canBuyUpgrade = Util.MakeRateLimiter(GameConfig.RateLimits.BuyUpgrade)

---------------------------------------------------------------------
-- Pay by player count: fewer players share the egg, so each piece pays less.
-- The count is locked at the first sale of the match and never changes.
---------------------------------------------------------------------
local PAY_MULTIPLIER_BY_PLAYERS = { 0.25, 0.5, 0.75, 1 } -- index = players (1 to 4)
local lockedPlayerCount: number? = nil

local function getPayMultiplier(): number
	if not lockedPlayerCount then
		lockedPlayerCount = math.clamp(#Players:GetPlayers(), 1, #PAY_MULTIPLIER_BY_PLAYERS)
		print(string.format("[ShopService] Player count locked at %d (pay x%s)", lockedPlayerCount, tostring(PAY_MULTIPLIER_BY_PLAYERS[lockedPlayerCount])))
	end
	return PAY_MULTIPLIER_BY_PLAYERS[lockedPlayerCount]
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function isNear(player: Player, part: BasePart, range: number): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	return (root.Position - part.Position).Magnitude <= range
end

local function notify(player: Player, message: string, kind: string)
	Remotes.Notify:FireClient(player, message, kind)
end

---------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------
-- Sells everything in the player's bag. The SERVER reads the values.
local function sellAll(player: Player, sellPart: BasePart)
	if not canSell(player) then
		return
	end
	if not isNear(player, sellPart, GameConfig.Interaction.SellRange) then
		return
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	if InventoryService.GetCount(player) == 0 then
		notify(player, "Your bag is empty.", "warning")
		return
	end

	local payMultiplier = getPayMultiplier()

	-- Empty the bag and add up the value, remembering the best specimen sold
	local taken = InventoryService.TakeAll(player)
	local lines = {}
	local totalCents = 0
	local bestItemId, bestRank, bestValue = nil, -1, -1
	for itemId, count in taken do
		local item = ItemDefinitions[itemId]
		if item and count > 0 then
			local lineCents = math.floor(item.Value * count * payMultiplier + 0.5)
			totalCents += lineCents
			table.insert(lines, {
				ItemId = itemId,
				Count = count,
				Cents = lineCents,
				SortOrder = item.SortOrder,
			})

			local rarity = GameConfig.Rarities[item.Rarity]
			local rank = if rarity then (rarity.Order or 0) else 0
			if rank > bestRank or (rank == bestRank and item.Value > bestValue) then
				bestItemId, bestRank, bestValue = itemId, rank, item.Value
			end
		end
	end
	table.sort(lines, function(a, b)
		return a.SortOrder < b.SortOrder
	end)

	PlayerDataService.AddMoney(player, totalCents)

	local curatorLine = Curator.PickLine(bestItemId, bestRank, totalCents)
	Remotes.SellResult:FireClient(player, {
		Lines = lines,
		TotalCents = totalCents,
		CuratorName = Curator.Name,
		CuratorLine = curatorLine,
	})
	notify(player, Curator.Name .. ": " .. curatorLine, "success")
end

---------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------
-- The client sends only a tool ID. Price, ownership, money and distance are all checked here.
local function onBuyTool(player: Player, toolId: any)
	if not canBuyTool(player) then
		return
	end
	if typeof(toolId) ~= "string" then
		return
	end

	local definition = ToolDefinitions[toolId]
	local data = PlayerDataService.Get(player)
	if not definition or not data or definition.Price <= 0 then
		return -- unknown tool, or the free starter tool
	end
	if not isNear(player, shopCounter, GameConfig.Interaction.ShopRange) then
		return
	end
	if data.OwnedTools[toolId] then
		notify(player, "You already own the " .. definition.DisplayName .. ".", "warning")
		return
	end
	if data.Money < definition.Price then
		notify(player, "Not enough money.", "warning")
		return
	end

	PlayerDataService.AddMoney(player, -definition.Price)
	PlayerDataService.GrantTool(player, toolId)
	ToolService.GiveTool(player, toolId)
	notify(player, "Bought the " .. definition.DisplayName .. "!", "success")
end

-- Storage: the player picks a bag size, the server checks the size and the money
local function onBuyCapacityUpgrade(player: Player, tier: any)
	if not canBuyCapacity(player) then
		return
	end

	-- the client only says WHICH bag it wants (a whole number)
	if typeof(tier) ~= "number" or tier ~= tier or tier % 1 ~= 0 then
		return
	end
	local upgrade = GameConfig.Inventory.CapacityUpgrades[tier]
	if not upgrade then
		return
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	if not isNear(player, shopCounter, GameConfig.Interaction.ShopRange) then
		return
	end
	if tier <= data.BagTier then
		notify(player, "You already have a bag that size or bigger.", "warning")
		return
	end
	if data.Money < upgrade.Price then
		notify(player, "Not enough money.", "warning")
		return
	end

	PlayerDataService.AddMoney(player, -upgrade.Price)
	data.BagTier = tier
	data.BagCapacity = upgrade.Capacity
	player:SetAttribute("BagTier", data.BagTier)
	InventoryService.Sync(player) -- updates BagCapacity on the HUD
	notify(player, string.format("%s! Carry %d pieces.", upgrade.Name, upgrade.Capacity), "success")
end

-- Pickup gear: hands, brush, vacuum
local function onBuyPickupUpgrade(player: Player)
	if not canBuyPickup(player) then
		return
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	if not isNear(player, shopCounter, GameConfig.Interaction.ShopRange) then
		return
	end

	-- The SERVER picks which upgrade is next
	local nextUpgrade = GameConfig.Pickup.Upgrades[data.PickupTier + 1]
	if not nextUpgrade then
		notify(player, "Your pickup gear is fully upgraded.", "warning")
		return
	end
	if data.Money < nextUpgrade.Price then
		notify(player, "Not enough money.", "warning")
		return
	end

	PlayerDataService.AddMoney(player, -nextUpgrade.Price)
	data.PickupTier += 1
	player:SetAttribute("PickupTier", data.PickupTier)
	notify(player, string.format("%s ready! %s", nextUpgrade.Name, nextUpgrade.Description), "success")
end

-- Climb Rig: the rig, then ladder levels 2 to 5 (tiers come from GameConfig.Climb + ClimbTier)
local canBuyClimb = Util.MakeRateLimiter(GameConfig.RateLimits.BuyCapacityUpgrade)
local function onBuyClimbUpgrade(player: Player)
	if not canBuyClimb(player) then
		return
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	if not isNear(player, shopCounter, GameConfig.Interaction.ShopRange) then
		return
	end

	-- The SERVER picks which tier is next
	local tier = data.ClimbTier or 0
	local nextTier = GameConfig.Climb.Tiers[tier + 1]
	if not nextTier then
		notify(player, "Your Ladder is fully upgraded.", "warning")
		return
	end
	if data.Money < nextTier.Price then
		notify(player, "Not enough money.", "warning")
		return
	end

	PlayerDataService.AddMoney(player, -nextTier.Price)
	PlayerDataService.SetClimbTier(player, tier + 1)
	notify(player, string.format("%s ready! %s", nextTier.Name, nextTier.Description), "success")
end

-- The client sends only a tool ID and a track ID. Level, price, ownership and money are all checked here.
local function onBuyUpgrade(player: Player, toolId: any, trackId: any)
	if not canBuyUpgrade(player) then
		return
	end
	if typeof(toolId) ~= "string" or typeof(trackId) ~= "string" then
		return
	end

	local definition = ToolDefinitions[toolId]
	local data = PlayerDataService.Get(player)
	local track = definition and definition.Upgrades[trackId]
	if not track or not data then
		return
	end
	if not data.OwnedTools[toolId] then
		notify(player, "Buy the " .. definition.DisplayName .. " first.", "warning")
		return
	end

	local currentLevel = (data.Upgrades[toolId] and data.Upgrades[toolId][trackId]) or 0
	local price = track.Prices[currentLevel + 1]
	if not price then
		notify(player, track.DisplayName .. " is already maxed.", "warning")
		return
	end
	if data.Money < price then
		notify(player, "Not enough money.", "warning")
		return
	end

	PlayerDataService.AddMoney(player, -price)
	PlayerDataService.SetUpgradeLevel(player, toolId, trackId, currentLevel + 1)
	ToolService.RefreshTool(player, toolId)
	notify(player, string.format("%s upgraded! (%s)", track.DisplayName, definition.DisplayName), "success")
end

---------------------------------------------------------------------
function ShopService.Init()
	Remotes = ReplicatedStorage:WaitForChild("Remotes")

	local map = Workspace:WaitForChild("Map")

	local sellCounter = map:WaitForChild("SellStation"):WaitForChild("Counter")
	sellCounter:WaitForChild("SellPrompt").Triggered:Connect(function(player)
		sellAll(player, sellCounter)
	end)

	shopCounter = map:WaitForChild("ToolShop"):WaitForChild("Counter")

	-- This service owns the pickup gear remote, so it creates it here
	local buyPickup = Remotes:FindFirstChild("BuyPickupUpgrade")
	if not buyPickup then
		buyPickup = Instance.new("RemoteEvent")
		buyPickup.Name = "BuyPickupUpgrade"
		buyPickup.Parent = Remotes
	end

	Remotes.BuyTool.OnServerEvent:Connect(onBuyTool)
	Remotes.BuyCapacityUpgrade.OnServerEvent:Connect(onBuyCapacityUpgrade)
	buyPickup.OnServerEvent:Connect(onBuyPickupUpgrade)

	-- This service also owns the Climb Rig remote
	local buyClimb = Remotes:FindFirstChild("BuyClimbUpgrade")
	if not buyClimb then
		buyClimb = Instance.new("RemoteEvent")
		buyClimb.Name = "BuyClimbUpgrade"
		buyClimb.Parent = Remotes
	end
	buyClimb.OnServerEvent:Connect(onBuyClimbUpgrade)
	Remotes.BuyUpgrade.OnServerEvent:Connect(onBuyUpgrade)

	print(string.format("[%s] Init OK", script.Name))
end

return ShopService