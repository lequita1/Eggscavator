local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local EggDefinitions = require(Shared.EggDefinitions)
local ItemDefinitions = require(Shared.ItemDefinitions)
local Util = require(Shared.Util)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)

local PieceService = {}

local EGG_TYPE = "Stonehatch"
local PIECE_SCALE = 0.5 -- the piece is half the size of the patch it came from
local OWNER_WINDOW = 6 -- seconds the breaker has first claim
local LIFETIME = 180 -- seconds before an uncollected piece or pile fades
local MAX_PIECES = 300 -- piles and pieces on the ground (the oldest is removed)
local SETTLE_TIME = 3 -- after this the piece is anchored, stops colliding and may join a pile
local MERGE_RADIUS = 8 -- studs: settled pieces this close (same item, same breaker) become one pile
local PILE_GROWTH = 0.12 -- each extra piece makes the pile this much bigger...
local PILE_MAX_SCALE = 1.8 -- ...up to this size
local REACH_TOLERANCE = 4 -- studs added to a reach for the server check (network lag)
local FULL_NOTICE_INTERVAL = 1.5
local HAND_REACH = GameConfig.Pickup.Start.Reach -- clicking a single piece or pile with your hand

local Remotes: Folder
local piecesFolder: Folder
local canCollect = Util.MakeRateLimiter(GameConfig.RateLimits.CollectDrop)
local live = {} -- oldest first: every piece and pile on the ground
local settled = {} -- set of anchored pieces that can take part in a merge
local baseSize = setmetatable({}, { __mode = "k" }) -- [piece] = size of a single piece
local lastFullNotice = setmetatable({}, { __mode = "k" }) -- [player] = os.clock()
local lastGearUse = setmetatable({}, { __mode = "k" }) -- [player] = os.clock()
local patchRel = {} -- [index] = { Part, Rel }

-- Pickup gear by id: { Def, Index }. Index is the PickupTier needed to own it.
local gearById = {}
for index, def in GameConfig.Pickup.Upgrades do
	gearById[def.Id] = { Def = def, Index = index }
end

local function loadPatchTemplates()
	local root = ReplicatedStorage:FindFirstChild("EggPatches")
	local folder = root and root:FindFirstChild(EGG_TYPE)
	local shellCF = folder and folder:GetAttribute("ShellCFrame")
	if not folder or typeof(shellCF) ~= "CFrame" then
		warn("[PieceService] EggPatches." .. EGG_TYPE .. " missing or has no ShellCFrame")
		return
	end
	for _, part in folder:GetChildren() do
		local index = part:GetAttribute("Index")
		if part:IsA("BasePart") and type(index) == "number" then
			patchRel[index] = { Part = part, Rel = shellCF:ToObjectSpace(part.CFrame) }
		end
	end
end

local function removeFromLive(piece)
	local i = table.find(live, piece)
	if i then
		table.remove(live, i)
	end
end

---------------------------------------------------------------------
-- Piles: size grows with the count, and a small "xN" label shows it
---------------------------------------------------------------------
local function refreshPile(piece: BasePart)
	local count = piece:GetAttribute("Count") or 1
	local base = baseSize[piece]
	if base then
		piece.Size = base * math.min(1 + PILE_GROWTH * (count - 1), PILE_MAX_SCALE)
	end

	local gui = piece:FindFirstChild("CountLabel")
	if count > 1 then
		if not gui then
			gui = Instance.new("BillboardGui")
			gui.Name = "CountLabel"
			gui.Size = UDim2.fromOffset(64, 26)
			gui.StudsOffset = Vector3.new(0, 2, 0)
			gui.MaxDistance = 70
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextSize = 20
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
			gui.Parent = piece
		end
		local label = gui:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = "x" .. count
		end
	elseif gui then
		gui:Destroy()
	end
end

-- Called once a piece has settled: joins a nearby pile of the same kind, or becomes one.
local function tryMerge(piece: BasePart)
	local itemId = piece:GetAttribute("ItemId")
	local owner = piece:GetAttribute("OwnerUserId")
	for other in settled do
		if
			other ~= piece
			and other.Parent
			and other:GetAttribute("ItemId") == itemId
			and other:GetAttribute("OwnerUserId") == owner
			and (other.Position - piece.Position).Magnitude <= MERGE_RADIUS
		then
			other:SetAttribute("Count", (other:GetAttribute("Count") or 1) + (piece:GetAttribute("Count") or 1))
			local claim = piece:GetAttribute("ClaimUntil")
			if claim and (other:GetAttribute("ClaimUntil") or 0) < claim then
				other:SetAttribute("ClaimUntil", claim)
			end
			refreshPile(other)
			piece:Destroy()
			return
		end
	end
	settled[piece] = true
