-- ClimbService: the carried, team-shared Climb Rig (server side).
-- The server decides everything. The client only sends intent (PlaceRig, ExtendRig).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
while not Remotes:GetAttribute("Ready") do
	task.wait(0.1)
end

---------------------------------------------------------------------
-- Settings (the client reads these from ReplicatedStorage.ClimbRigConfig)
---------------------------------------------------------------------
local GEAR_ID = "ClimbRig"
local LEVEL_HEIGHTS = { 10, 20, 30, 40, 48 } -- studs above the ground, one per level
local MAX_LEVELS = #LEVEL_HEIGHTS
local MAX_RIGS_PER_PLAYER = 2
local MAST_MIN = 24 -- the ladder stands at least this far from the egg centre (flat distance)...
local MAST_MAX = 36 -- ...and at most this far
local PLACE_REACH = 45 -- how far from you the spot may be
local EXTEND_REACH = 16 -- how close you must stand to add a level
local MIN_SPACING = 9 -- studs between two ladders
local DECK_WIDTH = 6
local DECK_THICK = 0.6
local DECK_START = 1.5 -- a deck begins this far from the ladder centre, towards the egg
local SHELL_GAP = 1.2 -- ...and stops this far from the egg
local MIN_DECK = 3
local TRUSS_EXTRA = 1.5 -- the ladder is this much taller than the top deck

local settings = {
	MastMin = MAST_MIN,
	MastMax = MAST_MAX,
	PlaceReach = PLACE_REACH,
	ExtendReach = EXTEND_REACH,
	MaxLevels = MAX_LEVELS,
	MinSpacing = MIN_SPACING,
	MaxPerPlayer = MAX_RIGS_PER_PLAYER,
	DeckWidth = DECK_WIDTH,
	DeckStart = DECK_START,
	ShellGap = SHELL_GAP,
	MinDeck = MIN_DECK,
	FirstLevel = LEVEL_HEIGHTS[1],
}
local cfgFolder = ReplicatedStorage:FindFirstChild("ClimbRigConfig")
if not cfgFolder then
	cfgFolder = Instance.new("Folder")
	cfgFolder.Name = "ClimbRigConfig"
	cfgFolder.Parent = ReplicatedStorage
end
for name, value in settings do
	cfgFolder:SetAttribute(name, value)
end

local function getRemote(name)
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = Remotes
	end
	return remote
end
local placeRemote = getRemote("PlaceRig")
local extendRemote = getRemote("ExtendRig")

local rigsFolder = Workspace:FindFirstChild("ClimbRigs")
if not rigsFolder then
	rigsFolder = Instance.new("Folder")
	rigsFolder.Name = "ClimbRigs"
	rigsFolder.Parent = Workspace
end

local rigs = setmetatable({}, { __mode = "k" }) -- [model] = info

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------
local buckets = {}
local function allow(player, key, ratePerSec, burst)
	local now = os.clock()
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local b = mine[key]
	if not b then
		b = { tokens = burst, last = now }
		mine[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * ratePerSec)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function notify(player, message, kind)
	local remote = Remotes:FindFirstChild("Notify")
	if remote then
		remote:FireClient(player, message, kind or "warning")
	end
end

local function aliveRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

local function holdsRigTool(player)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("GearId") == GEAR_ID
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- the live egg's Shell (the ladder is built around it)
local function findEgg()
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

