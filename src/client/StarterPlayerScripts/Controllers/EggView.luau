local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EggDefinitions = require(ReplicatedStorage.Shared.EggDefinitions)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local EggView = {}

---------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------
local EGG_TYPE = "Stonehatch"
local RAY_LENGTH = 500
local DEBUG_PATCH_COLORS = false -- true: every patch gets its own color (to check aim and patch edges)

local CRACK_COLOR = Color3.fromRGB(28, 22, 20)
local CRACK_WIDTH = 0.09
local CRACK_SEGMENTS = 5 -- segments per crack
local CRACKS_AT_STAGE = { 2, 4, 7 } -- total cracks on a patch at stage 1, 2, 3
local MAX_CRACK_SEGMENTS = GameConfig.FX.MaxCrackSegments -- global cap (300)
local MAX_DEBRIS = 40 -- live flying chips (client-only effect)

local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 60, 60)

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local player = Players.LocalPlayer
local definition = EggDefinitions[EGG_TYPE]
local layers = definition.Layers
local layerCount = #layers
local layerStep = definition.LayerStep
local LAYER_GROW = 0.15 -- studs each deeper layer is a hair wider, so wall planes of different layers never coincide (try 0.3 if stripes remain, 0.08 if thin gaps show)

local started = false
local viewRoot: Folder -- Workspace.EggView (exists only on this client)
local highlight: Highlight
local patchCount = 0
local templates = {} -- [index] = { Part, Rel } (Rel = patch CFrame relative to the template Shell)
local views = {} -- [eggModel] = egg view
local building = {} -- [eggModel] = true while it waits to be built
local partInfo = setmetatable({}, { __mode = "k" }) -- [part] = { Egg, Index }
local crackedEntries = {} -- set of entries that currently have crack parts
local crackTotal = 0
local debrisCount = 0

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Include
local crackParams = RaycastParams.new()
crackParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function scaleOf(layer: number): number
	return 1 - (layer - 1) * layerStep
end

local function layerColor(index: number, layer: number): Color3
	if DEBUG_PATCH_COLORS then
		return Color3.fromHSV((index * 0.137) % 1, 0.6, 0.9)
	end
	local base = layers[layer].Color
	local f = 1 -- slight tint per patch
	return Color3.new(math.min(base.R * f, 1), math.min(base.G * f, 1), math.min(base.B * f, 1))
end

-- PatchHP digit (1..9, ceil of fraction * 9) -> crack stage 0..3
local function stageFromDigit(digit: number): number
	if digit <= 2 then
		return 3
	elseif digit <= 4 then
		return 2
	elseif digit <= 6 then
		return 1
	end
	return 0
end

local function eggById(eggId)
	for _, egg in views do
		if egg.EggId == eggId then
			return egg
		end
	end
	return nil
end

---------------------------------------------------------------------
-- Effects (client only, capped)
---------------------------------------------------------------------
local function burst(egg, position: Vector3, color: Color3, count: number, speed: number)
	local outward = position - egg.Center
	outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.yAxis
	for _ = 1, count do
		if debrisCount >= MAX_DEBRIS then
			return
		end
		debrisCount += 1
		local size = 0.25 + math.random() * 0.35
		local chip = Instance.new("Part")
		chip.Size = Vector3.new(size, size * 0.6, size)
		chip.Color = color
		chip.Material = Enum.Material.Slate
		chip.CanCollide = false
		chip.CanTouch = false
		chip.CanQuery = false
		chip.CastShadow = false
		chip.CFrame = CFrame.new(position + outward * 0.5)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chip.Parent = viewRoot
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		chip.AssemblyLinearVelocity = (outward + spread) * speed
		Debris:AddItem(chip, 1.2)
		task.delay(1.2, function()
			debrisCount -= 1
		end)
	end
end

---------------------------------------------------------------------
-- Cracks: thin dark segments placed by raycast onto the patch, capped globally
---------------------------------------------------------------------
local function clearCracks(entry, evicted: boolean?)
	for _, part in entry.Cracks do
		part:Destroy()
	end
	crackTotal -= #entry.Cracks
	entry.Cracks = {}
	entry.CracksBuilt = 0
	entry.Stage = 0
	entry.Evicted = evicted == true
	crackedEntries[entry] = nil