end

---------------------------------------------------------------------
-- Pickup helpers
---------------------------------------------------------------------
local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

-- A piece is reserved for its breaker for the first few seconds
local function canClaim(player: Player, piece: BasePart): boolean
	local ownerId = piece:GetAttribute("OwnerUserId")
	local claimUntil = piece:GetAttribute("ClaimUntil")
	return not (ownerId and ownerId ~= player.UserId and claimUntil and os.clock() < claimUntil)
end

local function noticeFull(player: Player)
	local now = os.clock()
	if not lastFullNotice[player] or now - lastFullNotice[player] > FULL_NOTICE_INTERVAL then
		lastFullNotice[player] = now
		Remotes.Notify:FireClient(player, "Bag full!", "warning")
	end
end

-- Moves as much of a piece or pile as fits into the bag. Returns how many were added.
-- Position is extra: LootFeed reads ItemId and Count, and the fly-in animation will use Position.
local function takeInto(player: Player, piece: BasePart, free: number, gains): number
	local itemId = piece:GetAttribute("ItemId")
	if free < 1 or not ItemDefinitions[itemId] then
		return 0
	end
	local count = piece:GetAttribute("Count") or 1
	local added = InventoryService.Add(player, itemId, math.min(count, free))
	if not added or added <= 0 then
		return 0
	end
	table.insert(gains, { ItemId = itemId, Count = added, Position = piece.Position })
	if added >= count then
		piece:Destroy()
	else
		piece:SetAttribute("Count", count - added) -- the rest stays on the ground
		refreshPile(piece)
	end
	return added
end

local function sendGains(player: Player, gains)
	if #gains > 0 then
		Remotes.LootDropped:FireClient(player, gains)
	end
end

---------------------------------------------------------------------
-- Hand pickup: the client sends the piece it clicked; the server decides everything.
-- Works with any tool in hand. One piece or one pile per click.
---------------------------------------------------------------------
local flyInto -- assigned further down; collect needs it
local HAND_FLY_TIME = 0.3

local function collect(player: Player, piece: any)
	if typeof(piece) ~= "Instance" or not piece:IsA("BasePart") or piece.Parent ~= piecesFolder then
		return
	end
	if piece:GetAttribute("FlyTime") then
		return -- already flying into somebody's bag
	end
	if not canCollect(player) then
		return
	end
	local root = aliveRoot(player)
	if not root then
		return
	end
	if (root.Position - piece.Position).Magnitude > HAND_REACH + REACH_TOLERANCE + piece.Size.Magnitude / 2 then
		return
	end
	if not canClaim(player, piece) then
		Remotes.Notify:FireClient(player, "That piece is reserved for whoever broke it, just for a moment.", "Info")
		return
	end

	local free = InventoryService.GetFreeSpace(player)
	if free < 1 then
		noticeFull(player)
		return
	end

	local gains = {}
	local count = piece:GetAttribute("Count") or 1
	if count <= free and ItemDefinitions[piece:GetAttribute("ItemId")] then
		flyInto(player, piece, count, HAND_FLY_TIME)
		return
	end
	takeInto(player, piece, free, gains)
	sendGains(player, gains)
end

---------------------------------------------------------------------
-- Gear pickup (Brush, Vacuum): takes everything within `radius` studs of the aim point
---------------------------------------------------------------------
local function sweepInstant(player: Player, origin: Vector3, radius: number)
	local free = InventoryService.GetFreeSpace(player)
	if free < 1 then
		noticeFull(player)
		return
	end
	local gains = {}
	for _, piece in table.clone(live) do
		if free < 1 then
			break
		end
		if
			piece.Parent
			and (piece.Position - origin).Magnitude <= radius + piece.Size.Magnitude / 2
			and canClaim(player, piece)
		then
			free -= takeInto(player, piece, free, gains)
		end
	end
	sendGains(player, gains)
end

---------------------------------------------------------------------
-- Gear pickup with a fly-in: the real piece flies to the player and is collected on arrival.
-- The bag space is held (InventoryService.Reserve) from the moment the piece starts to fly.
---------------------------------------------------------------------
local FLY_TIME = { Brush = 0.55, Vacuum = 0.4 } -- seconds a piece flies before it is collected
local FLY_DEFAULT = 0.5

