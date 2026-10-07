local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactLua"):WaitForChild("React"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ToolDefinitions = require(Shared:WaitForChild("ToolDefinitions"))
local EggDefinitions = require(Shared:WaitForChild("EggDefinitions"))
local Util = require(Shared:WaitForChild("Util"))

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local eggsFolder = Workspace:WaitForChild("Eggs")

local Store = {}

---------------------------------------------------------------------
-- A channel = one piece of state + subscribers + a React hook.
-- mark() is safe to call many times per frame: it rebuilds once, on the next defer.
---------------------------------------------------------------------
local function makeChannel(compute)
	local channel = {}
	local value = compute()
	local listeners = {}
	local pending = false

	function channel.get()
		return value
	end

	function channel.mark()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			value = compute() -- always a NEW table so React sees the change
			for listener in table.clone(listeners) do
				listener(value)
			end
		end)
	end

	function channel.subscribe(listener)
		listeners[listener] = true
		return function()
			listeners[listener] = nil
		end
	end

	function channel.use()
		local current, setCurrent = React.useState(channel.get())
		React.useEffect(function()
			setCurrent(channel.get())
			return channel.subscribe(setCurrent)
		end, {})
		return current
	end

	return channel
end

-- Tool IDs in shop order (Ice Pick, Pickaxe, Drill)
local toolIds = {}
for toolId in ToolDefinitions do
	table.insert(toolIds, toolId)
end
table.sort(toolIds, function(a, b)
	return ToolDefinitions[a].ShopOrder < ToolDefinitions[b].ShopOrder
end)

---------------------------------------------------------------------
-- MAIN: money, bag, tools and upgrades (all from Player attributes set by the server)
---------------------------------------------------------------------
local function computeMain()
	local money = player:GetAttribute("Money") or 0 -- whole CENTS
	local tier = player:GetAttribute("BagTier") or 0
	local pickupTier = player:GetAttribute("PickupTier") or 0
	local climbTier = player:GetAttribute("ClimbTier") or 0

	-- Pickup gear tools (Brush, Vacuum): owned once the PickupTier reaches them
	local gear = {}
	for index, upgrade in GameConfig.Pickup.Upgrades do
		table.insert(gear, {
			Id = upgrade.Id,
			Name = upgrade.Name,
			Description = upgrade.Description,
			Owned = pickupTier >= index,
		})
	end

	local tools = {}
	for _, toolId in toolIds do
		local definition = ToolDefinitions[toolId]
		local tracks = {}
		for _, trackId in definition.UpgradeOrder do
			local track = definition.Upgrades[trackId]
			local level = player:GetAttribute(string.format("Up_%s_%s", toolId, trackId)) or 0
			table.insert(tracks, {
				Id = trackId,
				Name = track.DisplayName,
				Description = track.Description,
				Level = level,
				MaxLevel = #track.Prices,
				Price = track.Prices[level + 1], -- nil when maxed (cents)
			})
		end
		table.insert(tools, {
			Id = toolId,
			Name = definition.DisplayName,
			Description = definition.Description,
			Price = definition.Price, -- cents
			Owned = player:GetAttribute("Owns_" .. toolId) == true,
			Tracks = tracks,
		})
	end

	return {
		Money = money,
		MoneyText = Util.FormatCents(money),
		Carried = player:GetAttribute("BagCount") or 0,
		Capacity = player:GetAttribute("BagCapacity") or GameConfig.Inventory.StartingCapacity,
		BagTier = tier,
		BagNext = GameConfig.Inventory.CapacityUpgrades[tier + 1], -- { Name, Capacity, Price } or nil
		PickupTier = pickupTier,
		ClimbTier = climbTier,
		ClimbNext = GameConfig.Climb.Tiers[climbTier + 1], -- { Name, Price, ... } or nil
		PickupNext = GameConfig.Pickup.Upgrades[pickupTier + 1], -- { Name, Price, ... } or nil
		Gear = gear,
		Tools = tools,
	}
end