end

local function makeRoom(needed: number, except)
	while crackTotal + needed > MAX_CRACK_SEGMENTS do
		local oldest, oldestTime = nil, nil
		for entry in crackedEntries do
			if entry ~= except and (not oldestTime or entry.Touched < oldestTime) then
				oldest, oldestTime = entry, entry.Touched
			end
		end
		if not oldest then
			return
		end
		clearCracks(oldest, true)
	end
end

local function buildCrack(egg, entry, crackIndex: number)
	local part = entry.Cur
	if not part then
		return
	end
	local center = part.Position
	local n = center - egg.Center
	n = if n.Magnitude > 0.01 then n.Unit else Vector3.yAxis
	local t1 = n:Cross(Vector3.yAxis)
	if t1.Magnitude < 0.2 then
		t1 = n:Cross(Vector3.xAxis) -- near the top and bottom caps
	end
	t1 = t1.Unit
	local t2 = n:Cross(t1)

	local rng = Random.new(entry.Index * 131 + entry.Layer * 7919 + crackIndex * 17)
	crackParams.FilterDescendantsInstances = { part }
	local angle = rng:NextNumber(0, math.pi * 2)
	local point = center + t1 * rng:NextNumber(-1.5, 1.5) + t2 * rng:NextNumber(-1.5, 1.5)
	local previous = nil

	for _ = 0, CRACK_SEGMENTS do
		local hit = Workspace:Raycast(point + n * 4, -n * 8, crackParams)
		if not hit then
			break -- walked off the patch
		end
		local position = hit.Position + hit.Normal * 0.04
		if previous then
			local length = (position - previous).Magnitude
			if length > 0.05 then
				local seg = Instance.new("Part")
				seg.Size = Vector3.new(CRACK_WIDTH, CRACK_WIDTH, length + 0.05)
				seg.CFrame = CFrame.lookAt((position + previous) / 2, position)
				seg.Color = CRACK_COLOR
				seg.Material = Enum.Material.SmoothPlastic
				seg.Anchored = true
				seg.CanCollide = false
				seg.CanTouch = false
				seg.CanQuery = false
				seg.CastShadow = false
				seg.Parent = egg.Folder
				table.insert(entry.Cracks, seg)
				crackTotal += 1
			end
		end
		previous = position
		angle += rng:NextNumber(-0.7, 0.7)
		point += (t1 * math.cos(angle) + t2 * math.sin(angle)) * rng:NextNumber(0.5, 0.9)
	end
end

-- force = a real hit just happened (may evict the oldest cracks); otherwise stay within the cap
local function setStage(egg, entry, target: number, force: boolean)
	if target <= entry.Stage or not entry.Cur then
		return
	end
	if entry.Evicted and not force then
		return
	end
	local want = CRACKS_AT_STAGE[target]
	local needed = (want - entry.CracksBuilt) * CRACK_SEGMENTS
	if crackTotal + needed > MAX_CRACK_SEGMENTS then
		if not force then
			return
		end
		makeRoom(needed, entry)
	end
	entry.Evicted = false
	for crackIndex = entry.CracksBuilt + 1, want do
		buildCrack(egg, entry, crackIndex)
	end
	entry.CracksBuilt = want
	entry.Stage = target
	crackedEntries[entry] = true
end

---------------------------------------------------------------------
-- Patch parts (only the current layer and the one under it exist)
---------------------------------------------------------------------
local function makePart(egg, index: number, layer: number, queryable: boolean)
	local template = templates[index]
	local s = scaleOf(layer)
	local part = template.Part:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = queryable
	part.Size = template.Part.Size * s + Vector3.one * ((layer - 1) * LAYER_GROW)
	local rel = template.Rel
	part.CFrame = egg.ShellCF * (CFrame.new(rel.Position * s) * rel.Rotation)
	part.Color = layerColor(index, layer)
	part.Material = layers[layer].Material
	partInfo[part] = { Egg = egg, Index = index }
	part.Parent = egg.Folder
	return part
end

