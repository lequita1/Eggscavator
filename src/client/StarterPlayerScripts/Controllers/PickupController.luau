local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EggView = require(script.Parent.EggView)

local PickupController = {}

local RAY_LENGTH = 200
local CLICK_COOLDOWN = 0.12
local HAND_REACH = GameConfig.Pickup.Start.Reach + 2 -- a little stricter than the server's check
local OUTLINE = Color3.fromRGB(255, 220, 120)
local RING_OK = Color3.fromRGB(255, 210, 90)
local RING_FAR = Color3.fromRGB(255, 90, 90)

local player = Players.LocalPlayer
local CollectDrop: RemoteEvent
local UseGear: RemoteEvent? -- found a moment after start (the server creates it)
local piecesFolder: Folder
local highlight: Highlight
local ring: Part
local started = false
local lastSent = 0

local gearById = {}
for _, def in GameConfig.Pickup.Upgrades do
	gearById[def.Id] = def
end

local params = RaycastParams.new() -- hand pickup: only pieces and eggs
params.FilterType = Enum.RaycastFilterType.Include
local gearParams = RaycastParams.new() -- gear aim: everything except you and the ring
gearParams.FilterType = Enum.RaycastFilterType.Exclude

-- The pickup gear tool in the player's hand, if any
local function heldGear()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("GearId")
	return id and gearById[id] or nil
end

-- Where the player is aiming on screen: the center for gamepad or a locked mouse, else the cursor.
local function aimPosition(): Vector2
	local camera = Workspace.CurrentCamera
	if
		UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
		or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	then
		return camera.ViewportSize / 2
	end
	return EggView.GetScreenAim()
end

-- Hand pickup: the piece under a screen position, if it is close enough. The egg is in the ray
-- filter too, so a piece hidden behind the egg cannot be clicked through it.
local function pieceAt(screenPosition: Vector2): BasePart?
	if not started then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	local piece = result and result.Instance
	if not piece or piece.Parent ~= piecesFolder then
		return nil
	end
	if (root.Position - piece.Position).Magnitude > HAND_REACH + piece.Size.Magnitude / 2 then
		return nil
	end
	return piece
end

-- Gear aim: the point in the world under the aim, and whether it is within the gear's reach.
local function gearAim(screenPosition: Vector2, def)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root or not started then
		return nil
	end
	gearParams.FilterDescendantsInstances = { character, ring }
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, gearParams)
	if not result then
		return nil
	end
	return result.Position, (root.Position - result.Position).Magnitude <= def.Reach + 2
end

-- ToolController asks this before it swings: a piece under the aim wins over the egg behind it.
function PickupController.PieceUnderAim(): BasePart?
	return pieceAt(aimPosition())
end

---------------------------------------------------------------------
-- Gear tools: click (Brush) or hold (Vacuum) sends the aim point
---------------------------------------------------------------------
local hookedGear = setmetatable({}, { __mode = "k" })

local function hookGear(tool: Tool)
	local def = gearById[tool:GetAttribute("GearId")]
	if not def or hookedGear[tool] then
		return
	end
	hookedGear[tool] = true

	local holding = false
	local loopId = 0
	local lastUse = 0

	local function use()
		local now = os.clock()
		if now - lastUse < def.Interval then
			return
		end
		local position, inReach = gearAim(aimPosition(), def)
		if UseGear and position and inReach then
			lastUse = now
			UseGear:FireServer(position) -- intent only: the server checks the tool, reach and speed
		end
	end

	tool.Activated:Connect(function()
		use()
		if not def.Hold then
			return
		end
		holding = true
		loopId += 1
		local myLoop = loopId
		while holding and loopId == myLoop and tool.Parent == player.Character do
			task.wait(def.Interval)
			if holding and loopId == myLoop then
				use()
			end
		end
	end)
	tool.Deactivated:Connect(function()
		holding = false
	end)
	tool.Unequipped:Connect(function()
		holding = false
	end)
end

local function onCharacter(character: Model)
	local function check(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("GearId") then
			hookGear(child)
		end
	end
	character.ChildAdded:Connect(check)
	for _, child in character:GetChildren() do
		check(child)
	end
end

function PickupController.Init()
	CollectDrop = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectDrop")

	highlight = Instance.new("Highlight")
	highlight.Name = "PickupHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = OUTLINE
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	local highlightHome = Instance.new("Folder") -- an empty parent: with nothing selected the highlight outlines nothing
	highlightHome.Name = "PickupHighlightHome"
	highlightHome.Parent = Workspace
	highlight.Parent = highlightHome

	-- The flat ring that shows where the Brush or Vacuum will sweep
	ring = Instance.new("Part")
	ring.Name = "GearRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Transparency = 1
	ring.Parent = Workspace

	RunService.RenderStepped:Connect(function()
		if not started then
			return
		end
		local def = heldGear()
		if def then
			highlight.Adornee = nil
			local position, inReach = gearAim(aimPosition(), def)
			if position then
				ring.Size = Vector3.new(0.2, def.Sweep * 2, def.Sweep * 2)
				ring.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				ring.Color = if inReach then RING_OK else RING_FAR
				ring.Transparency = 1
			else
				ring.Transparency = 1
			end
		else
			ring.Transparency = 1
			highlight.Adornee = pieceAt(aimPosition())
		end
	end)

	-- Hand pickup (not while a gear tool is in hand: its own click does the picking up)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or heldGear() then
			return
		end
		local position
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			position = Workspace.CurrentCamera.ViewportSize / 2
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			position = aimPosition()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			position = Vector2.new(input.Position.X, input.Position.Y + GuiService:GetGuiInset().Y)
		else
			return
		end

		local now = os.clock()
		if now - lastSent < CLICK_COOLDOWN then
			return
		end
		local piece = pieceAt(position)
		if piece then
			lastSent = now
			CollectDrop:FireServer(piece) -- intent only: the server checks reach, claim and space
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	-- Everything that waits runs in its own thread so the other controllers start right away.
	task.spawn(function()
		local pieces = Workspace:WaitForChild("Pieces", 30)
		local eggs = Workspace:WaitForChild("Eggs", 30)
		UseGear = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UseGear", 30)
		if not pieces or not eggs then
			warn("[PickupController] Workspace.Pieces or Workspace.Eggs not found")
			return
		end
		piecesFolder = pieces
		params.FilterDescendantsInstances = { pieces, eggs }
		started = true
		print("[PickupController] Init OK")
	end)
end

return PickupController