local function groundAt(x, z, eggBottomY)
	local ignore = { rigsFolder }
	for _, name in { "Eggs", "Pieces" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(Vector3.new(x, eggBottomY + 60, z), Vector3.new(0, -120, 0), params)
	if not result or result.Normal.Y < 0.85 then
		return nil
	end
	if math.abs(result.Position.Y - eggBottomY) > 4 then
		return nil
	end
	return result.Position
end

-- how long a deck at this height must be to end just before the egg
local function deckLengthAt(info, rel)
	local levelY = info.Base.Y + rel
	local origin = Vector3.new(info.Base.X, levelY, info.Base.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { info.Shell }
	local result = Workspace:Raycast(origin, info.ToEgg * 80, params)
	local distance
	if result then
		distance = (result.Position - origin).Magnitude
	else
		local shell = info.Shell
		local t = (levelY - shell.Position.Y) / (shell.Size.Y / 2)
		local radius = if math.abs(t) < 1 then (shell.Size.X / 2) * math.sqrt(1 - t * t) else 0
		distance = math.max(info.MastDist - radius, 0)
	end
	return math.max(distance - DECK_START - SHELL_GAP, MIN_DECK)
end

local function newPart(model, name, size, cf, color, material, solid)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid
	part.CanQuery = solid
	part.CanTouch = false
	part.CastShadow = solid
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

---------------------------------------------------------------------
-- LOOK: only decoration (nothing here can be climbed or walked on).
-- info.CF: at the ground under the ladder, -Z points at the egg, +Y is up.
---------------------------------------------------------------------
-- BEGIN LOOK
-- Expedition scaffold: dark wood, rope, brass, canvas and lanterns.
-- Only decoration lives here (nothing in this block is solid), so it can never break the climbing.
local WOOD = Color3.fromRGB(112, 78, 46)
local WOOD_DARK = Color3.fromRGB(78, 54, 34)
local WOOD_LIGHT = Color3.fromRGB(150, 108, 66)
local ROPE = Color3.fromRGB(196, 166, 112)
local BRASS = Color3.fromRGB(205, 160, 70)
local IRON = Color3.fromRGB(58, 60, 66)
local CANVAS = Color3.fromRGB(232, 218, 186)
local SAND = Color3.fromRGB(190, 168, 120)
local AMBER = Color3.fromRGB(255, 190, 80)
local Material = Enum.Material

local function at(info, x, y, z)
	return info.CF * Vector3.new(x, y, z)
end

-- a block at local ladder coordinates (x right, y up, z towards the OUTSIDE; the egg is at -z)
local function box(model, info, name, size, x, y, z, color, material, yaw)
	local cf = info.CF * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
	return newPart(model, name, size, cf, color, material, false)
end

-- a cylinder whose long axis is the X axis of cf
local function round(model, name, length, diameter, cf, color, material)
	local part = newPart(model, name, Vector3.new(length, diameter, diameter), cf, color, material, false)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, diameter, diameter)
	return part
end

-- a thin beam or rope between two local points
local function strut(model, info, name, a, b, thickness, color, material)
	local p0 = at(info, a.X, a.Y, a.Z)
	local p1 = at(info, b.X, b.Y, b.Z)
	local length = (p1 - p0).Magnitude
	if length < 0.05 then
		return nil
	end
	return newPart(model, name, Vector3.new(thickness, thickness, length), CFrame.lookAt((p0 + p1) / 2, p1), color, material, false)
end

-- a lantern: glowing core with iron caps; light = range of a real light, or nil for glow only
local function lantern(model, info, name, x, y, z, light, scale)
	local s = scale or 1
	local core = box(model, info, name, Vector3.new(0.5, 0.7, 0.5) * s, x, y, z, AMBER, Material.Neon)
	box(model, info, name, Vector3.new(0.68, 0.12, 0.68) * s, x, y + 0.41 * s, z, IRON, Material.Metal)
	box(model, info, name, Vector3.new(0.68, 0.12, 0.68) * s, x, y - 0.41 * s, z, IRON, Material.Metal)
	if light then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 190, 110)
		l.Range = light
		l.Brightness = 1.4
		l.Shadows = false
		l.Parent = core
	end
	return core
end

local function bannerFace(part, face)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0.5
	sg.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "STONE\nHATCH"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(78, 54, 34)
	label.Parent = sg
end