function flyInto(player: Player, piece: BasePart, amount: number, flyTime: number)
	local itemId = piece:GetAttribute("ItemId")
	local position = piece.Position

	-- out of the pickup lists, so nothing else can sweep it or merge into it
	removeFromLive(piece)
	settled[piece] = nil

	InventoryService.Reserve(player, amount)
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece:SetAttribute("FlyUserId", player.UserId)
	piece:SetAttribute("FlyTime", flyTime) -- the client animates the piece when it sees this

	task.delay(flyTime, function()
		InventoryService.Release(player, amount)
		local added = InventoryService.Add(player, itemId, amount)
		if piece.Parent then
			piece:Destroy()
		end
		if added > 0 then
			Remotes.LootDropped:FireClient(player, { { ItemId = itemId, Count = added, Position = position } })
		end
	end)
end

-- Takes everything within `radius` studs of the aim point. Whatever fits in the bag flies in.
local function sweep(player: Player, origin: Vector3, radius: number, gearId: string?)
	local free = InventoryService.GetFreeSpace(player)
	if free < 1 then
		noticeFull(player)
		return
	end
	local flyTime = FLY_TIME[gearId or ""] or FLY_DEFAULT
	local gains = {}
	for _, piece in table.clone(live) do
		if free < 1 then
			break
		end
		if
			piece.Parent
			and (piece.Position - origin).Magnitude <= radius + piece.Size.Magnitude / 2
			and canClaim(player, piece)
		then
			local amount = piece:GetAttribute("Count") or 1
			if amount <= free and ItemDefinitions[piece:GetAttribute("ItemId")] then
				flyInto(player, piece, amount, flyTime)
				free -= amount
			else
				-- a pile that only partly fits: take what fits right away, the rest stays on the ground
				free -= takeInto(player, piece, free, gains)
			end
		end
	end
	sendGains(player, gains)
end

-- The client sends only the aim point. The server checks the held tool, ownership, speed and reach.
local function onUseGear(player: Player, position: any)
	if typeof(position) ~= "Vector3" or position ~= position or position.Magnitude > 100000 then
		return
	end
	local root = aliveRoot(player)
	local data = PlayerDataService.Get(player)
	if not root or not data then
		return
	end
	local tool = (player.Character :: Model):FindFirstChildOfClass("Tool")
	local gearId = tool and tool:GetAttribute("GearId")
	local entry = gearId and gearById[gearId]
	if not entry or data.PickupTier < entry.Index then
		return
	end

	local def = entry.Def
	local now = os.clock()
	if lastGearUse[player] and now - lastGearUse[player] < def.Interval * 0.8 then
		return
	end
	lastGearUse[player] = now

	if (root.Position - position).Magnitude > def.Reach + REACH_TOLERANCE then
		return
	end
	sweep(player, position, def.Sweep, def.Id)
end

---------------------------------------------------------------------
-- Gear tools in the hotbar (placeholders unless ServerStorage.Assets.Tools has a Tool with the same name)
---------------------------------------------------------------------
local PLACEHOLDER = {
	Brush = { Color = Color3.fromRGB(170, 115, 80), Material = Enum.Material.Wood, Size = Vector3.new(0.6, 0.6, 2.4) },
	Vacuum = { Color = Color3.fromRGB(110, 120, 130), Material = Enum.Material.Metal, Size = Vector3.new(1, 1, 3) },
}

local function buildGearTool(def): Tool
	local assets = ServerStorage:FindFirstChild("Assets")
	local toolsFolder = assets and assets:FindFirstChild("Tools")
	local template = toolsFolder and toolsFolder:FindFirstChild(def.Id)

	local tool
	if template and template:IsA("Tool") then
		tool = template:Clone()
	else
		tool = Instance.new("Tool")
		local look = PLACEHOLDER[def.Id] or PLACEHOLDER.Brush
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = look.Size
		handle.Color = look.Color
		handle.Material = look.Material
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
	end
	tool.Name = def.Name
	tool.CanBeDropped = false
	tool.ToolTip = def.Description
	tool:SetAttribute("GearId", def.Id) -- set BEFORE parenting so the client sees it immediately
	return tool
end

local function containerHasGear(container: Instance?, gearId: string): boolean
	if not container then
		return false
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GearId") == gearId then
			return true
		end
	end
	return false
end

-- Puts every gear tool the player owns into their Backpack (skips ones they already have).
local function giveGear(player: Player)
	local data = PlayerDataService.Get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	for index, def in GameConfig.Pickup.Upgrades do
		if data.PickupTier >= index and not (containerHasGear(backpack, def.Id) or containerHasGear(player.Character, def.Id)) then
			buildGearTool(def).Parent = backpack
		end
	end
end

