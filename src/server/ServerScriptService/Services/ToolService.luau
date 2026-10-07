local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local ToolDefinitions = require(Shared.ToolDefinitions)
local Util = require(Shared.Util)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EggService = require(script.Parent.EggService)
local PieceService = require(script.Parent.PieceService)

local ToolService = {}

local Remotes: Folder
local canCallHitEgg = Util.MakeRateLimiter(GameConfig.RateLimits.HitEgg)
local lastHitTime = setmetatable({}, { __mode = "k" }) -- [player] = os.clock() of last accepted hit
local lastClinkTime = setmetatable({}, { __mode = "k" }) -- [player] = os.clock() of last "Clink!" notice
local HIT_DEBUG = false -- set true to print in the server Output why a hit was rejected
local CLINK_INTERVAL = 1.5

-- Weaker egg for fewer players: every hit does more damage when the match is small.
-- Index = number of players now in the server (1 to 4). Solo = x3, two players = x1.5.
local DAMAGE_BY_PLAYERS = { 3, 1.5, 1, 1 }

local function getPlayerDamageFactor(): number
	local count = math.clamp(#Players:GetPlayers(), 1, 4)
	return DAMAGE_BY_PLAYERS[count]
end

-- Tool IDs sorted by shop order, so the hotbar slots are always Ice Pick, Pickaxe, Drill.
local toolOrder = {}
for toolId in ToolDefinitions do
	table.insert(toolOrder, toolId)
end
table.sort(toolOrder, function(a, b)
	return ToolDefinitions[a].ShopOrder < ToolDefinitions[b].ShopOrder
end)

-- power -> display name, for the "needs a Pickaxe or better" message
local toolNameByPower = {}
for _, toolId in toolOrder do
	local definition = ToolDefinitions[toolId]
	if not toolNameByPower[definition.Power] then
		toolNameByPower[definition.Power] = definition.DisplayName
	end
end

---------------------------------------------------------------------
-- Stats: base tool + the player's upgrade levels = final numbers
---------------------------------------------------------------------
local function computeStats(data, toolId: string)
	local definition = ToolDefinitions[toolId]
	local levels = data.Upgrades[toolId] or {}

	local interval = definition.AttackInterval
	local range = definition.Range
	local damage = definition.Damage
	local hold = definition.ToolType == "Continuous" -- the Drill always holds

	for trackId, track in definition.Upgrades do
		local level = levels[trackId] or 0
		if level > 0 then
			if track.Kind == "Hold" then
				hold = true
			elseif track.Kind == "Speed" then
				interval = interval * (1 - track.PerLevel * level)
			elseif track.Kind == "Grip" then
				damage = damage + track.DamagePerLevel * level
			elseif track.Kind == "Reach" then
				range = range + track.RangePerLevel * level
			end
		end
	end

	return {
		AttackInterval = interval,
		Range = range,
		Damage = damage,
		Power = definition.Power,
		HoldEnabled = hold,
	}
end

-- Copies what the client needs onto the Tool (replicates automatically).
local function applyStatsToTool(tool: Tool, stats)
	tool:SetAttribute("HoldEnabled", stats.HoldEnabled)
	tool:SetAttribute("AttackInterval", stats.AttackInterval)
	tool:SetAttribute("Power", stats.Power) -- for client hints; the server never trusts it
end

---------------------------------------------------------------------
-- Giving tools
---------------------------------------------------------------------
local function containerHasTool(container: Instance?, toolId: string): boolean
	if not container then
		return false
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("ToolId") == toolId then
			return true
		end
	end
	return false
end

-- Puts a tool in the player's Backpack (does nothing if they already have it).
local function giveTool(player: Player, toolId: string): Tool?
	local data = PlayerDataService.Get(player)
	local template = ServerStorage.Assets.Tools:FindFirstChild(toolId)
	if not data or not template then
		warn(string.format("[ToolService] No tool named '%s' in ServerStorage.Assets.Tools", toolId))
		return nil
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return nil
	end
	if containerHasTool(backpack, toolId) or containerHasTool(player.Character, toolId) then
		return nil
	end

	local tool = template:Clone()
	tool:SetAttribute("ToolId", toolId) -- set BEFORE parenting so the client sees it immediately
	applyStatsToTool(tool, computeStats(data, toolId))
	tool.Parent = backpack
	return tool
end

-- Called by ShopService after a purchase.
function ToolService.GiveTool(player: Player, toolId: string)
	return giveTool(player, toolId)
end

-- Called by ShopService after an upgrade: updates the tool the player already has.
function ToolService.RefreshTool(player: Player, toolId: string)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	local stats = computeStats(data, toolId)
	for _, container in { player:FindFirstChild("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ToolId") == toolId then
					applyStatsToTool(child, stats)
				end
			end
		end
	end
end

-- On spawn: give every owned tool, and hold the starting tool.
local function giveOwnedTools(player: Player, character: Model)
	PlayerDataService.WaitForLoad(player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local backpack = player:WaitForChild("Backpack")
	for _, toolId in toolOrder do
		if data.OwnedTools[toolId] then
			giveTool(player, toolId)
		end
	end

	local startTool = backpack:FindFirstChild(data.EquippedTool)
	local humanoid = character:WaitForChild("Humanoid")
	if startTool then
		humanoid:EquipTool(startTool)
	end
end

---------------------------------------------------------------------
-- Hit validation
---------------------------------------------------------------------
local function onHitEgg(player: Player, eggId: any, hitPosition: any, patchIndex: any)
	-- 1. Rate limit
	if not canCallHitEgg(player) then
		return
	end

	-- 2. Argument types (never trust what the client sends)
	if typeof(eggId) ~= "string" or typeof(hitPosition) ~= "Vector3" then
		return
	end
	if hitPosition ~= hitPosition or hitPosition.Magnitude > 100000 then
		return -- NaN or absurd position
	end
	if type(patchIndex) ~= "number" or patchIndex % 1 ~= 0 then
		return -- the client must say which patch it hit
	end

	-- 3. Player must be alive
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	-- 4. The tool is the one the player is HOLDING, and they must really own it
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	local heldTool = character:FindFirstChildOfClass("Tool")
	local heldToolId = heldTool and heldTool:GetAttribute("ToolId")
	local toolDef = heldToolId and ToolDefinitions[heldToolId]
	if not toolDef or not data.OwnedTools[toolDef.Id] then
		return
	end
	local stats = computeStats(data, toolDef.Id)

	-- 5. Attack speed
	local now = os.clock()
	local last = lastHitTime[player]
	if last and now - last < stats.AttackInterval * GameConfig.Combat.IntervalTolerance then
		return
	end

	-- 6. The egg must exist and be alive
	local eggModel = EggService.GetEggModel(eggId)
	if not eggModel then
		return
	end

	-- 7. The patch the client says it hit (it must exist and be closed)
	local index = patchIndex
	local info = EggService.GetPatchInfo(eggId, index)
	if not info or info.Open then
		if HIT_DEBUG then
			print("[HitDebug] rejected: no closed patch for this hit")
		end
		return
	end

	-- 8. Reach: distance from the player to the patch's nearest edge (current layer)
	local standing = math.max((root.Position - info.Center).Magnitude - info.Radius, 0)
	local reach = stats.Range + GameConfig.Combat.HitPositionTolerance
	if standing > reach then
		if HIT_DEBUG then
			print(string.format("[HitDebug] rejected: you stand %.1f studs from patch %d, reach is %.1f", standing, index, reach))
		end
		return
	end

	-- 9. The claimed hit position must be on/near that patch
	local offPatch = (hitPosition - info.Center).Magnitude - info.Radius
	if offPatch > GameConfig.Combat.HitPositionTolerance then
		if HIT_DEBUG then
			print(string.format("[HitDebug] rejected: the click is %.1f studs from patch %d", offPatch, index))
		end
		return
	end

	-- 10. The SERVER decides tool power, damage and the result
	-- (damage is scaled by the live player count: weaker egg for fewer players)
	local damageFactor = getPlayerDamageFactor()
	local result = EggService.ApplyPatchDamage(eggId, index, stats.Damage * damageFactor, stats.Power, player)
	if not result then
		return
	end
	if result.TooHard then
		local t = os.clock()
		if not lastClinkTime[player] or t - lastClinkTime[player] > CLINK_INTERVAL then
			lastClinkTime[player] = t
			local toolName = toolNameByPower[result.Required] or "stronger tool"
			Remotes.Notify:FireClient(player, string.format("Clink! %s needs a %s or better.", result.LayerName, toolName), "Info")
		end
		return
	end
	lastHitTime[player] = now

	-- Tell every client (extra values at the end: patchIndex, hpFraction, layerAfter; the old 6th stays nil)
	Remotes.EggHit:FireAllClients(
		eggId, hitPosition, result.Applied, false, toolDef.Id, nil,
		result.PatchIndex, result.HPFraction, result.LayerAfter
	)

	-- Only a broken patch drops a piece (the layer that just broke)
	if result.PatchBroken then
		PieceService.SpawnPiece(eggModel, result.PatchIndex, result.LayerBefore, player)
	end
end

---------------------------------------------------------------------
function ToolService.Init()
	Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remotes.HitEgg.OnServerEvent:Connect(onHitEgg)

	local function setupPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(giveOwnedTools, player, character)
		end)
		if player.Character then
			task.spawn(giveOwnedTools, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	print(string.format("[%s] Init OK", script.Name))
end

return ToolService