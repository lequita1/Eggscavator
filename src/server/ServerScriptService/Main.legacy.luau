local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Util = require(Shared.Util)
local GameConfig = require(Shared.GameConfig)
local ToolDefinitions = require(Shared.ToolDefinitions)
local EggDefinitions = require(Shared.EggDefinitions)
local ItemDefinitions = require(Shared.ItemDefinitions)

---------------------------------------------------------------------
-- 1. REMOTES
-- The client only ever sends INTENT. The server decides every result.
---------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
assert(remotesFolder, "Main: ReplicatedStorage needs a Folder named 'Remotes' (M1 Step 1).")

local REMOTE_NAMES = {
	-- Client -> Server (requests)
	"HitEgg", -- (eggId: string, hitPosition: Vector3, patchIndex: number)
	"CollectDrop", -- (dropId: string) not used
	"SellAll", -- ()
	"BuyTool", -- (toolId: string)
	"EquipTool", -- (toolId: string)
	"BuyCapacityUpgrade", -- ()
	"BuyUpgrade", -- (toolId: string, trackId: string)
	"TeleportRequest", -- (stationKey: "Sell" | "Shop")

	-- Server -> Client (results)
	"PlayerDataChanged", -- (snapshot table)
	"EggHit", -- (eggId, position, damage, isWeakPoint, toolId, nil, patchIndex, hpFraction, layerAfter)
	"EggBroken", -- (eggId, position)
	"LootDropped", -- (list of drops for this player)
	"SellResult", -- (summary table)
	"Notify", -- (message: string, kind: string)
	"RoundResults", -- (results table: time, deliverer, contributions)
}

for _, remoteName in REMOTE_NAMES do
	if not remotesFolder:FindFirstChild(remoteName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
end

-- Clients wait for this flag so they never look for remotes too early.
remotesFolder:SetAttribute("Ready", true)
print(string.format("[Main] Remotes ready (%d)", #remotesFolder:GetChildren()))

---------------------------------------------------------------------
-- 2. VALIDATE DEFINITIONS (catches typos in item/tool IDs early)
---------------------------------------------------------------------
local function count(tbl): number
	local n = 0
	for _ in tbl do
		n += 1
	end
	return n
end

local function validateDefinitions(): boolean
	local problems = 0

	local maxPower = 0
	for toolId, tool in ToolDefinitions do
		if type(tool.Power) ~= "number" then
			warn(string.format("[Main] Tool '%s' has no numeric Power", toolId))
			problems += 1
		else
			maxPower = math.max(maxPower, tool.Power)
		end
	end

	for eggId, egg in EggDefinitions do
		local layers = egg.Layers
		if type(layers) ~= "table" or #layers < 1 or #layers > 8 then
			warn(string.format("[Main] Egg '%s' needs 1 to 8 Layers", eggId))
			problems += 1
		else
			for index, layer in layers do
				if type(layer.HP) ~= "number" or layer.HP <= 0 then
					warn(string.format("[Main] Egg '%s' layer %d has a bad HP", eggId, index))
					problems += 1
				end
				if type(layer.Hardness) ~= "number" or layer.Hardness < 1 or layer.Hardness > maxPower then
					warn(string.format("[Main] Egg '%s' layer %d Hardness must be 1..%d (no tool is stronger)", eggId, index, maxPower))
					problems += 1
				end
				if not ItemDefinitions[layer.PieceItem] then
					warn(string.format("[Main] Egg '%s' layer %d PieceItem '%s' is not in ItemDefinitions", eggId, index, tostring(layer.PieceItem)))
					problems += 1
				end
				if typeof(layer.Color) ~= "Color3" or typeof(layer.Material) ~= "EnumItem" then
					warn(string.format("[Main] Egg '%s' layer %d needs a Color3 and a Material", eggId, index))
					problems += 1
				end
			end
		end
		if type(egg.OpenToHatch) ~= "number" or egg.OpenToHatch <= 0 or egg.OpenToHatch > 1 then
			warn(string.format("[Main] Egg '%s' OpenToHatch must be above 0 and at most 1", eggId))
			problems += 1
		end
	end

	for itemId, item in ItemDefinitions do
		if not GameConfig.Rarities[item.Rarity] then
			warn(string.format("[Main] Item '%s' has unknown rarity '%s'", itemId, item.Rarity))
			problems += 1
		end
	end

	if not ToolDefinitions[GameConfig.Player.StartingToolId] then
		warn("[Main] GameConfig.Player.StartingToolId is not a real tool")
		problems += 1
	end

	return problems == 0
end

assert(validateDefinitions(), "[Main] Definition problems found. Check the warnings above.")
print(string.format(
	"[Main] Definitions OK: %d tools, %d egg(s), %d items",
	count(ToolDefinitions), count(EggDefinitions), count(ItemDefinitions)
	))

---------------------------------------------------------------------
-- 3. START SERVICES (order matters: data first, then what depends on it)
---------------------------------------------------------------------
local servicesFolder = ServerScriptService.Services

local SERVICE_ORDER = {
	"PlayerDataService",
	"InventoryService",
	"EggService",
	"PieceService",
	"ToolService",
	"ShopService",
	"StationTeleportService",
	"RoundService",
}

for _, serviceName in SERVICE_ORDER do
	local service = require(servicesFolder[serviceName])
	service.Init()
end

print("[Main] Server started. Format test: " .. Util.FormatMoney(1234567))