---------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------
-- eggModel: the live egg model (its Shell must still exist). layer: the layer that just broke.
function PieceService.SpawnPiece(eggModel: Model, patchIndex: number, layer: number, breaker: Player?)
	local data = patchRel[patchIndex]
	local shell = eggModel:FindFirstChild("Shell")
	local layerDef = EggDefinitions[EGG_TYPE].Layers[layer]
	if not data or not (shell and shell:IsA("BasePart")) or not layerDef then
		return nil
	end
	if not ItemDefinitions[layerDef.PieceItem] then
		warn("[PieceService] Unknown PieceItem " .. tostring(layerDef.PieceItem))
		return nil
	end

	-- The piece is sized like the patch at its layer, but starts at the OUTER surface: the layers
	-- above it are already open, so it comes out of the hole instead of falling inside the egg.
	local scale = 1 - (layer - 1) * EggDefinitions[EGG_TYPE].LayerStep
	local cf = shell.CFrame * (CFrame.new(data.Rel.Position) * data.Rel.Rotation)
	local outward = data.Rel.Position.Magnitude > 0.01 and shell.CFrame:VectorToWorldSpace(data.Rel.Position.Unit) or Vector3.yAxis

	-- Cap: the oldest piece goes first
	while #live >= MAX_PIECES do
		local oldest = table.remove(live, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local piece = data.Part:Clone()
	for _, name in { "Index", "Band", "Col" } do
		piece:SetAttribute(name, nil)
	end
	piece.Name = layerDef.PieceName
	piece.Size = data.Part.Size * scale * PIECE_SCALE
	baseSize[piece] = piece.Size
	local floorY = shell.Position.Y - shell.Size.Y / 2 + 1.5 -- never start below the ground the egg stands on
	local startCF = cf + outward * 2.5 -- just outside the egg so it never overlaps the Shell
	piece.CFrame = startCF + Vector3.new(0, math.max(0, floorY - startCF.Position.Y), 0)
	piece.Color = layerDef.Color
	piece.Material = layerDef.Material
	piece.Anchored = false
	piece.CanCollide = true
	piece.CanTouch = false
	piece.CanQuery = true
	piece:SetAttribute("ItemId", layerDef.PieceItem)
	piece:SetAttribute("Count", 1)
	if breaker then
		piece:SetAttribute("OwnerUserId", breaker.UserId)
		piece:SetAttribute("ClaimUntil", os.clock() + OWNER_WINDOW)
	end
	piece.Parent = piecesFolder
	piece:SetNetworkOwner(nil)

	local spread = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 6
	piece.AssemblyLinearVelocity = outward * 12 + Vector3.new(0, 10, 0) + spread
	piece.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6

	table.insert(live, piece)
	piece.AncestryChanged:Connect(function()
		if not piece.Parent then
			removeFromLive(piece)
			settled[piece] = nil
		end
	end)
	Debris:AddItem(piece, LIFETIME)

	-- After it has fallen, freeze it in place, stop it colliding, and let it join a pile
	task.delay(SETTLE_TIME, function()
		if piece.Parent then
			piece.AssemblyLinearVelocity = Vector3.zero
			piece.AssemblyAngularVelocity = Vector3.zero
			piece.Anchored = true
			piece.CanCollide = false
		end
	end)
	return piece
end

-- Removes every piece on the ground (used when the round ends).
function PieceService.ClearAll()
	for _, child in piecesFolder:GetChildren() do
		child:Destroy()
	end
	table.clear(live)
	table.clear(settled)
end

function PieceService.Init()
	Remotes = ReplicatedStorage:WaitForChild("Remotes")
	piecesFolder = Instance.new("Folder")
	piecesFolder.Name = "Pieces"
	piecesFolder.Parent = Workspace
	loadPatchTemplates()

	-- This service owns the gear remote, so it creates it here
	local useGear = Remotes:FindFirstChild("UseGear")
	if not useGear then
		useGear = Instance.new("RemoteEvent")
		useGear.Name = "UseGear"
		useGear.Parent = Remotes
	end
	Remotes.CollectDrop.OnServerEvent:Connect(collect)
	useGear.OnServerEvent:Connect(onUseGear)

	Workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
		if Workspace:GetAttribute("RoundState") == "Ended" then
			PieceService.ClearAll()
		end
	end)

	-- Gear tools follow the player's PickupTier: on spawn, and the moment they buy one
	local function setupPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.spawn(function()
				player:WaitForChild("Backpack")
				giveGear(player)
			end)
		end)
		player:GetAttributeChangedSignal("PickupTier"):Connect(function()
			giveGear(player)
		end)
		if player.Character then
			task.spawn(giveGear, player)
		end
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	print(string.format("[%s] Init OK", script.Name))
end

return PieceService