-- once, when the ladder is put up: sleepers, stakes with guy ropes, sandbags
local function lookBase(model, info)
	box(model, info, "Sleeper", Vector3.new(5.2, 0.45, 0.9), 0, 0.225, 0.3, WOOD_DARK, Material.Wood)
	box(model, info, "Sleeper", Vector3.new(0.9, 0.45, 5.2), 0, 0.675, 0.3, WOOD_DARK, Material.Wood)
	box(model, info, "Lash", Vector3.new(1.4, 0.3, 1.4), 0, 5.0, 0, ROPE, Material.Fabric)
	for _, sx in { -3.2, 3.2 } do
		for _, sz in { -3.0, 3.6 } do
			box(model, info, "Stake", Vector3.new(0.28, 1.2, 0.28), sx, 0.45, sz, IRON, Material.Metal)
			strut(model, info, "GuyRope", Vector3.new(0, 5.0, 0), Vector3.new(sx, 1.0, sz), 0.1, ROPE, Material.Fabric)
		end
	end
	box(model, info, "Sandbag", Vector3.new(1.4, 0.6, 0.95), -1.9, 0.3, 2.5, SAND, Material.Fabric, 0.3)
	box(model, info, "Sandbag", Vector3.new(1.4, 0.6, 0.95), -0.6, 0.3, 2.7, SAND, Material.Fabric, -0.2)
	box(model, info, "Sandbag", Vector3.new(1.4, 0.6, 0.95), -1.3, 0.88, 2.55, SAND, Material.Fabric, 0.1)
	box(model, info, "Sandbag", Vector3.new(1.4, 0.6, 0.95), 1.9, 0.3, 2.4, SAND, Material.Fabric, -0.3)
end

-- after the ladder is made and after every new level: the post, banner and beacon (rebuilt each time)
local function lookTop(model, info)
	for _, child in model:GetChildren() do
		if string.sub(child.Name, 1, 4) == "Top_" then
			child:Destroy()
		end
	end
	local topY = LEVEL_HEIGHTS[info.Levels] + TRUSS_EXTRA
	info.Truss.Transparency = 1 -- you climb the invisible truss, you see the wooden post

	local postH = topY + 5
	box(model, info, "Top_Post", Vector3.new(1.2, postH, 1.2), 0, postH / 2, 0, WOOD, Material.Wood)
	local barY = topY + 4.6
	box(model, info, "Top_Bar", Vector3.new(4.2, 0.28, 0.28), 0, barY, 0, WOOD_DARK, Material.Wood)

	local banner = box(model, info, "Top_Banner", Vector3.new(2.6, 2.2, 0.1), -0.4, barY - 1.3, 0, CANVAS, Material.Fabric)
	bannerFace(banner, Enum.NormalId.Front)
	bannerFace(banner, Enum.NormalId.Back)
	box(model, info, "Top_Stripe", Vector3.new(2.62, 0.2, 0.12), -0.4, barY - 0.35, 0, AMBER, Material.Fabric)
	box(model, info, "Top_Stripe", Vector3.new(2.62, 0.2, 0.12), -0.4, barY - 2.25, 0, AMBER, Material.Fabric)

	strut(model, info, "Top_Cord", Vector3.new(1.6, barY - 0.1, 0), Vector3.new(1.6, barY - 0.6, 0), 0.08, ROPE, Material.Fabric)
	lantern(model, info, "Top_Beacon", 1.6, barY - 1.05, 0, 22, 1.4)

	local ball = box(model, info, "Top_Finial", Vector3.new(0.7, 0.7, 0.7), 0, postH + 0.3, 0, BRASS, Material.Metal)
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.7, 0.7, 0.7)
end