---------------------------------------------------------------------
-- EGG: health for the egg bar (the session has one egg)
---------------------------------------------------------------------
local function computeEgg()
	for _, egg in eggsFolder:GetChildren() do
		local maxDurability = egg:GetAttribute("MaxDurability")
		local durability = egg:GetAttribute("Durability")
		if maxDurability and durability then
			local definition = EggDefinitions[egg:GetAttribute("EggType")]
			return {
				Present = durability > 0,
				Fraction = math.clamp(durability / maxDurability, 0, 1),
				Name = definition and definition.DisplayName or "Egg",
				Stage = egg:GetAttribute("Stage") or 0,
			}
		end
	end
	return { Present = false, Fraction = 0, Name = "Egg", Stage = 0 }
end

---------------------------------------------------------------------
-- ROUND: state and timestamps (Workspace attributes set by RoundService)
---------------------------------------------------------------------
local function computeRound()
	return {
		State = Workspace:GetAttribute("RoundState") or "Playing",
		Start = Workspace:GetAttribute("RoundStart"),
		End = Workspace:GetAttribute("RoundEnd"),
	}
end

---------------------------------------------------------------------
-- TOOL: the tool the character is holding right now
---------------------------------------------------------------------
local function computeTool()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local toolId = tool and tool:GetAttribute("ToolId")
	local definition = toolId and ToolDefinitions[toolId]
	return { Id = definition and definition.Id, Name = definition and definition.DisplayName }
end

local mainChannel = makeChannel(computeMain)
local eggChannel = makeChannel(computeEgg)
local roundChannel = makeChannel(computeRound)
local toolChannel = makeChannel(computeTool)

---------------------------------------------------------------------
-- Wiring the real game to the channels
---------------------------------------------------------------------
player.AttributeChanged:Connect(function(name: string)
	if
		name == "Money"
		or name == "BagCount"
		or name == "BagCapacity"
		or name == "BagTier"
		or name == "PickupTier"
		or name == "ClimbTier"
		or name:sub(1, 5) == "Owns_"
		or name:sub(1, 3) == "Up_"
	then
		mainChannel.mark()
	end
end)

local function hookEgg(egg: Instance)
	egg.AttributeChanged:Connect(function()
		eggChannel.mark()
	end)
	eggChannel.mark()
end
eggsFolder.ChildAdded:Connect(hookEgg)
eggsFolder.ChildRemoved:Connect(function()
	eggChannel.mark()
end)
for _, egg in eggsFolder:GetChildren() do
	hookEgg(egg)
end

Workspace.AttributeChanged:Connect(function(name: string)
	if name == "RoundState" or name == "RoundStart" or name == "RoundEnd" then
		roundChannel.mark()
	end
end)

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			toolChannel.mark()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			toolChannel.mark()
		end
	end)
	toolChannel.mark()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

---------------------------------------------------------------------
-- Reading (React hooks)
---------------------------------------------------------------------
Store.useStore = mainChannel.use
Store.useEgg = eggChannel.use
Store.useRound = roundChannel.use
Store.useTool = toolChannel.use
Store.get = mainChannel.get
Store.subscribe = mainChannel.subscribe

---------------------------------------------------------------------
-- Actions: INTENT ONLY. The server checks money, ownership, price and distance.
-- Results come back as attribute changes, so the UI updates by itself.
---------------------------------------------------------------------
function Store.buyTrack(toolId: string, trackId: string)
	Remotes.BuyUpgrade:FireServer(toolId, trackId)
end

function Store.buyTool(toolId: string)
	Remotes.BuyTool:FireServer(toolId)
end

function Store.buyBagUpgrade()
	Remotes.BuyCapacityUpgrade:FireServer()
end

-- Bags: the player picks the size. The server checks the size and the money.
function Store.buyBagTier(tier: number)
	Remotes.BuyCapacityUpgrade:FireServer(tier)
end

function Store.buyClimbUpgrade()
	local remote = Remotes:WaitForChild("BuyClimbUpgrade", 5) -- ShopService creates it at server start
	if remote then
		remote:FireServer()
	end
end

function Store.buyPickupUpgrade()
	local remote = Remotes:WaitForChild("BuyPickupUpgrade", 5) -- ShopService creates it at server start
	if remote then
		remote:FireServer()
	end
end

return Store