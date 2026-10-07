-- ClimbController: shows the green/red ghost for the Climb Rig and sends intent.
-- It computes nothing that matters: the server decides every placement.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local GEAR_ID = "ClimbRig"
local OK_COLOR = Color3.fromRGB(110, 235, 140)
local BAD_COLOR = Color3.fromRGB(255, 90, 90)

-- the same numbers as the server (replaced by ReplicatedStorage.ClimbRigConfig when it arrives)
local cfg = {
	MastMin = 24,
	MastMax = 36,
	PlaceReach = 45,
	ExtendReach = 16,
	MaxLevels = 5,
	MinSpacing = 9,
	MaxPerPlayer = 2,
	DeckWidth = 6,
	DeckStart = 1.5,
	ShellGap = 1.2,
	MinDeck = 3,
	FirstLevel = 10,
}
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("ClimbRigConfig", 30)
	if folder then
		for name in cfg do
			local value = folder:GetAttribute(name)
			if type(value) == "number" then
				cfg[name] = value
			end
		end
	end
end)

local placeRemote, extendRemote
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	placeRemote = remotes:WaitForChild("PlaceRig", 30)
	extendRemote = remotes:WaitForChild("ExtendRig", 30)
end)

-- the same aim position the rest of the client uses (finger / locked mouse / mouse)
local EggView = nil
task.spawn(function()
	local controllers = script.Parent:WaitForChild("Controllers", 10)
	local view = controllers and controllers:WaitForChild("EggView", 10)
	if view then
		local ok, module = pcall(require, view)
		if ok then
			EggView = module
		end
	end
end)

---------------------------------------------------------------------
-- Ghost and hint
---------------------------------------------------------------------
local ghostFolder = Instance.new("Folder")
ghostFolder.Name = "ClimbGhost"
ghostFolder.Parent = Workspace

local function ghostPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Parent = ghostFolder
	return part
end
local ghostMast = ghostPart("Mast")
local ghostDeck = ghostPart("Deck")
local ghostRing = ghostPart("Ring")
ghostRing.Shape = Enum.PartType.Cylinder

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Parent = ghostFolder

local gui = Instance.new("ScreenGui")
gui.Name = "ClimbHint"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -140)
hint.Size = UDim2.fromOffset(460, 28)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamBold
hint.TextSize = 18
hint.TextColor3 = Color3.new(1, 1, 1)
hint.TextStrokeTransparency = 0.35
hint.Visible = false
hint.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local current = nil -- what a click would do right now: { Mode, Ok, Position, Rig }

local function hideAll()
	ghostMast.Transparency = 1
	ghostDeck.Transparency = 1
	ghostRing.Transparency = 1
	highlight.Adornee = nil
	hint.Visible = false
	current = nil
end

local function setHint(text, ok)
	hint.Text = text
	hint.TextColor3 = if ok then OK_COLOR else BAD_COLOR
	hint.Visible = true
end

---------------------------------------------------------------------
-- Geometry (display only; the server repeats all of it)
---------------------------------------------------------------------
local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function findShell()
	local eggs = Workspace:FindFirstChild("Eggs")
	if not eggs then
		return nil
	end
	for _, model in eggs:GetChildren() do
		local shell = model:FindFirstChild("Shell")
		if shell and shell:IsA("BasePart") and not model:GetAttribute("Broken") then
			return shell
		end
	end
	return nil
end

