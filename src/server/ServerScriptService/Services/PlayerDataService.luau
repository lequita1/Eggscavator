local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlayerDataService = {}

-- One server = one match. Nothing is saved to a DataStore: every new match starts from zero.
-- Only if a player disconnects and rejoins THIS same server do they get their match progress back.
local dataByPlayer = {}
local keptByUserId = {} -- [userId] = data of a player who left this server mid-match

local function createData()
	return {
		Money = GameConfig.Player.StartingMoney, -- whole CENTS
		OwnedTools = { [GameConfig.Player.StartingToolId] = true },
		EquippedTool = GameConfig.Player.StartingToolId,
		Upgrades = {
			[GameConfig.Player.StartingToolId] = {},
		},
		Inventory = {}, -- bag contents are not kept on rejoin
		BagCapacity = GameConfig.Inventory.StartingCapacity,
		BagTier = 0,
		PickupTier = 0,
		ClimbTier = 0,
	}
end

function PlayerDataService.Get(player: Player)
	return dataByPlayer[player]
end

function PlayerDataService.AddMoney(player: Player, cents: number): number?
	local data = dataByPlayer[player]
	if not data or type(cents) ~= "number" or cents ~= cents then
		return nil
	end
	data.Money += math.floor(cents)
	player:SetAttribute("Money", data.Money)
	return data.Money
end

function PlayerDataService.GrantTool(player: Player, toolId: string): boolean
	local data = dataByPlayer[player]
	if not data or data.OwnedTools[toolId] then
		return false
	end
	data.OwnedTools[toolId] = true
	data.Upgrades[toolId] = data.Upgrades[toolId] or {}
	player:SetAttribute("Owns_" .. toolId, true)
	return true
end

function PlayerDataService.SetUpgradeLevel(player: Player, toolId: string, trackId: string, level: number)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	data.Upgrades[toolId] = data.Upgrades[toolId] or {}
	data.Upgrades[toolId][trackId] = level
	player:SetAttribute(string.format("Up_%s_%s", toolId, trackId), level)
end

local function initPlayer(player: Player)
	local data = createData()
	dataByPlayer[player] = data
	player:SetAttribute("Money", data.Money)
	player:SetAttribute("BagTier", data.BagTier)
	player:SetAttribute("PickupTier", data.PickupTier)
	for toolId in data.OwnedTools do
		player:SetAttribute("Owns_" .. toolId, true)
	end
end

-- Wipes a player back to a fresh start. Nothing calls this now.
function PlayerDataService.Reset(player: Player)
	for name in player:GetAttributes() do
		if name:sub(1, 5) == "Owns_" or name:sub(1, 3) == "Up_" then
			player:SetAttribute(name, nil)
		end
	end
	initPlayer(player)
end

-- Puts a rejoining player's kept data back on the live player.
local function restorePlayer(player: Player, data)
	data.Inventory = {}
	dataByPlayer[player] = data
	player:SetAttribute("Money", data.Money)
	player:SetAttribute("BagTier", data.BagTier)
	player:SetAttribute("BagCapacity", data.BagCapacity)
	player:SetAttribute("BagCount", 0)
	for toolId in data.OwnedTools do
		player:SetAttribute("Owns_" .. toolId, true)
	end
	for toolId, levels in data.Upgrades do
		for trackId, level in levels do
			player:SetAttribute(string.format("Up_%s_%s", toolId, trackId), level)
		end
	end
	player:SetAttribute("PickupTier", data.PickupTier) -- last: PieceService hands out the gear when this changes
	print("[PlayerDataService] Rejoin restored: " .. player.Name)
end

-- Climb Rig tier: 0 = not bought, 1 to 5 = the rig and the ladder levels unlocked so far.
local function syncClimbTier(player: Player)
	local data = dataByPlayer[player]
	if data then
		data.ClimbTier = data.ClimbTier or 0
		player:SetAttribute("ClimbTier", data.ClimbTier)
	end
end

function PlayerDataService.SetClimbTier(player: Player, tier: number)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	data.ClimbTier = tier
	player:SetAttribute("ClimbTier", tier)
end

local function onPlayerAdded(player: Player)
	local kept = keptByUserId[player.UserId]
	if kept then
		keptByUserId[player.UserId] = nil
		restorePlayer(player, kept)
	else
		initPlayer(player)
	end
end

-- Kept so older callers still work. There is no loading any more, so this returns at once.
function PlayerDataService.WaitForLoad(player: Player): boolean
	return true
end

-- Kept so RoundService can still call it before the lobby teleport. Nothing is saved.
function PlayerDataService.SaveAll()
end

function PlayerDataService.Init()
	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(player)
		syncClimbTier(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local data = dataByPlayer[player]
		if data then
			keptByUserId[player.UserId] = data
		end
		dataByPlayer[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		syncClimbTier(player)
	end
	print(string.format("[%s] Init OK", script.Name))
end

return PlayerDataService