-- one level. rel = height of this deck above the ground, len = deck length
local function lookLevel(model, info, level, rel, len)
	local zEndFull = -(DECK_START + len)

	-- under the deck: side beams, cross beams, diagonal braces to the post
	for _, side in { -1, 1 } do
		box(model, info, "Beam", Vector3.new(0.5, 0.6, len), side * 2.6, rel - 0.9, -(DECK_START + len / 2), WOOD_DARK, Material.Wood)
		strut(
			model, info, "Brace",
			Vector3.new(side * 0.4, rel - 3.8, -0.3),
			Vector3.new(side * 2.6, rel - 1.0, -(DECK_START + 3.0)),
			0.3, WOOD_DARK, Material.Wood
		)
	end
	local crossCount = math.max(1, math.floor(len / 4))
	for i = 1, crossCount do
		local z = -(DECK_START + (i - 0.5) * len / crossCount)
		box(model, info, "Cross", Vector3.new(6.4, 0.45, 0.6), 0, rel - 0.95, z, WOOD_DARK, Material.Wood)
	end

	-- brass plates at the deck corners
	for _, side in { -1, 1 } do
		for _, z in { -(DECK_START + 0.4), -(DECK_START + len - 0.4) } do
			box(model, info, "Plate", Vector3.new(0.5, 0.08, 0.5), side * 2.6, rel + 0.04, z, BRASS, Material.Metal)
		end
	end

	-- padded canvas bumper against the egg
	box(model, info, "Bumper", Vector3.new(5.6, 1.1, 0.5), 0, rel + 0.45, zEndFull - 0.1, SAND, Material.Fabric)
	box(model, info, "BumperStrap", Vector3.new(0.3, 1.2, 0.56), -1.6, rel + 0.45, zEndFull - 0.1, IRON, Material.Metal)
	box(model, info, "BumperStrap", Vector3.new(0.3, 1.2, 0.56), 1.6, rel + 0.45, zEndFull - 0.1, IRON, Material.Metal)

	-- railings (the end next to the ladder stays open)
	local zStart = -(DECK_START + 1.2)
	local zEnd = -(DECK_START + len - 0.5)
	local posts = math.max(2, math.floor(math.abs(zEnd - zStart) / 4.5) + 2)
	for _, side in { -1, 1 } do
		local x = side * 2.8
		for i = 0, posts - 1 do
			local z = zStart + (zEnd - zStart) * (i / (posts - 1))
			box(model, info, "Post", Vector3.new(0.28, 3.0, 0.28), x, rel + 1.5, z, WOOD_DARK, Material.Wood)
		end
		strut(model, info, "Rail", Vector3.new(x, rel + 2.85, zStart), Vector3.new(x, rel + 2.85, zEnd), 0.22, WOOD, Material.Wood)
		strut(model, info, "Rope", Vector3.new(x, rel + 1.7, zStart), Vector3.new(x, rel + 1.7, zEnd), 0.1, ROPE, Material.Fabric)
	end

	-- a lantern on the first right-hand post (only the first level has a real light)
	lantern(model, info, "Lantern", 2.8, rel + 3.5, zStart, if level == 1 then 14 else nil, 1)

	-- a crate on odd levels, a banded barrel on even levels
	local px, pz = -1.8, -(DECK_START + 1.9)
	if level % 2 == 1 then
		box(model, info, "Crate", Vector3.new(1.6, 1.4, 1.6), px, rel + 0.7, pz, WOOD_LIGHT, Material.WoodPlanks, level * 0.7)
		box(model, info, "CrateBand", Vector3.new(1.66, 0.12, 1.66), px, rel + 0.35, pz, BRASS, Material.Metal, level * 0.7)
		box(model, info, "CrateBand", Vector3.new(1.66, 0.12, 1.66), px, rel + 1.05, pz, BRASS, Material.Metal, level * 0.7)
	else
		local base = info.CF * CFrame.new(px, rel + 0.75, pz) * CFrame.Angles(0, 0, math.pi / 2)
		round(model, "Barrel", 1.5, 1.3, base, WOOD, Material.Wood)
		round(model, "BarrelBand", 0.14, 1.38, base * CFrame.new(0.45, 0, 0), IRON, Material.Metal)
		round(model, "BarrelBand", 0.14, 1.38, base * CFrame.new(-0.45, 0, 0), IRON, Material.Metal)
	end

	-- rope lashings on the post below this deck
	box(model, info, "Lash", Vector3.new(1.4, 0.3, 1.4), 0, rel - 0.5, 0, ROPE, Material.Fabric)
	box(model, info, "Lash", Vector3.new(1.4, 0.3, 1.4), 0, rel - 3.4, 0, ROPE, Material.Fabric)

	-- wooden rungs for the part of the ladder that belongs to this level
	local from = if level == 1 then 0 else LEVEL_HEIGHTS[level - 1] + 1.2
	local to = rel + 1.2
	local i = 0
	while true do
		local y = 1.0 + i * 1.2
		if y > to then
			break
		end
		if y > from then
			round(model, "Rung", 2.9, 0.22, info.CF * CFrame.new(0, y, 0), WOOD_LIGHT, Material.Wood)
		end
		i += 1
	end
end
-- END LOOK

---------------------------------------------------------------------
-- Building (the parts you climb and walk on are made here)
---------------------------------------------------------------------
local function resizeTruss(info)
	local height = LEVEL_HEIGHTS[info.Levels] + TRUSS_EXTRA
	info.Truss.Size = Vector3.new(2, height, 2)
	info.Truss.CFrame = info.CF * CFrame.new(0, height / 2, 0)