local function setLayer(egg, entry, newLayer: number)
	local old = entry.Layer
	if old == newLayer then
		return
	end

	if old and entry.Cur and newLayer > old then
		burst(egg, entry.Cur.Position, layers[old].Color, if newLayer > layerCount then 10 else 6, 16)
	end
	clearCracks(entry)

	if entry.Nxt and entry.NxtLayer == newLayer then
		-- the layer underneath becomes the visible one
		if entry.Cur then
			entry.Cur:Destroy()
		end
		entry.Cur = entry.Nxt
		entry.Cur.CanQuery = true
		entry.Nxt, entry.NxtLayer = nil, nil
	else
		if entry.Cur then
			entry.Cur:Destroy()
		end
		if entry.Nxt then
			entry.Nxt:Destroy()
		end
		entry.Cur, entry.Nxt, entry.NxtLayer = nil, nil, nil
		if newLayer <= layerCount then
			entry.Cur = makePart(egg, entry.Index, newLayer, true)
		end
	end

	entry.Layer = newLayer
	if newLayer + 1 <= layerCount and not entry.Nxt then
		entry.Nxt = makePart(egg, entry.Index, newLayer + 1, false)
		entry.NxtLayer = newLayer + 1
	end
end

---------------------------------------------------------------------
-- Egg views
---------------------------------------------------------------------
-- The server attributes PatchLayer / PatchHP are the single source of truth.
local function syncEgg(egg)
	local model = egg.Model
	local layerString = model:GetAttribute("PatchLayer")
	local hpString = model:GetAttribute("PatchHP")
	if type(layerString) ~= "string" or type(hpString) ~= "string" then
		return
	end
	if layerString == egg.LastLayers and hpString == egg.LastHP then
		return
	end
	egg.LastLayers, egg.LastHP = layerString, hpString

	local now = os.clock()
	for index, entry in egg.Entries do
		local layer = tonumber(string.sub(layerString, index, index))
		local digit = tonumber(string.sub(hpString, index, index))
		if layer then
			setLayer(egg, entry, layer)
			if layer <= layerCount and digit and digit > 0 then
				local target = stageFromDigit(digit)
				if target > entry.Stage then
					entry.Touched = now
					setStage(egg, entry, target, false)
				end
			end
		end
	end
end

local function scheduleSync(egg)
	if egg.Pending then
		return
	end
	egg.Pending = true
	task.defer(function()
		egg.Pending = false
		if egg.Alive then
			syncEgg(egg)
		end
	end)
end

local function destroyView(egg)
	if not egg.Alive then
		return
	end
	egg.Alive = false
	for _, connection in egg.Conns do
		connection:Disconnect()
	end
	for _, entry in egg.Entries do
		clearCracks(entry)
	end
	if highlight.Adornee and highlight.Adornee:IsDescendantOf(egg.Folder) then
		highlight.Adornee = nil
	end
	egg.Folder:Destroy()
	views[egg.Model] = nil
end

local function shatter(egg)
	if egg.Shattering or not egg.Alive then
		return
	end
	egg.Shattering = true
	for _, entry in egg.Entries do
		clearCracks(entry)
	end
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function fade(part)
		if not part then
			return
		end
		part.CanQuery = false
		local outward = part.Position - egg.Center
		outward = if outward.Magnitude > 0.01 then outward.Unit * 10 else Vector3.yAxis * 10
		TweenService:Create(part, info, { CFrame = part.CFrame + outward, Transparency = 1 }):Play()
	end
	for _, entry in egg.Entries do
		fade(entry.Cur)
		fade(entry.Nxt)
	end
	task.delay(1.1, function()
		destroyView(egg)
	end)
end