local function deckLength(shell, base, toEgg, levelY, mastDist)
	local origin = Vector3.new(base.X, levelY, base.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { shell }
	local result = Workspace:Raycast(origin, toEgg * 80, params)
	local distance
	if result then
		distance = (result.Position - origin).Magnitude
	else
		local t = (levelY - shell.Position.Y) / (shell.Size.Y / 2)
		local radius = if math.abs(t) < 1 then (shell.Size.X / 2) * math.sqrt(1 - t * t) else 0
		distance = math.max(mastDist - radius, 0)
	end
	return math.max(distance - cfg.DeckStart - cfg.ShellGap, cfg.MinDeck)
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignoreList(forGround)
	local list = { ghostFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local names = { "Pieces", "ToolFX", "EggView", "SellFly" }
	if forGround then
		table.insert(names, "Eggs")
		table.insert(names, "ClimbRigs")
	end
	for _, name in names do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	return list
end

-- returns plan, reason. reason == nil means the spot is fine
local function planPlacement(root, hitPos)
	local shell = findShell()
	if not shell then
		return nil, "No egg to climb right now"
	end
	local centre = shell.Position
	local flat = Vector3.new(hitPos.X - centre.X, 0, hitPos.Z - centre.Z)
	local dist = flat.Magnitude
	if dist < 1 then
		return nil, "Aim at the ground beside the egg"
	end
	local snapped = math.clamp(dist, cfg.MastMin, cfg.MastMax)
	local dirOut = flat / dist
	local mastX = centre.X + dirOut.X * snapped
	local mastZ = centre.Z + dirOut.Z * snapped
	local eggBottomY = centre.Y - shell.Size.Y / 2

	groundParams.FilterDescendantsInstances = ignoreList(true)
	local ground = Workspace:Raycast(Vector3.new(mastX, eggBottomY + 60, mastZ), Vector3.new(0, -120, 0), groundParams)
	if not ground or ground.Normal.Y < 0.85 or math.abs(ground.Position.Y - eggBottomY) > 4 then
		return nil, "Can't put a ladder on that spot"
	end

	local base = ground.Position
	local plan = { Base = base, ToEgg = -dirOut, MastDist = snapped, Shell = shell, Hit = hitPos }
	if flatDistance(root.Position, base) > cfg.PlaceReach then
		return plan, "Too far away, walk closer"
	end
	local rigsFolder = Workspace:FindFirstChild("ClimbRigs")
	local mine = 0
	if rigsFolder then
		for _, rig in rigsFolder:GetChildren() do
			local mast = rig:FindFirstChild("Mast")
			if mast and flatDistance(mast.Position, base) < cfg.MinSpacing then
				return plan, "Too close to another ladder"
			end
			if rig:GetAttribute("OwnerUserId") == player.UserId then
				mine += 1
			end
		end
	end
	if mine >= cfg.MaxPerPlayer then
		return plan, string.format("You already have %d ladders out. Pick one up first", cfg.MaxPerPlayer)
	end
	return plan, nil
end

local function showGhost(plan, ok)
	local cf = CFrame.lookAt(plan.Base, plan.Base + plan.ToEgg)
	local color = if ok then OK_COLOR else BAD_COLOR
	local height = cfg.FirstLevel + 1.5
	ghostMast.Size = Vector3.new(2, height, 2)
	ghostMast.CFrame = cf * CFrame.new(0, height / 2, 0)
	local len = deckLength(plan.Shell, plan.Base, plan.ToEgg, plan.Base.Y + cfg.FirstLevel, plan.MastDist)
	ghostDeck.Size = Vector3.new(cfg.DeckWidth, 0.6, len)
	ghostDeck.CFrame = cf * CFrame.new(0, cfg.FirstLevel - 0.3, -(cfg.DeckStart + len / 2))
	ghostRing.Size = Vector3.new(0.15, 5, 5)
	ghostRing.CFrame = CFrame.new(plan.Base + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ghostMast.Color = color
	ghostDeck.Color = color
	ghostRing.Color = color
	ghostMast.Transparency = 0.6
	ghostDeck.Transparency = 0.6
	ghostRing.Transparency = 0.35
end

---------------------------------------------------------------------
-- Tool and click
---------------------------------------------------------------------
local function heldRigTool()
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GearId") == GEAR_ID then
			return child
		end
	end
	return nil
end

local hooked = setmetatable({}, { __mode = "k" })
local lastClick = 0
local function hookTool(tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastClick < 0.25 then
			return
		end
		local c = current
		if not c or not c.Ok then
			return
		end
		lastClick = now
		if c.Mode == "place" and placeRemote then
			placeRemote:FireServer(c.Position) -- intent only: the server snaps, checks and builds
		elseif c.Mode == "extend" and extendRemote and c.Rig and c.Rig.Parent then
			extendRemote:FireServer(c.Rig)
		end
	end)
end

local function aimRay(camera)
	local pos = nil
	if EggView and EggView.GetScreenAim then
		local ok, value = pcall(EggView.GetScreenAim)
		if ok and typeof(value) == "Vector2" then
			pos = value
		end
	end
	if not pos then
		pos = UserInputService:GetMouseLocation()
	end
	return camera:ViewportPointToRay(pos.X, pos.Y)
end

local function update()
	local camera = Workspace.CurrentCamera
	local tool = heldRigTool()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not tool or not camera or not root or camera.CameraType ~= Enum.CameraType.Custom then
		hideAll()
		return
	end
	hookTool(tool)

	local ray = aimRay(camera)
	aimParams.FilterDescendantsInstances = ignoreList(false)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 150, aimParams)
	if not hit then
		hideAll()
		return
	end

	-- aimed at a ladder: click adds a level
	local rigsFolder = Workspace:FindFirstChild("ClimbRigs")
	if rigsFolder and hit.Instance:IsDescendantOf(rigsFolder) then
		local rig = hit.Instance:FindFirstAncestorOfClass("Model")
		if rig and rig.Parent == rigsFolder then
			local levels = rig:GetAttribute("Levels") or 1
			local mast = rig:FindFirstChild("Mast")
			local ok = true
			local text = string.format("Click: add level %d of %d", levels + 1, cfg.MaxLevels)
			if levels >= cfg.MaxLevels then
				ok = false
				text = "This ladder is fully built"
			elseif mast and flatDistance(root.Position, mast.Position) > cfg.ExtendReach then
				ok = false
				text = "Step closer to add a level"
			end
			current = { Mode = "extend", Ok = ok, Rig = rig }
			ghostMast.Transparency = 1
			ghostDeck.Transparency = 1
			ghostRing.Transparency = 1
			highlight.Adornee = rig
			highlight.OutlineColor = if ok then OK_COLOR else BAD_COLOR
			setHint(text, ok)
			return
		end
	end

	-- otherwise: click puts up a new ladder
	highlight.Adornee = nil
	local plan, reason = planPlacement(root, hit.Position)
	if not plan then
		ghostMast.Transparency = 1
		ghostDeck.Transparency = 1
		ghostRing.Transparency = 1
		current = nil
		setHint(reason or "", false)
		return
	end
	local ok = reason == nil
	showGhost(plan, ok)
	current = { Mode = "place", Ok = ok, Position = hit.Position }
	setHint(if ok then "Click: put up a ladder" else reason, ok)
end

local warned = false
RunService:BindToRenderStep("ClimbGhost", Enum.RenderPriority.Camera.Value + 2, function()
	local ok, err = pcall(update)
	if not ok and not warned then
		warned = true
		warn("[ClimbController] " .. tostring(err))
	end
end)

print("[ClimbController] Init OK")