end

local function addLevel(model, info, level)
	local rel = LEVEL_HEIGHTS[level]
	local len = deckLengthAt(info, rel)
	newPart(
		model,
		"Deck" .. level,
		Vector3.new(DECK_WIDTH, DECK_THICK, len),
		info.CF * CFrame.new(0, rel - DECK_THICK / 2, -(DECK_START + len / 2)),
		Color3.fromRGB(112, 78, 46),
		Enum.Material.WoodPlanks,
		true
	)
	lookLevel(model, info, level, rel, len)
end

local function buildRig(player, base, toEgg, mastDist, shell)
	local model = Instance.new("Model")
	model.Name = "ClimbRig"
	local info = {
		Owner = player.UserId,
		Base = base,
		ToEgg = toEgg,
		MastDist = mastDist,
		Shell = shell,
		CF = CFrame.lookAt(base, base + toEgg),
		Levels = 1,
	}

	local truss = Instance.new("TrussPart")
	truss.Name = "Mast"
	truss.Anchored = true
	truss.Material = Enum.Material.Wood
	truss.Color = Color3.fromRGB(78, 54, 34)
	truss.Parent = model
	info.Truss = truss
	model.PrimaryPart = truss
	resizeTruss(info)

	addLevel(model, info, 1)
	lookBase(model, info)
	lookTop(model, info)

	-- "Pick up" prompt on the outer side of the ladder
	local spot = Instance.new("Part")
	spot.Name = "PickupSpot"
	spot.Size = Vector3.new(1.5, 2, 1.5)
	spot.CFrame = info.CF * CFrame.new(0, 1.2, 1.9)
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.Transparency = 1
	spot.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Ladder"
	prompt.ActionText = "Pick up"
	prompt.HoldDuration = 0.7
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot
	prompt.Triggered:Connect(function(who)
		local owner = Players:GetPlayerByUserId(info.Owner)
		if owner and owner ~= who then
			notify(who, "Only " .. owner.DisplayName .. " can pick this ladder up.")
			return
		end
		model:Destroy()
	end)

	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Levels", 1)
	rigs[model] = info
	model.Parent = rigsFolder
	return model
end

---------------------------------------------------------------------
-- Requests from the client
---------------------------------------------------------------------
local function onPlace(player, position)
	-- 1. rate limit, 2. type and range
	if not allow(player, "PlaceRig", 2, 3) then
		return
	end
	if typeof(position) ~= "Vector3" or position ~= position or position.Magnitude > 100000 then
		return
	end
	-- 3. permission
	local root = aliveRoot(player)
	if not root or not holdsRigTool(player) then
		return
	end
	if Workspace:GetAttribute("RoundState") == "Ended" then
		return
	end
	-- 4. the rig must be bought
	if (player:GetAttribute("ClimbTier") or 0) < 1 then
		notify(player, "Buy the Ladder at the Tool Shop first.")
		return
	end
	-- 4. plausibility
	local shell = findEgg()
	if not shell then
		notify(player, "There is no egg to climb right now.")
		return
	end
	local centre = shell.Position
	local flat = Vector3.new(position.X - centre.X, 0, position.Z - centre.Z)
	local dist = flat.Magnitude
	if dist < 1 then
		return
	end
	local snapped = math.clamp(dist, MAST_MIN, MAST_MAX)
	local dirOut = flat / dist
	local mastX = centre.X + dirOut.X * snapped
	local mastZ = centre.Z + dirOut.Z * snapped
	local eggBottomY = centre.Y - shell.Size.Y / 2
	local ground = groundAt(mastX, mastZ, eggBottomY)
	if not ground then
		notify(player, "You can't put a ladder on that spot.")
		return
	end
	if flatDistance(root.Position, ground) > PLACE_REACH then
		notify(player, "Too far away. Walk closer.")
		return
	end
	local mine = 0
	for _, child in rigsFolder:GetChildren() do
		local info = rigs[child]
		if info then
			if flatDistance(info.Base, ground) < MIN_SPACING then
				notify(player, "Too close to another ladder.")
				return
			end
			if info.Owner == player.UserId then
				mine += 1
			end
		end
	end
	if mine >= MAX_RIGS_PER_PLAYER then
		notify(player, string.format("You already have %d ladders out. Pick one up first.", MAX_RIGS_PER_PLAYER))
		return
	end

	buildRig(player, ground, -dirOut, snapped, shell)
	notify(player, "Ladder up! Click it again to add a level.", "Info")