local function buildEgg(model: Instance)
	if not model:IsA("Model") or views[model] or building[model] then
		return
	end
	building[model] = true

	local shell = model:WaitForChild("Shell", 10)
	if shell and model.Parent and model:GetAttribute("PatchLayer") == nil then
		model:GetAttributeChangedSignal("PatchLayer"):Wait()
	end
	building[model] = nil
	if not (shell and shell:IsA("BasePart")) or not model.Parent or views[model] then
		return
	end
	if model:GetAttribute("Broken") then
		return -- the shell is already gone
	end

	local egg = {
		Model = model,
		EggId = model:GetAttribute("EggId") or model.Name,
		ShellCF = shell.CFrame,
		Center = shell.Position,
		Entries = {},
		Folder = Instance.new("Folder"),
		Conns = {},
		Alive = true,
	}
	egg.Folder.Name = model.Name
	egg.Folder.Parent = viewRoot
	for index = 1, patchCount do
		egg.Entries[index] = {
			Index = index,
			Layer = nil,
			Cur = nil,
			Nxt = nil,
			NxtLayer = nil,
			Stage = 0,
			Cracks = {},
			CracksBuilt = 0,
			Evicted = false,
			Touched = 0,
		}
	end
	views[model] = egg

	-- Hide the real Shell on this client only (it stays for collision and server checks)
	shell.LocalTransparencyModifier = 1

	-- BEGIN YOLK
	-- A glowing solid egg inside the deepest layer, so seams and holes never show an empty cavity.
	-- Client only, never queried, and it lives in the egg's folder so it is cleaned up with the egg.
	local okYolk, errYolk = pcall(function()
		local YOLK_SCALE = 0.70 -- the deepest tile layer sits at about 0.66, so keep this below that
		local tplYolk = game:GetService("ReplicatedStorage"):FindFirstChild("EggYolk")
		local yolk = (tplYolk or shell):Clone()
		for _, child in yolk:GetChildren() do
			child:Destroy()
		end
		yolk.Name = "Yolk"
		yolk.LocalTransparencyModifier = 0
		yolk.Anchored = true
		yolk.CanCollide = false
		yolk.CanQuery = false
		yolk.CanTouch = false
		yolk.CastShadow = false
		yolk.Massless = true
		yolk.Transparency = 0
		yolk.Material = Enum.Material.SmoothPlastic
		yolk.Color = Color3.fromRGB(205, 95, 25)
		if not tplYolk then yolk.Size = shell.Size * YOLK_SCALE end
		yolk.CFrame = if tplYolk then shell.CFrame * (tplYolk:GetAttribute("YolkCFrame") or CFrame.identity) else shell.CFrame
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 170, 70)
		glow.Brightness = 0.7
		glow.Range = 30
		glow.Shadows = false
		glow.Parent = yolk
		yolk.Parent = egg.Folder
		egg.Yolk = yolk
	end)
	if not okYolk then
		warn("[EggView] yolk: " .. tostring(errYolk))
	end
	-- END YOLK

	syncEgg(egg)
	table.insert(egg.Conns, model:GetAttributeChangedSignal("PatchLayer"):Connect(function()
		scheduleSync(egg)
	end))
	table.insert(egg.Conns, model:GetAttributeChangedSignal("PatchHP"):Connect(function()
		scheduleSync(egg)
	end))
	table.insert(egg.Conns, model:GetAttributeChangedSignal("Broken"):Connect(function()
		if model:GetAttribute("Broken") then
			shatter(egg)
		end
	end))
end

---------------------------------------------------------------------
-- Remote events
---------------------------------------------------------------------
-- EggHit: eggId, hitPosition, applied, false, toolId, nil, patchIndex, hpFraction, layerAfter
local function onEggHit(eggId, hitPosition, _applied, _, _toolId, _, patchIndex, hpFraction, layerAfter)
	local egg = eggById(eggId)
	if not egg or type(patchIndex) ~= "number" then
		return
	end
	local entry = egg.Entries[patchIndex]
	if not entry or not entry.Layer or entry.Layer > layerCount then
		return
	end
	entry.Touched = os.clock()
	burst(egg, hitPosition, layers[entry.Layer].Color, 2, 10)

	if layerAfter == entry.Layer and type(hpFraction) == "number" then
		local digit = math.clamp(math.ceil(hpFraction * 9 - 1e-6), 1, 9)
		local target = stageFromDigit(digit)
		if target > entry.Stage then
			setStage(egg, entry, target, true)
		end
	end
end

local function onEggBroken(eggId)
	local egg = eggById(eggId)
	if egg then
		shatter(egg)
	end
