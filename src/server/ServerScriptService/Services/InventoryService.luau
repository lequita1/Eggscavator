local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.Shared.ItemDefinitions)
local PlayerDataService = require(script.Parent.PlayerDataService)

local InventoryService = {}

local reservedCount = setmetatable({}, { __mode = "k" }) -- [player] = bag slots held for pieces that are still flying in

-- Total number of items in the bag.
function InventoryService.GetCount(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, count in data.Inventory do
		total += count
	end
	return total
end

function InventoryService.GetFreeSpace(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	return math.max(data.BagCapacity - InventoryService.GetCount(player) - (reservedCount[player] or 0), 0)
end

-- Copies bag numbers to Player attributes so the client HUD can read them.
function InventoryService.Sync(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("BagCount", InventoryService.GetCount(player))
	player:SetAttribute("BagCapacity", data.BagCapacity)
end

-- Adds up to `count` of an item. Returns how many were actually added (0 if full).
function InventoryService.Add(player: Player, itemId: string, count: number): number
	local data = PlayerDataService.Get(player)
	if not data or not ItemDefinitions[itemId] then
		return 0
	end
	if type(count) ~= "number" or count <= 0 then
		return 0
	end

	local added = math.min(math.floor(count), InventoryService.GetFreeSpace(player))
	if added <= 0 then
		return 0
	end

	data.Inventory[itemId] = (data.Inventory[itemId] or 0) + added
	InventoryService.Sync(player)
	return added
end

-- Empties the bag and returns what was in it: { [itemId] = count }.
function InventoryService.TakeAll(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return {}
	end
	local taken = data.Inventory
	data.Inventory = {}
	InventoryService.Sync(player)
	return taken
end

-- Holds bag space for pieces that are flying to the player (GetFreeSpace counts it as taken).
function InventoryService.Reserve(player: Player, count: number)
	reservedCount[player] = (reservedCount[player] or 0) + count
end

-- Gives the held space back. Call it right before Add when the piece arrives.
function InventoryService.Release(player: Player, count: number)
	local left = (reservedCount[player] or 0) - count
	reservedCount[player] = if left > 0 then left else nil
end

function InventoryService.Init()
	-- defer: lets PlayerDataService create the data first
	Players.PlayerAdded:Connect(function(player)
		task.defer(InventoryService.Sync, player)
	end)
	for _, player in Players:GetPlayers() do
		InventoryService.Sync(player)
	end
	print(string.format("[%s] Init OK", script.Name))
end

return InventoryService