end

-- BEGIN BUILD ANIM
-- The new level is built piece by piece, bottom to top. Decoration only:
-- solid parts only fade in and never move, so nobody can be pushed.
local buildSnapshot = nil

local function buildSnap(rig)
	buildSnapshot = {}
	for _, d in rig:GetDescendants() do
		buildSnapshot[d] = true
	end
end

local function buildEmitter(kind)
	local e = Instance.new("ParticleEmitter")
	if kind == "dust" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(196, 176, 140))
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 4),
		})
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(3, 7)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 2
		e.Acceleration = Vector3.new(0, 1, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.LightEmission = 0
		e.Rate = 50
	else
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 205, 100), Color3.fromRGB(255, 140, 40))
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(10, 18)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = Vector3.new(0, -30, 0)
		e.LightEmission = 1
		e.Rate = 40
	end
	e.Enabled = true
	return e
end

local function buildAnim(rig, info, level)
	local snap = buildSnapshot
	buildSnapshot = nil
	if not snap then
		return
	end
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local records = {}

	local function restore()
		for _, r in records do
			if r.part.Parent then
				r.part.Transparency = r.tr
				r.part.CFrame = r.cf
			end
		end
	end

	local function later(t, fn)
		task.delay(t, function()
			pcall(fn)
		end)
	end

	local ok, err = pcall(function()
		local rel = LEVEL_HEIGHTS[level]
		local gap = rel - (LEVEL_HEIGHTS[level - 1] or 0)
		local minY, maxY = math.huge, -math.huge

		for _, d in rig:GetDescendants() do
			if
				not snap[d]
				and d:IsA("BasePart")
				and d.Anchored
				and d.Transparency < 0.99
				and d.Name ~= "Top_Post"
				and d.Name ~= "RiseFx"
			then
				local isTop = string.sub(d.Name, 1, 4) == "Top_"
				local y = d.Position.Y
				table.insert(records, {
					part = d, cf = d.CFrame, tr = d.Transparency,
					top = isTop, solid = d.CanCollide, y = y,
				})
				if not isTop then
					minY = math.min(minY, y)
					maxY = math.max(maxY, y)
				end
			end
		end
		local span = math.max(maxY - minY, 1)

		-- hide and move everything in this same frame so nothing flashes
		for _, r in records do
			if r.top then
				r.part.CFrame = r.cf + Vector3.new(0, -gap, 0)
			else
				r.part.Transparency = 1
				if not r.solid then
					r.part.CFrame = r.cf + Vector3.new(0, -3, 0)
				end
			end
		end

		-- build bottom to top
		for _, r in records do
			local delay = if r.top then 0.3 else ((r.y - minY) / span) * 0.9
			later(delay, function()
				if not r.part.Parent then
					return
				end
				if r.top then
					TweenService:Create(
						r.part,
						TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ CFrame = r.cf }
					):Play()
				else
					local goal = { Transparency = r.tr }
					if not r.solid then
						goal.CFrame = r.cf
					end
					TweenService:Create(
						r.part,
						TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						goal
					):Play()
				end
			end)
		end

		-- dust and sparks while it builds
		local len = deckLengthAt(info, rel)
		local function puff(kind, x, y, z, seconds)
			local p = Instance.new("Part")
			p.Name = "RiseFx"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			p.Size = Vector3.new(0.2, 0.2, 0.2)
			p.CFrame = info.CF * CFrame.new(x, y, z)
			local e = buildEmitter(kind)
			e.Parent = p
			p.Parent = rig
			Debris:AddItem(p, seconds + 2.5)
			task.delay(seconds, function()
				e.Enabled = false
			end)
		end
		later(0.25, function() puff("dust", 0, rel + 0.2, -(DECK_START + 0.5), 0.35) end)
		later(0.55, function() puff("dust", 0, rel + 0.2, -(DECK_START + len / 2), 0.35) end)
		later(0.85, function() puff("dust", 0, rel + 0.2, -(DECK_START + len - 0.5), 0.35) end)
		later(0.95, function() puff("sparks", 0, rel + 0.6, -(DECK_START + len - 0.3), 0.25) end)
		later(0.95, function() puff("sparks", 0, rel + 0.6, 0, 0.25) end)
	end)

	if not ok then
		warn("[ClimbService] buildAnim: " .. tostring(err))
		restore()
	end
	task.delay(3, restore) -- safety net: everything ends up exactly as built