end

---------------------------------------------------------------------
-- Aim (used by ToolController and the hover outline)
---------------------------------------------------------------------
local lastTouch = nil
local function rememberTouch(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouch = Vector2.new(input.Position.X, input.Position.Y + game:GetService("GuiService"):GetGuiInset().Y)
	end
end
UserInputService.InputBegan:Connect(rememberTouch)
UserInputService.InputChanged:Connect(rememberTouch)

-- Where the player is aiming on screen: the last touch on a phone, else the mouse cursor.
function EggView.GetScreenAim(): Vector2
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter and Workspace.CurrentCamera then
		return Workspace.CurrentCamera.ViewportSize / 2
	end
	if lastTouch and UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		return lastTouch
	end
	return UserInputService:GetMouseLocation()
end

local function aimRay()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local screenPosition
	if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
		screenPosition = camera.ViewportSize / 2
	else
		screenPosition = EggView.GetScreenAim()
	end
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, aimParams)
	if not result then
		return nil
	end
	local info = partInfo[result.Instance]
	if not info then
		return nil
	end
	return info, result
end

-- Returns eggId, hitPosition, patchIndex (or nil if no patch is under the aim).
function EggView.GetAim()
	if not started then
		return nil
	end
	local info, result = aimRay()
	if not info then
		return nil
	end
	return info.Egg.EggId, result.Position, info.Index
end

local function updateHover()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("ToolId") then
		highlight.Adornee = nil
		return
	end
	local info, result = aimRay()
	if not info then
		highlight.Adornee = nil
		return
	end
	local entry = info.Egg.Entries[info.Index]
	local layerDef = entry and entry.Layer and layers[entry.Layer]
	if not layerDef then
		highlight.Adornee = nil
		return
	end
	local power = tool:GetAttribute("Power") or 1
	highlight.Adornee = result.Instance
	highlight.OutlineColor = if power >= layerDef.Hardness then WHITE else RED
end

---------------------------------------------------------------------
function EggView.Init()
	viewRoot = Instance.new("Folder")
	viewRoot.Name = "EggView"
	viewRoot.Parent = Workspace
	aimParams.FilterDescendantsInstances = { viewRoot }

	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineColor = WHITE
	highlight.Parent = viewRoot

	RunService.RenderStepped:Connect(function()
		if started then
			updateHover()
		end
	end)

	-- Everything that waits runs in its own thread so the other controllers start right away.
	task.spawn(function()
		local root = ReplicatedStorage:WaitForChild("EggPatches", 15)
		local folder = root and root:WaitForChild(EGG_TYPE, 15)
		if not folder then
			warn("[EggView] ReplicatedStorage.EggPatches." .. EGG_TYPE .. " not found")
			return
		end
		local folderShellCF = folder:GetAttribute("ShellCFrame")
		if typeof(folderShellCF) ~= "CFrame" then
			warn("[EggView] EggPatches folder has no ShellCFrame attribute")
			return
		end
		for _, part in folder:GetChildren() do
			local index = part:GetAttribute("Index")
			if part:IsA("BasePart") and type(index) == "number" then
				templates[index] = { Part = part, Rel = folderShellCF:ToObjectSpace(part.CFrame) }
				patchCount += 1
			end
		end
		for index = 1, patchCount do
			if not templates[index] then
				warn("[EggView] Patch Index " .. index .. " is missing")
				return
			end
		end

		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		remotes:WaitForChild("EggHit").OnClientEvent:Connect(onEggHit)
		remotes:WaitForChild("EggBroken").OnClientEvent:Connect(onEggBroken)

		local eggsFolder = Workspace:WaitForChild("Eggs")
		eggsFolder.ChildAdded:Connect(function(model)
			task.spawn(buildEgg, model)
		end)
		eggsFolder.ChildRemoved:Connect(function(model)
			local egg = views[model]
			if egg then
				destroyView(egg)
			end
		end)
		for _, model in eggsFolder:GetChildren() do
			task.spawn(buildEgg, model)
		end

		started = true
		print(string.format("[EggView] Init OK (%d patches)", patchCount))
	end)
end

return EggView