end
-- END BUILD ANIM

local function onExtend(player, rig)
	if not allow(player, "ExtendRig", 3, 4) then
		return
	end
	if typeof(rig) ~= "Instance" or not rig:IsA("Model") or rig.Parent ~= rigsFolder then
		return
	end
	local info = rigs[rig]
	if not info then
		return
	end
	local root = aliveRoot(player)
	if not root or not holdsRigTool(player) then
		return
	end
	if Workspace:GetAttribute("RoundState") == "Ended" then
		return
	end
	if flatDistance(root.Position, info.Base) > EXTEND_REACH then
		notify(player, "Step closer to add a level.")
		return
	end
	if info.Levels < MAX_LEVELS and info.Levels >= (player:GetAttribute("ClimbTier") or 0) then
		notify(player, "Buy the next ladder level at the Tool Shop.")
		return
	end
	if info.Levels >= MAX_LEVELS then
		notify(player, "This ladder is fully built.", "Info")
		return
	end
	local shell = findEgg()
	if not shell then
		return
	end
	info.Shell = shell
	buildSnap(rig)
	info.Levels += 1
	addLevel(rig, info, info.Levels)
	resizeTruss(info)
	lookTop(rig, info)
	buildAnim(rig, info, info.Levels)
	rig:SetAttribute("Levels", info.Levels)
end

-- BEGIN PLACE ANIM
-- A new ladder builds up piece by piece, like an extend does. onPlace stays exactly as it was;
-- this wrapper spots the rig it just created and runs the same build-up with an empty snapshot.
-- Wrapped in pcall: if the animation ever fails, the ladder is still placed.
placeRemote.OnServerEvent:Connect(function(player, position)
	local before = {}
	for model in rigs do
		before[model] = true
	end
	onPlace(player, position)
	for model, info in rigs do
		if not before[model] and model.Parent == rigsFolder then
			buildSnapshot = {}
			local ok, err = pcall(buildAnim, model, info, 1)
			if not ok then
				buildSnapshot = nil
				warn("[ClimbService] place anim: " .. tostring(err))
			end
		end
	end
end)
-- END PLACE ANIM
extendRemote.OnServerEvent:Connect(onExtend)

---------------------------------------------------------------------
-- The tool: free for everybody, always in the bar
---------------------------------------------------------------------
local function buildTool()
	local tool = Instance.new("Tool")
	tool.Name = "Ladder"
	tool.CanBeDropped = false
	tool.ToolTip = "Click the ground near the egg to put up a ladder. Click a ladder to add a level."
	tool:SetAttribute("GearId", GEAR_ID) -- set BEFORE parenting so the client sees it immediately
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.55, 0.55, 2.4)
	handle.Color = Color3.fromRGB(112, 78, 46)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

local function hasRigTool(container)
	if not container then
		return false
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GearId") == GEAR_ID then
			return true
		end
	end
	return false
end

local function giveTool(player)
	if (player:GetAttribute("ClimbTier") or 0) < 1 then
		return -- not bought yet
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or hasRigTool(backpack) or hasRigTool(player.Character) then
		return
	end
	buildTool().Parent = backpack
end

local function setupPlayer(player)
	player:GetAttributeChangedSignal("ClimbTier"):Connect(function()
		giveTool(player) -- hand over the rig the moment it is bought
	end)
	player.CharacterAdded:Connect(function()
		task.spawn(function()
			player:WaitForChild("Backpack")
			task.wait(0.3)
			giveTool(player)
		end)
	end)
	if player.Character then
		task.spawn(function()
			player:WaitForChild("Backpack")
			giveTool(player)
		end)
	end
end
Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

-- ladders are cleared when the round ends
Workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
	if Workspace:GetAttribute("RoundState") == "Ended" then
		for _, child in rigsFolder:GetChildren() do
			child:Destroy()
		end
	end
end)

print("[ClimbService] Init OK")
