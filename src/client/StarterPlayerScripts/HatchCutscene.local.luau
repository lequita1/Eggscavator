-- HatchCutscene v3 (client): real egg, any hatchling model, about 31 seconds on Workspace.HatchStage.
-- The hatchling is CLONED and animated locally, so stage physics, streaming and anchoring can't hide it.
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FX = require(Shared:WaitForChild("GameConfig")).FX
local Util = require(Shared:WaitForChild("Util"))
local CollectionService = game:GetService("CollectionService")
local DinoAnimator = require(Shared:WaitForChild("DinoAnimator"))
local HatchlingProp = require(Shared:WaitForChild("HatchlingProp"))

local CuratorName = "Prof. Yanah"
pcall(function()
	CuratorName = require(Shared:WaitForChild("Curator", 5)).Name
end)

local CFG = {
	BarHeight = 0.11,
	Total = 31.0, -- keep RoundService CUTSCENE_TIME at least 1.5 higher
	HatchlingHeight = 0.36, -- hatchling height as a fraction of the egg's height
	FaceFix = 0, -- set to math.pi if the dinosaur faces AWAY from the camera
	StartFraction = 0.7, -- size inside the egg, as a fraction of its final size
	Night = false, -- dark sky during the scene (this player's screen only)
	-- Beats (seconds into the scene)
	CrackStart = 6.0,
	SilenceAt = 18.2, -- heartbeat stops, everything holds still
	ThumpAt = 18.95, -- one huge last beat
	BurstAt = 19.2,
	PopAt = 22.0, -- the membrane tears, the hatchling climbs out
	RiseTime = 1.6,
	ChirpAt = 25.6,
	HopAt = { 26.0, 26.9 },
	HopTime = 0.55,
	HopHeight = 0.1, -- fraction of the egg's height
	CloseUpAt = 27.0,
	CloseUpTime = 2.6,
	CardAt = 27.8,
	CardOutAt = 30.0,
	BlackAt = 30.5,
}

-- {time, strength, heroCrackNumber}. Knocks from inside the egg: they rock it and grow cracks.
local KNOCKS = {
	{ 6.0, 0.9, 1 }, { 7.9, 0.6 }, { 9.3, 0.7 }, { 10.4, 1.0, 2 }, { 11.4, 0.6 }, { 12.2, 0.8 },
	{ 13.0, 1.2, 3 }, { 13.7, 0.9 }, { 14.3, 1.0 }, { 14.8, 1.1 }, { 15.25, 1.2 }, { 15.65, 1.3 },
	{ 16.0, 1.3 }, { 16.35, 1.4 }, { 16.65, 1.4 }, { 16.95, 1.5 }, { 17.2, 1.5 }, { 17.45, 1.6 },
	{ 17.65, 1.6 }, { 17.85, 1.7 }, { 18.0, 1.8 },
}
local HERO_DIRS = { Vector3.new(0.12, 0.15, 1), Vector3.new(-0.3, 0.4, 1), Vector3.new(0.35, -0.1, 1) }

local SUBS = {
	{ 1.0, 4.4, "Quiet now... can you hear that?" },
	{ 6.6, 9.6, "Something is knocking. From the inside." },
	{ 10.8, 14.0, "That is no fossil. That is a heartbeat!" },
	{ 14.4, 17.9, "The stone is giving way! Stand back!" },
	{ 23.0, 25.3, "By all the stars... it's alive." },
	{ 26.0, 27.6, "Welcome to the world, little one." },
}

local LOW_QUALITY = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local Q = if LOW_QUALITY then 0.5 else 1 -- phones get half the particles and shards
local RARITY_COLORS = {
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 200, 50),
}

local DUST = Color3.fromRGB(225, 205, 170)
local COLD = Color3.fromRGB(70, 35, 15)
local WARM = Color3.fromRGB(235, 120, 35)
local HOT = Color3.fromRGB(255, 235, 170)
local COOL_TINT = Color3.fromRGB(205, 222, 255)
local WARM_TINT = Color3.fromRGB(255, 236, 215)

-- Audio director: plays from ReplicatedStorage.GameSounds. An empty Cut_ slot falls back to a similar sound.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local gameSounds = ReplicatedStorage:FindFirstChild("GameSounds")
local FALLBACK = { -- { existing sound, volume multiplier, speed multiplier }
	Cut_Crack = { "PlatePop", 1, 1 },
	Cut_Thump = { "Heartbeat", 1, 0.55 },
	Cut_Burst = { "Break", 1, 0.9 },
	Cut_Whoosh = { "PlatePop", 0.8, 0.6 },
	Cut_Pop = { "Break", 0.6, 1.3 },
	Cut_Land = { "PlatePop", 1, 0.7 },
	Cut_Chirp = { "HatchChirp", 1, 1 },
	Cut_Hop = { "PlatePop", 0.5, 1.5 },
}
local SOUND_NAMES = {
	"Cut_Ambience", "Cut_Rumble", "Cut_Swell", "Cut_Crack", "Cut_Thump", "Cut_Burst", "Cut_Whoosh",
	"Cut_Pop", "Cut_Land", "Cut_Chirp", "Cut_Hop", "Cut_Sting", "Cut_Music", "Heartbeat", "PlatePop", "Break",
}

local function usable(name: string): Sound?
	gameSounds = gameSounds or ReplicatedStorage:FindFirstChild("GameSounds")
	local s = gameSounds and gameSounds:FindFirstChild(name)
	if s and s:IsA("Sound") and s.SoundId ~= "" then
		return s
	end
	return nil
end

local function resolve(name: string): (Sound?, number, number)
	local s = usable(name)
	if s then
		return s, 1, 1
	end
	local fb = FALLBACK[name]
	if fb then
		local f = usable(fb[1])
		if f then
			return f, fb[2], fb[3]
		end
	end
	return nil, 1, 1
end

local Audio = {}
local activeSounds = {}

local function spawnSound(name: string, volume: number?, speed: number?, looped: boolean)
	local template, volMul, speedMul = resolve(name)
	if not template then
		return nil
	end
	local sound = template:Clone()
	sound.Looped = looped
	local base = template.Volume * volMul
	sound.Volume = base * (volume or 1)
	sound.PlaybackSpeed = template.PlaybackSpeed * (speed or 1) * speedMul
	sound.Parent = SoundService

	local handle = { Sound = sound }
	activeSounds[handle] = true
	local function cleanup()
		activeSounds[handle] = nil
		if sound.Parent then
			sound:Destroy()
		end
	end
	if not looped then
		local connection
		connection = sound.Ended:Connect(function()
			connection:Disconnect()
			cleanup()
		end)
		task.delay(40, cleanup)
	end
	function handle.Set(v: number) -- instant volume (1 = the sound's own volume)
		if sound.Parent then
			sound.Volume = base * v
		end
	end
	function handle.Fade(v: number, seconds: number)
		if sound.Parent then
			TweenService:Create(sound, TweenInfo.new(seconds), { Volume = base * v }):Play()
		end
	end
	function handle.Stop(seconds: number?)
		if not sound.Parent then
			return
		end
		local s = seconds or 0.3
		TweenService:Create(sound, TweenInfo.new(s), { Volume = 0 }):Play()
		task.delay(s + 0.05, cleanup)
	end
	sound:Play()
	return handle
end

function Audio.Play(name: string, volume: number?, speed: number?)
	return spawnSound(name, volume, speed, false)
end
function Audio.Loop(name: string, volume: number?)
	return spawnSound(name, volume, 1, true)
end
function Audio.StopAll(seconds: number)
	for handle in table.clone(activeSounds) do
		handle.Stop(seconds)
	end
end

local function playSound(name: string, volume: number?, speed: number?)
	Audio.Play(name, volume, speed)
end

-- Preload, and tell you once which sounds are still silent
task.spawn(function()
	local toLoad, missing = {}, {}
	for _, name in SOUND_NAMES do
		local s = usable(name)
		if s then
			table.insert(toLoad, s)
		elseif not (FALLBACK[name] and usable(FALLBACK[name][1])) then
			table.insert(missing, name)
		end
	end
	if #toLoad > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(toLoad)
		end)
	end
	if #missing > 0 then
		print("[HatchCutscene] Sounds not set yet (silent): " .. table.concat(missing, ", "))
	end
end)

local rng = Random.new()
local function rand(a: number, b: number): number
	return rng:NextNumber(a, b)
end
local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end
local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function noise2(x: number, y: number): number
	return math.noise(x, y, 0.5) * 2
end

local function extents(part: BasePart): Vector3
	local cf, s = part.CFrame, part.Size
	return Vector3.new(
		math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
		math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
		math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
	)
end

local function collectParts(inst: Instance)
	local list = {}
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function crackColor(level: number): Color3
	if level < 0.6 then
		return COLD:Lerp(WARM, level / 0.6)
	end
	return WARM:Lerp(HOT, (level - 0.6) / 0.4)
end

---------------------------------------------------------------------
-- Hatchling: clone, make safe, measure, and a rig-less deformer
---------------------------------------------------------------------
local function prepareClone(src: Instance, parent: Instance): Model?
	local clone = src:Clone()
	if not clone then
		return nil
	end
	if clone:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		clone.Parent = wrapper
		clone = wrapper
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Humanoid") then
			d:Destroy()
		end
	end
	clone.Parent = parent
	return clone
end

local function buildPlaceholder(parent: Instance, at: Vector3): Model
	local model = Instance.new("Model")
	local function blob(size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Position = at + offset
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = model
	end
	blob(Vector3.new(4.2, 3.6, 6), Vector3.new(0, 3.1, 0), Color3.fromRGB(150, 190, 105))
	blob(Vector3.new(3.2, 3, 3.4), Vector3.new(0, 3.7, -3.6), Color3.fromRGB(150, 190, 105))
	blob(Vector3.new(4.6, 4.6, 0.6), Vector3.new(0, 4.6, -2.4), Color3.fromRGB(240, 140, 50))
	model.Parent = parent
	return model
end

-- Remembers every part's position relative to the feet, so the whole model can be posed and squashed.
local function buildRig(model: Model)
	local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, d in collectParts(model) do
		if d.Transparency < 1 then
			local e = extents(d)
			minX = math.min(minX, d.Position.X - e.X / 2)
			maxX = math.max(maxX, d.Position.X + e.X / 2)
			minY = math.min(minY, d.Position.Y - e.Y / 2)
			maxY = math.max(maxY, d.Position.Y + e.Y / 2)
			minZ = math.min(minZ, d.Position.Z - e.Z / 2)
			maxZ = math.max(maxZ, d.Position.Z + e.Z / 2)
		end
	end
	if minY == math.huge then
		return nil, 0
	end
	local base = CFrame.new((minX + maxX) / 2, minY, (minZ + maxZ) / 2)
	local rig = {}
	for _, d in collectParts(model) do
		table.insert(rig, { Part = d, Rel = base:ToObjectSpace(d.CFrame), Size = d.Size })
	end
	return rig, maxY - minY
end

---------------------------------------------------------------------
-- Cracks on the real shell
---------------------------------------------------------------------
local function planCrack(plan, shell, half, startPoint, startNormal, length, width, depth, t0, step, hero)
	local dir = startNormal:Cross(Vector3.new(rand(-1, 1), rand(-1, 1), rand(-1, 1)))
	if dir.Magnitude < 0.1 then
		dir = startNormal:Cross(Vector3.xAxis)
	end
	dir = dir.Unit

	local steps = rng:NextInteger(5, 8)
	local stepLength = length / steps
	local current = startPoint
	for i = 1, steps do
		dir = (dir + startNormal:Cross(dir) * rand(-0.7, 0.7)).Unit
		local nextPoint, nextNormal = Util.EllipsoidSurface(shell.CFrame, half, current + dir * stepLength)
		table.insert(plan, {
			A = current,
			B = nextPoint,
			N = nextNormal,
			Width = width * (1 - (i / steps) * 0.6),
			Reveal = t0 + (i - 1) * step,
			Hero = hero,
		})
		local along = nextPoint - current
		if along.Magnitude > 0.01 then
			dir = (along - nextNormal * along:Dot(nextNormal)).Unit
		end
		if depth > 0 and i >= 2 and rng:NextNumber() < 0.35 then
			planCrack(plan, shell, half, nextPoint, nextNormal, length * 0.5, width * 0.7, depth - 1, t0 + i * step, step, hero)
		end
		current = nextPoint
		startNormal = nextNormal
	end
end

local function neonPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	return part
end

local function makeSegment(seg, S: number)
	local distance = (seg.B - seg.A).Magnitude
	if distance < 0.05 then
		return nil, nil
	end
	local mid = (seg.A + seg.B) / 2
	local main = neonPart()
	main.Size = Vector3.new(seg.Width, 0.14 * S, distance + 0.08 * S)
	main.CFrame = CFrame.lookAt(mid + seg.N * 0.06 * S, seg.B + seg.N * 0.06 * S, seg.N)
	local halo = nil
	if seg.Hero then
		halo = neonPart()
		halo.Transparency = 0.8
		halo.Size = Vector3.new(seg.Width * 3.4, 0.1 * S, distance + 0.6 * S)
		halo.CFrame = CFrame.lookAt(mid + seg.N * 0.04 * S, seg.B + seg.N * 0.04 * S, seg.N)
	end
	return main, halo
end

---------------------------------------------------------------------
-- Lighting mood, only on this player's screen
---------------------------------------------------------------------
local function startMood()
	local saved = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation,
		ClockTime = Lighting.ClockTime,
	}
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 0.9
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast = 0.15
	grade.Saturation = 0.05
	grade.TintColor = COOL_TINT
	grade.Parent = Lighting
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.5
	dof.NearIntensity = 0
	dof.FocusDistance = 40
	dof.InFocusRadius = 25
	dof.Parent = Lighting

	local goal = {
		Brightness = 0.4,
		Ambient = Color3.fromRGB(26, 28, 44),
		OutdoorAmbient = Color3.fromRGB(26, 28, 44),
		ExposureCompensation = -0.35,
	}
	if CFG.Night then
		goal.ClockTime = 0
	end
	TweenService:Create(Lighting, TweenInfo.new(2), goal):Play()

	return {
		Bloom = bloom,
		Grade = grade,
		DOF = dof,
		Restore = function()
			bloom:Destroy()
			grade:Destroy()
			dof:Destroy()
			TweenService:Create(Lighting, TweenInfo.new(0.5), saved):Play()
		end,
	}
end

---------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------
local function buildGui(species: string, rarity: string)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	local function makeFrame(zIndex: number, color: Color3, transparency: number): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency
		frame.BorderSizePixel = 0
		frame.ZIndex = zIndex
		frame.Parent = gui
		return frame
	end

	-- Vignette: four dark gradients on the screen edges
	local function vignette(anchor: Vector2, position: UDim2, size: UDim2, rotation: number)
		local frame = makeFrame(1, Color3.new(0, 0, 0), 0)
		frame.AnchorPoint = anchor
		frame.Position = position
		frame.Size = size
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		gradient.Parent = frame
	end
	vignette(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.2, 1), 0)
	vignette(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.2, 1), 180)
	vignette(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.25), 90)
	vignette(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.25), 270)

	local top = makeFrame(5, Color3.new(0, 0, 0), 0)
	top.AnchorPoint = Vector2.new(0, 0)
	top.Position = UDim2.fromScale(0, 0)
	top.Size = UDim2.fromScale(1, 0)

	local bottom = makeFrame(5, Color3.new(0, 0, 0), 0)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.fromScale(1, 0)

	local flash = makeFrame(2, Color3.fromRGB(255, 245, 215), 1)
	flash.Size = UDim2.fromScale(1, 1)

	local black = makeFrame(20, Color3.new(0, 0, 0), 1)
	black.Size = UDim2.fromScale(1, 1)

	local function makeLabel(text: string, y: number, height: number, maxSize: number, font: Enum.Font, color: Color3)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.fromScale(0.8, height)
		label.BackgroundTransparency = 1
		label.Font = font
		label.Text = text
		label.TextColor3 = color
		label.TextScaled = true
		label.TextTransparency = 1
		label.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
		label.TextStrokeTransparency = 1
		label.ZIndex = 3
		label.Parent = gui
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = maxSize
		limit.Parent = label
		return label
	end
	local labels = {
		makeLabel("YOU DISCOVERED", 0.70, 0.04, 24, Enum.Font.GothamMedium, Color3.fromRGB(255, 240, 200)),
		makeLabel(species, 0.765, 0.09, 56, Enum.Font.GothamBlack, Color3.new(1, 1, 1)),
		makeLabel(string.upper(rarity), 0.855, 0.04, 26, Enum.Font.GothamBold, RARITY_COLORS[rarity] or RARITY_COLORS.Common),
	}
	local pop = Instance.new("UIScale")
	pop.Parent = labels[2]

	local line = makeFrame(3, RARITY_COLORS[rarity] or RARITY_COLORS.Common, 0)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.822)
	line.Size = UDim2.fromScale(0, 0.004)

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.83)
	subtitle.Size = UDim2.fromScale(0.7, 0.05)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.RichText = true
	subtitle.Text = ""
	subtitle.TextColor3 = Color3.fromRGB(255, 248, 235)
	subtitle.TextScaled = true
	subtitle.TextTransparency = 1
	subtitle.TextStrokeColor3 = Color3.fromRGB(10, 6, 2)
	subtitle.TextStrokeTransparency = 1
	subtitle.ZIndex = 4
	subtitle.Parent = gui
	local subLimit = Instance.new("UITextSizeConstraint")
	subLimit.MaxTextSize = 26
	subLimit.Parent = subtitle

	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.fromScale(0.985, 0.985)
	skip.Size = UDim2.fromOffset(96, 34)
	skip.BackgroundTransparency = 1
	skip.Font = Enum.Font.GothamBold
	skip.Text = "Skip >"
	skip.TextColor3 = Color3.fromRGB(220, 220, 220)
	skip.TextSize = 18
	skip.ZIndex = 10
	skip.Parent = gui

	return {
		Gui = gui, Black = black, Top = top, Bottom = bottom, Flash = flash,
		Labels = labels, Pop = pop, Line = line, Subtitle = subtitle, Skip = skip,
	}
end

local function tweenBars(top: Frame, bottom: Frame, height: number, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, info, { Size = UDim2.fromScale(1, height) }):Play()
	TweenService:Create(bottom, info, { Size = UDim2.fromScale(1, height) }):Play()
end

local function showLabel(label: TextLabel, duration: number)
	TweenService:Create(label, TweenInfo.new(duration), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
end
local function hideLabel(label: TextLabel, duration: number)
	TweenService:Create(label, TweenInfo.new(duration), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

---------------------------------------------------------------------
-- The scene
---------------------------------------------------------------------
local running = false

local function run()
	if running then
		return
	end
	running = true

	local stagePos = Workspace:GetAttribute("HatchStagePosition")
	local species = Workspace:GetAttribute("HatchSpecies") or "Hatchling"
	local rarity = Workspace:GetAttribute("HatchRarity") or "Common"
	local eventStart = os.clock()

	local ui = buildGui(species, rarity)
	ui.Gui.Parent = playerGui
	local black = ui.Black

	-- Cover the screen while the server moves us, and hide the rest of the UI
	TweenService:Create(black, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	tweenBars(ui.Top, ui.Bottom, CFG.BarHeight, 0.5)
	local hiddenGuis = {}
	for _, other in playerGui:GetChildren() do
		if other:IsA("ScreenGui") and other ~= ui.Gui and other.Enabled then
			other.Enabled = false
			table.insert(hiddenGuis, other)
		end
	end

	local sceneStarted = false
	local skipped = false
	local function skip()
		if skipped or not sceneStarted then
			return
		end
		skipped = true
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("HatchSkip")
		if remote then
			remote:FireServer()
		end
	end
	ui.Skip.Activated:Connect(skip)
	local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space then
			skip()
		end
	end)

	local camera = Workspace.CurrentCamera
	local savedFov = camera.FieldOfView
	local shell, shellBase, shellSize, shellTransparency = nil, nil, nil, nil
	local hiddenSource = {}
	local fxFolder, mood = nil, nil
	local blackDone = false

	local ok, err = pcall(function()
		-- Load the stage (it is far away, so ask the engine to stream it in)
		if typeof(stagePos) == "Vector3" then
			pcall(function()
				player:RequestStreamAroundAsync(stagePos, 4)
			end)
		end
		local stage = Workspace:WaitForChild("HatchStage", 8)
		local center = stage:WaitForChild("EggCenter", 8)
		local eggProp = stage:WaitForChild("EggProp", 8)
		shell = eggProp:WaitForChild("Shell", 8)

		-- Wait until the server has had time to move us
		while os.clock() - eventStart < 0.8 do
			RunService.Heartbeat:Wait()
		end

		fxFolder = Instance.new("Folder")
		fxFolder.Name = "HatchCutsceneFX"
		fxFolder.Parent = Workspace

		-- Sizes, all measured from the real egg
		local ext = extents(shell)
		shellBase, shellSize, shellTransparency = shell.CFrame, shell.Size, shell.Transparency
		local H = ext.Y
		local S = H / 28 -- 1 for a 28-stud egg; scales shake, dust, speeds
		local halfZ = ext.Z / 2
		local egg = shell.Position
		local groundY = center:GetAttribute("GroundY") or (egg.Y - H / 2)
		local half = shell.Size / 2 * FX.SurfaceScale
		local front = Vector3.new(0, 0, 1)
		local up = Vector3.yAxis
		local hatchH = CFG.HatchlingHeight * H
		local gStart = Vector3.new(egg.X, groundY, egg.Z)
		local gPoint = gStart
		local landing = Vector3.new(egg.X, groundY, egg.Z + halfZ * 0.9)
		local landTime = CFG.PopAt + CFG.RiseTime

		---------------------------------------------------------
		---------------------------------------------------------
		-- The hatchling: the rigged dinosaur (bones), or the old model if there is no DinoRig
		---------------------------------------------------------
		local source = stage:FindFirstChild("Hatchling", true)
		local poseHatchling
		local rigged = false

		if ReplicatedStorage:FindFirstChild("DinoRig") then
			local okMake, model = pcall(HatchlingProp.Make, hatchH, "CutsceneHatchling")
			if okMake and model then
				CollectionService:RemoveTag(model, "DinoAnim") -- this scene drives it, not DinoLife
				model:SetAttribute("Manual", true)
				model.Parent = fxFolder
				local okAnim, animator = pcall(DinoAnimator.new, model, "Hatchling")
				if okAnim then
					rigged = true
					local baseScale = model:GetScale()
					-- Work out which way the head really points, so the scene can turn it toward the camera
					local autoFace = 0
					do
						local meshPart = model:FindFirstChildWhichIsA("MeshPart")
						local headBone, baseBone
						if meshPart then
							for _, b in meshPart:GetDescendants() do
								if b:IsA("Bone") then
									local n = tonumber(string.match(b.Name, "(%d+)$"))
									if n == 24 then
										headBone = b
									elseif n == 3 then
										baseBone = b
									end
								end
							end
						end
						local rigPart = model.PrimaryPart
						if headBone and rigPart and meshPart then
							local from = if baseBone then baseBone.WorldPosition else meshPart.Position
							local v = rigPart.CFrame:VectorToObjectSpace(headBone.WorldPosition - from)
							if Vector3.new(v.X, 0, v.Z).Magnitude > 0.01 then
								autoFace = -math.atan2(v.X, v.Z)
							end
							print(string.format("[HatchCutscene] head direction in rig space: (%.2f, %.2f, %.2f), auto turn: %.2f rad", v.X, v.Y, v.Z, autoFace))
						else
							warn("[HatchCutscene] Could not find the head bone, so there is no auto-facing")
						end
					end
					local lastFraction = -1
					local lastClock = os.clock()
					-- squash > 1 means stretched (in the air, chirping), < 1 means crouched (landing, wind-up)
					poseHatchling = function(feet: Vector3, yaw: number, pitch: number, roll: number, fraction: number, squash: number)
						local now = os.clock()
						local dt = math.min(now - lastClock, 0.05)
						lastClock = now
						if math.abs(fraction - lastFraction) > 0.002 then
							lastFraction = fraction
							model:ScaleTo(baseScale * fraction)
						end
						model:PivotTo(
							CFrame.new(feet)
								* CFrame.Angles(0, yaw + CFG.FaceFix + autoFace, 0)
								* CFrame.Angles(-pitch, 0, roll) -- positive pitch = nose up
						)
						local kicking = squash > 1.06 or math.abs(roll) > 0.06
						animator:Step(dt, {
							Speed = if kicking then animator.Length * 0.6 else 0,
							Tuck = math.clamp((1 - squash) * 3.5, 0, 1),
							Roar = math.clamp((squash - 1) * 3, 0, 1),
							Excite = 1,
							LookYaw = math.clamp(-yaw * 0.8, -1, 1), -- the head stays on the camera while the body sways
						})
					end
				else
					warn("[HatchCutscene] DinoAnimator failed: " .. tostring(animator))
					model:Destroy()
				end
			else
				warn("[HatchCutscene] Could not build the rigged hatchling: " .. tostring(model))
			end
		end

		if not rigged then
			-- Fallback: the old rigid model (or a placeholder) with the rig-less squash deformer
			local hatchModel = nil
			if source and #collectParts(source) > 0 then
				local okClone, cloned = pcall(prepareClone, source, fxFolder)
				if okClone and cloned then
					hatchModel = cloned
				end
			end
			local rig, baseHeight = nil, 0
			if hatchModel then
				rig, baseHeight = buildRig(hatchModel)
			end
			if not rig or baseHeight < 0.05 then
				warn("[HatchCutscene] Using a placeholder hatchling.")
				if hatchModel then
					hatchModel:Destroy()
				end
				hatchModel = buildPlaceholder(fxFolder, Vector3.new(egg.X, groundY, egg.Z + halfZ + 12))
				rig, baseHeight = buildRig(hatchModel)
			end
			local unitScale = hatchH / baseHeight
			poseHatchling = function(feet: Vector3, yaw: number, pitch: number, roll: number, fraction: number, squash: number)
				local sx = 1 / math.sqrt(squash)
				local scale = Vector3.new(sx, squash, sx) * (unitScale * fraction)
				local root = CFrame.new(feet) * CFrame.Angles(0, yaw + CFG.FaceFix, 0) * CFrame.Angles(pitch, 0, roll)
				for _, e in rig do
					local rel = e.Rel
					e.Part.CFrame = root * CFrame.new(rel.Position * scale) * (rel - rel.Position)
					e.Part.Size = Vector3.new(
						math.clamp(e.Size.X * (rel.RightVector * scale).Magnitude, 0.01, 2048),
						math.clamp(e.Size.Y * (rel.UpVector * scale).Magnitude, 0.01, 2048),
						math.clamp(e.Size.Z * (rel.LookVector * scale).Magnitude, 0.01, 2048)
					)
				end
			end
		end

		-- Hide the old model sitting on the stage (this player's screen only; restored when the scene ends)
		if source then
			for _, part in collectParts(source) do
				part.LocalTransparencyModifier = 1
				table.insert(hiddenSource, part)
			end
		end
		poseHatchling(gStart, 0, 0, 0, CFG.StartFraction, 1)

		---------------------------------------------------------
		-- Lights and ambient particles
		---------------------------------------------------------
		local lightPart = Instance.new("Part")
		lightPart.Anchored = true
		lightPart.CanCollide = false
		lightPart.CanQuery = false
		lightPart.CanTouch = false
		lightPart.Transparency = 1
		lightPart.Size = Vector3.one
		lightPart.Position = egg
		lightPart.Parent = fxFolder
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 40)
		light.Range = math.max(60, H * 2.5)
		light.Brightness = 0
		light.Parent = lightPart

		local ember = Instance.new("ParticleEmitter")
		ember.Rate = 0
		ember.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80))
		ember.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * S), NumberSequenceKeypoint.new(1, 0) })
		ember.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		ember.Lifetime = NumberRange.new(1.2, 2.4)
		ember.Speed = NumberRange.new(4 * S, 14 * S)
		ember.SpreadAngle = Vector2.new(180, 180)
		ember.Acceleration = Vector3.new(0, 7 * S, 0)
		ember.LightEmission = 1
		ember.Parent = lightPart

		local rimPart = Instance.new("Part")
		rimPart.Anchored = true
		rimPart.CanCollide = false
		rimPart.CanQuery = false
		rimPart.CanTouch = false
		rimPart.Transparency = 1
		rimPart.Size = Vector3.one
		rimPart.Position = landing + Vector3.new(hatchH * 1.2, hatchH * 1.5, -hatchH * 0.9)
		rimPart.Parent = fxFolder
		local rim = Instance.new("PointLight")
		rim.Color = Color3.fromRGB(150, 195, 255)
		rim.Range = math.max(40, hatchH * 5)
		rim.Brightness = 0
		rim.Parent = rimPart

		-- A soft warm pool of light on the floor under the hatchling (fades in once it lands)
		local pool = neonPart()
		pool.Shape = Enum.PartType.Cylinder
		pool.Color = Color3.fromRGB(255, 190, 90)
		pool.Transparency = 1
		pool.Size = Vector3.new(0.2 * S, hatchH * 2.6, hatchH * 2.6)
		pool.CFrame = CFrame.new(landing + up * (0.15 * S)) * CFrame.Angles(0, 0, math.pi / 2)
		pool.Parent = fxFolder

		local motes = Instance.new("Part")
		motes.Anchored = true
		motes.CanCollide = false
		motes.CanQuery = false
		motes.CanTouch = false
		motes.Transparency = 1
		motes.Size = Vector3.new(H * 3, H * 1.4, H * 3)
		motes.Position = egg + Vector3.new(0, H * 0.2, H * 0.5)
		motes.Parent = fxFolder
		local moteEmitter = Instance.new("ParticleEmitter")
		moteEmitter.Shape = Enum.ParticleEmitterShape.Box
		moteEmitter.Rate = 22 * Q
		moteEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 225, 170))
		moteEmitter.Size = NumberSequence.new(0.18 * S)
		moteEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(0.8, 0.55), NumberSequenceKeypoint.new(1, 1),
		})
		moteEmitter.Lifetime = NumberRange.new(6, 9)
		moteEmitter.Speed = NumberRange.new(0.3 * S, 1.2 * S)
		moteEmitter.SpreadAngle = Vector2.new(180, 180)
		moteEmitter.LightEmission = 0.7
		moteEmitter.Parent = motes

		---------------------------------------------------------
		-- Effect helpers
		---------------------------------------------------------
		local t = 0 -- scene time, updated every frame

		local function emitBurst(position: Vector3, count: number, o)
			o = o or {}
			local holder = Instance.new("Part")
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Transparency = 1
			holder.Size = Vector3.one
			holder.Position = position
			holder.Parent = fxFolder
			local size = (o.Size or 4) * S
			local life = o.Life or 1.5
			local e = Instance.new("ParticleEmitter")
			e.Enabled = false
			e.Rate = 0
			e.Color = ColorSequence.new(o.Color or DUST)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * (o.Grow or 3)) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, o.Alpha or 0.3), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(life, life + 1)
			e.Speed = NumberRange.new((o.Speed or 20) * S * 0.5, (o.Speed or 20) * S)
			e.SpreadAngle = o.Spread or Vector2.new(180, 180)
			e.Drag = o.Drag or 3
			e.LightEmission = o.Glow or 0.2
			e.Acceleration = o.Accel or Vector3.zero
			e.Parent = holder
			e:Emit(count)
			Debris:AddItem(holder, life + 3)
		end

		local shards = {}
		local function spawnShard(position: Vector3, velocity: Vector3, size: number)
			if #shards >= 150 then
				return
			end
			local part
			if rng:NextNumber() < 0.4 then
				part = Instance.new("WedgePart")
			else
				part = Instance.new("Part")
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Material = shell.Material
			part.Color = shell.Color
			part.Size = Vector3.new(size * rand(0.8, 1.6), size * rand(0.5, 1), size * rand(0.8, 1.6))
			part.CFrame = CFrame.new(position) * CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6))
			part.Parent = fxFolder
			table.insert(shards, {
				Part = part,
				Vel = velocity,
				Spin = Vector3.new(rand(-9, 9), rand(-9, 9), rand(-9, 9)),
				Landed = false,
			})
		end
		local function popChips(point: Vector3, normal: Vector3, count: number)
			for _ = 1, count do
				spawnShard(
					point + normal * 0.3 * S,
					normal * rand(10, 22) * S + Vector3.new(rand(-5, 5), rand(4, 10), rand(-5, 5)) * S,
					H * rand(0.02, 0.045)
				)
			end
		end

		local rays = {}
		local function spawnRay(point: Vector3, normal: Vector3, length: number, width: number, life: number)
			local p = neonPart()
			p.Color = HOT
			p.Transparency = 0.45
			p.Size = Vector3.new(width, width, length)
			p.CFrame = CFrame.lookAt(point + normal * (length / 2), point + normal * length)
			p.Parent = fxFolder
			table.insert(rays, { Part = p, Born = t, Life = life })
		end

		local rings = {}
		local function spawnRing(position: Vector3, delay: number)
			local p = neonPart()
			p.Shape = Enum.PartType.Cylinder
			p.Color = HOT
			p.Transparency = 1
			p.Size = Vector3.new(0.4 * S, 1, 1)
			p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
			p.Parent = fxFolder
			table.insert(rings, { Part = p, Born = t + delay, Pos = position })
		end

		local function doFlash(startTransparency: number)
			ui.Flash.BackgroundTransparency = startTransparency
			TweenService:Create(ui.Flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		end

		---------------------------------------------------------
		-- Knocks and cracks
		---------------------------------------------------------
		local plan, knocks, heroes = {}, {}, {}
		local okPlan, planErr = pcall(function()
			for i, k in KNOCKS do
				local dir
				if k[3] then
					dir = HERO_DIRS[k[3]]
				else
					dir = Vector3.new(rand(-1.2, 1.2), rand(-0.4, 1), rand(-0.2, 1.3))
				end
				if dir.Magnitude < 0.1 then
					dir = up
				end
				local point, normal = Util.EllipsoidSurface(shell.CFrame, half, egg + dir.Unit * 400)
				local knock = { At = k[1], Str = k[2], Point = point, Normal = normal }
				table.insert(knocks, knock)
				if k[3] then
					heroes[k[3]] = knock
				end
				if i <= 15 then
					local hero = k[3] ~= nil
					planCrack(
						plan, shell, half, point, normal,
						if hero then H * 0.5 else H * rand(0.25, 0.4),
						if hero then 1.1 * S else 0.55 * S,
						2, k[1], 0.12, hero
					)
				end
			end
		end)
		if not okPlan then
			warn("[HatchCutscene] Crack planning failed: " .. tostring(planErr))
		end
		for i = 1, 3 do
			if not heroes[i] then
				heroes[i] = { At = 0, Str = 1, Point = egg + Vector3.new(0, 0.1 * H, halfZ), Normal = front }
			end
		end
		local knockIndex = 1
		local cracksAlive = true

		---------------------------------------------------------
		-- Camera shots (offsets are in egg heights; the stage's front is +Z)
		---------------------------------------------------------
		local function P(x: number, y: number, z: number): Vector3
			return egg + Vector3.new(x * H, y * H, z * H)
		end
		local function lin(p0: Vector3, p1: Vector3, l0: Vector3, l1: Vector3, f0: number, f1: number)
			return function(a: number)
				return p0:Lerp(p1, a), l0:Lerp(l1, a), f0 + (f1 - f0) * a
			end
		end
		local function orbit(a0: number, a1: number, r0: number, r1: number, y0: number, y1: number, look: Vector3, f0: number, f1: number)
			return function(a: number)
				local ang = a0 + (a1 - a0) * a
				local r = r0 + (r1 - r0) * a
				return egg + Vector3.new(math.sin(ang) * r * H, (y0 + (y1 - y0) * a) * H, math.cos(ang) * r * H), look, f0 + (f1 - f0) * a
			end
		end

		local h1, h2 = heroes[1], heroes[2]
		local head = landing + up * (hatchH * 0.8) + front * (hatchH * 0.25)
		-- Framing: how far the camera stands so the hatchling fills a given fraction of the screen height
		local function standOff(fraction: number, fov: number): number
			return (hatchH / fraction) / (2 * math.tan(math.rad(fov) / 2))
		end
		-- A camera in front of the hatchling: azimuth (degrees, 0 = straight ahead), distance, height as a fraction of its height
		local function camAt(azimuth: number, distance: number, heightFrac: number): Vector3
			local a = math.rad(azimuth)
			return landing + Vector3.new(math.sin(a) * distance, hatchH * heightFrac, math.cos(a) * distance)
		end
		local lookMid = landing + up * (hatchH * 0.5)
		local lookLow = landing + up * (hatchH * 0.3) -- aim a little low so it sits high, above the title card
		local dWide, dMed, dHero = standOff(0.30, 50), standOff(0.40, 46), standOff(0.60, 38)
		local eggLook = P(0, 0.45, 0)
		local shots = {
			{ 0, 6.0, orbit(-0.75, -0.35, 2.4, 1.9, 0.08, 0.2, eggLook, 62, 54) },
			{ 6.0, 10.0, lin(h1.Point + h1.Normal * (0.5 * H) + up * (0.06 * H), h1.Point + h1.Normal * (0.28 * H), h1.Point, h1.Point, 48, 38) },
			{ 10.0, 13.0, lin(P(0.95, 0.02, 1.15), P(0.7, 0.04, 0.95), P(0, 0.55, 0), P(0, 0.6, 0), 72, 64) },
			{ 13.0, 16.2, orbit(0.55, -0.4, 1.7, 1.3, 0.3, 0.45, eggLook, 56, 66) },
			{ 16.2, CFG.SilenceAt, lin(P(0, 0.5, 1.25), P(0, 0.5, 0.9), P(0, 0.5, 0), P(0, 0.5, 0), 52, 40) },
			{ CFG.SilenceAt, CFG.BurstAt, lin(h2.Point + h2.Normal * (0.3 * H), h2.Point + h2.Normal * (0.18 * H), h2.Point, h2.Point, 36, 28) },
			{ CFG.BurstAt, 21.0, lin(P(0.25, 0.3, 0.7), P(-0.1, 0.28, 1.9), P(0, 0.4, 0), P(0, 0.4, 0), 45, 62) },
			{ 21.0, landTime, lin(P(-0.5, 0.1, 1.3), camAt(-35, dWide, 0.4), P(0, 0.35, 0), lookMid, 52, 50) },
			{ landTime, CFG.CloseUpAt, lin(camAt(-35, dWide, 0.4), camAt(-14, dMed, 0.42), lookMid, lookLow, 50, 46) },
			{ CFG.CloseUpAt, CFG.Total, lin(camAt(-14, dMed, 0.42), camAt(8, dHero, 0.5), lookLow, lookLow, 46, 38) },
		}
		local function shotAt(time: number)
			for _, s in shots do
				if time < s[2] then
					return s[3](ease((time - s[1]) / (s[2] - s[1])))
				end
			end
			return shots[#shots][3](1)
		end

		---------------------------------------------------------
		-- Hatchling motion helpers
		---------------------------------------------------------
		local function hopState(time: number)
			local height, squash = 0, 1
			for _, h0 in CFG.HopAt do
				local u = time - h0
				if u >= -0.2 and u < 0 then
					squash = math.min(squash, 1 - 0.22 * ease((u + 0.2) / 0.2))
				elseif u >= 0 and u <= CFG.HopTime then
					local s = math.sin(math.pi * u / CFG.HopTime)
					height = math.max(height, CFG.HopHeight * H * s)
					squash = 1 + 0.14 * s
				elseif u > CFG.HopTime and u < CFG.HopTime + 0.35 then
					local k = 1 - (u - CFG.HopTime) / 0.35
					squash = math.min(squash, 1 - 0.2 * k * k)
				end
			end
			return height, squash
		end

		---------------------------------------------------------
		-- Begin: cut to the stage and fade up from black
		---------------------------------------------------------
		mood = startMood()
		camera.CameraType = Enum.CameraType.Scriptable
		local firstPos, firstLook, firstFov = shotAt(0)
		camera.CFrame = CFrame.lookAt(firstPos, firstLook)
		camera.FieldOfView = firstFov
		TweenService:Create(black, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
		sceneStarted = true

		-- state
		local rx, rz, rvx, rvz = 0, 0, 0, 0 -- the egg's rocking (a spring)
		local ambience = Audio.Loop("Cut_Ambience", 0)
		if ambience then
			ambience.Fade(0.45, 2.5)
		end
		local rumble, swell, music = nil, nil, nil
		local rumbleStarted, hushed, swelled, scored = false, false, false, false
		local hopLaunched, hopLanded = {}, {}
		local pulse, shake, punch, kick, bloomKick, expKick = 0, 0, 0, 0, 0, 0
		local nextBeat, dubAt = 1.0, -1
		local burstDone, popDone, landDone, chirpDone, thumpDone, cardShown, cardHidden = false, false, false, false, false, false, false
		local membrane = nil
		local memBaseSize = ext * 0.8
		local subShown, subHidden = {}, {}
		local start = os.clock()
		local last = start

		while true do
			local now = os.clock()
			t = now - start
			local dt = math.min(now - last, 0.05)
			last = now
			if skipped or t >= CFG.Total then
				break
			end
			local progress = ease(t / CFG.SilenceAt)

			-- Sound director: the rumble swells with the cracks, then everything drops out for the silence
			if t >= CFG.CrackStart and t < CFG.SilenceAt then
				if not rumbleStarted then
					rumbleStarted = true
					rumble = Audio.Loop("Cut_Rumble", 0.05)
				end
				if rumble then
					rumble.Set(0.08 + 0.92 * progress * progress)
				end
			end
			if not swelled and t >= CFG.SilenceAt - 5.2 then
				swelled = true
				swell = Audio.Play("Cut_Swell", 0.9, 1)
			end
			if not hushed and t >= CFG.SilenceAt then
				hushed = true
				if rumble then
					rumble.Stop(0.12)
				end
				if swell then
					swell.Stop(0.12)
				end
				if ambience then
					ambience.Fade(0, 0.15)
				end
			end
			if not scored and t >= landTime then
				scored = true
				if ambience then
					ambience.Fade(0.4, 2.5)
				end
				music = Audio.Play("Cut_Music", 0.8, 1)
			end
			for i, h0 in CFG.HopAt do
				if not hopLaunched[i] and t >= h0 then
					hopLaunched[i] = true
					playSound("Cut_Hop", 0.8, rand(0.95, 1.1))
				end
				if not hopLanded[i] and t >= h0 + CFG.HopTime then
					hopLanded[i] = true
					playSound("Cut_Land", 0.45, rand(1.3, 1.6))
				end
			end

			-- Heartbeat: lub-dub that speeds up, then silence
			-- Knocks from inside: rock the egg, pop chips, dust, light rays
			while knocks[knockIndex] and knocks[knockIndex].At <= t and t < CFG.SilenceAt do
				local k = knocks[knockIndex]
				knockIndex += 1
				local ang = rand(0, math.pi * 2)
				rvx += math.cos(ang) * k.Str * 0.9
				rvz += math.sin(ang) * k.Str * 0.9
				pulse = math.max(pulse, 1)
				shake = math.max(shake, 0.25 + 0.2 * k.Str)
				popChips(k.Point, k.Normal, 2 + math.floor(k.Str * 2))
				emitBurst(
					Vector3.new(egg.X + rand(-1, 1) * halfZ * 0.7, groundY + 0.2 * S, egg.Z + rand(-1, 1) * halfZ * 0.7),
					6 + math.floor(k.Str * 6),
					{ Size = 3, Grow = 3, Speed = 14, Life = 1.4, Alpha = 0.5 }
				)
				emitBurst(egg + up * (H * 0.48), 5, {
					Size = 1.2, Grow = 1, Speed = 4, Life = 1.6, Alpha = 0.4,
					Accel = Vector3.new(0, -25 * S, 0), Spread = Vector2.new(60, 60),
				})
				if t > CFG.CrackStart + 3 then
					spawnRay(k.Point, k.Normal, H * rand(0.5, 0.9), 0.5 * S, 0.45)
				end
				playSound("Cut_Crack", math.min(0.5 + 0.3 * k.Str, 1), rand(0.85, 1.1))
			end

			-- The silence, then one huge last beat
			if t >= CFG.SilenceAt and t < CFG.BurstAt then
				shake = 0
			end
			if not thumpDone and t >= CFG.ThumpAt then
				thumpDone = true
				pulse = 4
				shake = 0.6
				playSound("Cut_Thump", 1, 1)
			end

			-- The burst
			if not burstDone and t >= CFG.BurstAt then
				burstDone = true
				cracksAlive = false
				for _, seg in plan do
					if seg.Part then
						seg.Part:Destroy()
						seg.Part = nil
					end
					if seg.Halo then
						seg.Halo:Destroy()
						seg.Halo = nil
					end
				end
				-- Big chunks and small shards from the real surface
				for i = 1, math.floor(70 * Q) do
					local dir = Vector3.new(rand(-1, 1), rand(0.1, 1), rand(-1, 1)).Unit
					local point = Util.EllipsoidSurface(shell.CFrame, half, egg + dir * 400)
					spawnShard(
						point,
						dir * rand(0.9, 2.1) * H + up * rand(0.3, 0.9) * H,
						H * (if i <= 10 then rand(0.09, 0.16) else rand(0.03, 0.07))
					)
				end
				shell.CFrame = shellBase + Vector3.new(0, -2000, 0) -- hidden until the scene ends
				for _ = 1, 16 do
					spawnRay(egg, Vector3.new(rand(-1, 1), rand(-0.2, 1), rand(-1, 1)).Unit, H * rand(0.8, 1.6), 0.8 * S, 0.9)
				end
				membrane = neonPart()
				membrane.Color = Color3.fromRGB(255, 170, 40)
				membrane.Transparency = 0.55
				membrane.Size = memBaseSize
				membrane.CFrame = CFrame.new(egg)
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = membrane
				membrane.Parent = fxFolder
				emitBurst(Vector3.new(egg.X, groundY + H * 0.05, egg.Z), 100, { Size = 4, Grow = 3.5, Speed = 45, Life = 2, Alpha = 0.3 })
				emitBurst(egg, 60, { Size = 0.8, Grow = 0.2, Speed = 70, Life = 1.4, Alpha = 0, Glow = 1, Color = Color3.fromRGB(255, 200, 90) })
				spawnRing(Vector3.new(egg.X, groundY + 0.5 * S, egg.Z), 0)
				spawnRing(Vector3.new(egg.X, groundY + 0.5 * S, egg.Z), 0.18)
				doFlash(0)
				shake = 1.6
				punch = 24
				kick = H * 0.15
				pulse = 5
				bloomKick = 1.6
				expKick = 1.0
				ember.Rate = 25
				playSound("Cut_Burst", 1, 1)
				playSound("Cut_Whoosh", 0.9, 1)
			end

			-- The membrane tears
			if not popDone and t >= CFG.PopAt then
				popDone = true
				doFlash(0.45)
				shake = math.max(shake, 0.9)
				punch = math.max(punch, 8)
				pulse = 2
				emitBurst(egg, 45, {
					Size = 1.2, Grow = 0.4, Speed = 50, Life = 1.3, Alpha = 0.1, Glow = 0.8,
					Color = Color3.fromRGB(255, 175, 60), Accel = Vector3.new(0, -90 * S, 0),
				})
				playSound("Cut_Pop", 0.8, 1)
			end

			-- It lands
			if not landDone and t >= landTime then
				landDone = true
				shake = math.max(shake, 1.1)
				emitBurst(landing + up * (H * 0.02), 45, { Size = 3, Grow = 3, Speed = 30, Life = 1.6 })
				spawnRing(landing + up * (0.4 * S), 0)
				playSound("Cut_Land", 1, 1)
			end
			if not chirpDone and t >= CFG.ChirpAt then
				chirpDone = true
				playSound("Cut_Chirp", 1, 1)
			end

			-- Subtitles
			for i, s in SUBS do
				if not subShown[i] and t >= s[1] then
					subShown[i] = true
					ui.Subtitle.Text = string.format('<font color="#FFD27A"><b>%s:</b></font> %s', CuratorName, s[3])
					showLabel(ui.Subtitle, 0.3)
				end
				if subShown[i] and not subHidden[i] and t >= s[2] then
					subHidden[i] = true
					hideLabel(ui.Subtitle, 0.35)
				end
			end

			-- Discovery card
			if not cardShown and t >= CFG.CardAt then
				playSound("Cut_Sting", 0.9, 1)
				cardShown = true
				TweenService:Create(ui.Line, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(0.3, 0.004) }):Play()
				showLabel(ui.Labels[1], 0.5)
				task.delay(0.4, function()
					showLabel(ui.Labels[2], 0.4)
					ui.Pop.Scale = 1.3
					TweenService:Create(ui.Pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				end)
				task.delay(1.0, function()
					showLabel(ui.Labels[3], 0.5)
				end)
			end
			if not cardHidden and t >= CFG.CardOutAt then
				cardHidden = true
				for _, label in ui.Labels do
					hideLabel(label, 0.6)
				end
				TweenService:Create(ui.Line, TweenInfo.new(0.5), { Size = UDim2.fromScale(0, 0.004) }):Play()
			end
			if not blackDone and t >= CFG.BlackAt then
				blackDone = true
				TweenService:Create(black, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
			end

			---------------------------------------------------------
			-- The egg: rocking spring, heartbeat thump, cracks
			---------------------------------------------------------
			pulse = math.max(0, pulse - dt * 5)
			local damping = if t < CFG.SilenceAt then 2.2 else 9
			rvx += (-81 * rx - damping * rvx) * dt
			rvz += (-81 * rz - damping * rvz) * dt
			rx = math.clamp(rx + rvx * dt, -0.2, 0.2)
			rz = math.clamp(rz + rvz * dt, -0.2, 0.2)
			local lift = math.min(pulse, 1.5) * H * 0.003
			local breathe = 1 + 0.012 * math.min(pulse, 3)
			local rockCF = CFrame.new(gPoint + Vector3.new(0, lift, 0)) * CFrame.Angles(rx, 0, rz) * CFrame.new(-gPoint)

			if not burstDone then
				shell.CFrame = rockCF * shellBase
				shell.Size = shellSize * breathe
			end

			if cracksAlive then
				local level
				if t < CFG.CrackStart then
					level = 0.05
				elseif t < CFG.SilenceAt then
					level = 0.1 + 0.8 * ((t - CFG.CrackStart) / (CFG.SilenceAt - CFG.CrackStart))
				elseif t < CFG.ThumpAt then
					level = 0.15
				else
					level = 1
				end
				local color = crackColor(math.clamp(level + math.min(pulse, 1) * 0.25, 0, 1))
				for _, seg in plan do
					if t >= seg.Reveal then
						if not seg.Part and not seg.Failed then
							local main, halo = makeSegment(seg, S)
							if main then
								seg.Part, seg.Halo = main, halo
								seg.Base = main.CFrame
								seg.HaloBase = halo and halo.CFrame
								main.Parent = fxFolder
								if halo then
									halo.Parent = fxFolder
								end
							else
								seg.Failed = true
							end
						end
						if seg.Part then
							seg.Part.Color = color
							local p = egg + (seg.Base.Position - egg) * breathe
							seg.Part.CFrame = rockCF * (CFrame.new(p) * (seg.Base - seg.Base.Position))
							if seg.Halo then
								seg.Halo.Color = color
								local hp = egg + (seg.HaloBase.Position - egg) * breathe
								seg.Halo.CFrame = rockCF * (CFrame.new(hp) * (seg.HaloBase - seg.HaloBase.Position))
							end
						end
					end
				end
			end

			-- Embers leak out as the cracks grow
			if t >= CFG.CrackStart and t < CFG.SilenceAt then
				ember.Rate = (4 + 60 * progress * progress) * Q
			elseif t >= CFG.SilenceAt and t < CFG.BurstAt then
				ember.Rate = 0
			end

			---------------------------------------------------------
			-- Shards, rays, rings, membrane
			---------------------------------------------------------
			local slow = 1
			if t >= CFG.BurstAt and t < CFG.BurstAt + 2.2 then
				slow = 0.1 + 0.9 * ease((t - CFG.BurstAt) / 2.2)
			end
			local pdt = dt * slow
			local G = math.max(60, 110 * S)
			for _, s in shards do
				if not s.Landed then
					s.Vel += Vector3.new(0, -G, 0) * pdt
					local cf = s.Part.CFrame
					local pos = cf.Position + s.Vel * pdt
					local floor = groundY + s.Part.Size.Y * 0.45
					if pos.Y < floor then
						pos = Vector3.new(pos.X, floor, pos.Z)
						if math.abs(s.Vel.Y) > 14 * S then
							s.Vel = Vector3.new(s.Vel.X * 0.5, -s.Vel.Y * 0.3, s.Vel.Z * 0.5)
							s.Spin *= 0.5
						else
							s.Landed = true
						end
					end
					s.Part.CFrame = CFrame.new(pos) * (cf - cf.Position)
						* CFrame.Angles(s.Spin.X * pdt, s.Spin.Y * pdt, s.Spin.Z * pdt)
				end
			end

			for i = #rays, 1, -1 do
				local r = rays[i]
				local a = (t - r.Born) / r.Life
				if a >= 1 then
					r.Part:Destroy()
					table.remove(rays, i)
				else
					r.Part.Transparency = 0.45 + 0.55 * a
				end
			end

			for i = #rings, 1, -1 do
				local r = rings[i]
				local age = t - r.Born
				if age >= 1.1 then
					r.Part:Destroy()
					table.remove(rings, i)
				elseif age >= 0 then
					local a = age / 1.1
					local d = H * (0.4 + 3.2 * a)
					r.Part.Size = Vector3.new(0.4 * S * (1 - a), d, d)
					r.Part.Transparency = 0.3 + 0.7 * a
				end
			end

			if membrane then
				if t < CFG.PopAt then
					local bulge = 1 + 0.04 * math.sin(t * 14) + 0.05 * math.max(0, math.sin(t * 3.1))
					membrane.Size = memBaseSize * bulge
					membrane.CFrame = CFrame.new(egg + Vector3.new(rand(-1, 1), 0, rand(-1, 1)) * H * 0.004)
				else
					local a = math.clamp((t - CFG.PopAt) / 0.5, 0, 1)
					membrane.Size = memBaseSize * (1 + 0.6 * a)
					membrane.Transparency = 0.55 + 0.45 * a
					if a >= 1 then
						membrane:Destroy()
						membrane = nil
					end
				end
			end

			---------------------------------------------------------
			-- The hatchling
			---------------------------------------------------------
			if t < CFG.PopAt then
				-- Thrashing inside the egg, then pushing against the membrane
				local pre = ease((t - CFG.CrackStart) / (CFG.SilenceAt - CFG.CrackStart))
				local amp2 = if t < CFG.BurstAt then pre else 1
				local fraction = CFG.StartFraction
				if t >= CFG.BurstAt then
					fraction = lerp(CFG.StartFraction, 0.8, ease((t - CFG.BurstAt) / (CFG.PopAt - CFG.BurstAt)))
				end
				poseHatchling(gStart, math.sin(t * 7) * 0.7 * amp2, 0, math.sin(t * 12) * 0.14 * amp2, fraction, 1 + 0.06 * math.sin(t * 10) * amp2)
			elseif t < landTime then
				-- Climbing out in an arc, stretching in the air
				local a = ease((t - CFG.PopAt) / CFG.RiseTime)
				local arc = math.sin(a * math.pi)
				local ground = gStart:Lerp(landing, a) + up * (arc * H * 0.55)
				poseHatchling(ground, 0, 0, arc * 0.25, lerp(0.8, 1, a), 1 + 0.18 * arc)
			else
				-- Landing wobble, shake-off, look around, chirp, hops
				local u = t - landTime
				local hop, hopSq = hopState(t)
				local landSq = 1 - 0.3 * math.exp(-u * 6) * math.cos(u * 14)
				local breath = 1 + 0.018 * math.sin(t * 4.5)
				local calm = ease((t - (CFG.CloseUpAt - 1.5)) / 1.5)
				local yaw = math.sin(u * 1.4) * 0.6 * (1 - calm)
				local roll = math.sin(t * 2.2) * 0.025
				local shakeOff = t - (landTime + 0.5)
				if shakeOff >= 0 and shakeOff < 1 then
					roll += math.sin(shakeOff * 38) * 0.14 * (1 - shakeOff)
				end
				local pitch, chirpSq = 0, 1
				local cu = t - CFG.ChirpAt
				if cu >= 0 and cu <= 0.5 then
					local s = math.sin(math.pi * cu / 0.5)
					chirpSq = 1 + 0.2 * s
					pitch = 0.18 * s
				end
				poseHatchling(landing + up * hop, yaw, pitch, roll, 1, landSq * hopSq * breath * chirpSq)
			end

			---------------------------------------------------------
			-- Light, mood and camera
			---------------------------------------------------------
			local lightLevel
			if t < CFG.SilenceAt then
				lightLevel = 0.3 + 5 * progress
			elseif t < CFG.BurstAt then
				lightLevel = 0.15
			elseif t < CFG.CloseUpAt then
				lightLevel = 4 + 10 * (1 - ease((t - CFG.BurstAt) / (CFG.CloseUpAt - CFG.BurstAt)))
			else
				lightLevel = 4
			end
			light.Brightness = lightLevel + pulse * 3 + (if t < CFG.SilenceAt then noise2(t * 17, 2.2) * 0.4 * progress else 0)
			rim.Brightness = if t >= landTime then 2.5 * ease((t - landTime) / 1.5) else 0
			if t >= landTime then
				pool.Transparency = 1 - 0.7 * ease((t - landTime) / 1.5)
			end

			bloomKick *= math.exp(-dt * 2.5)
			expKick *= math.exp(-dt * 2.2)
			local bloomBase
			if t < CFG.SilenceAt then
				bloomBase = 0.6 + 0.9 * progress
			elseif t < CFG.BurstAt then
				bloomBase = 0.4
			else
				bloomBase = 1.1
			end
			mood.Bloom.Intensity = bloomBase + bloomKick
			mood.Grade.TintColor = COOL_TINT:Lerp(WARM_TINT, ease(t / CFG.BurstAt))
			if burstDone then
				Lighting.ExposureCompensation = -0.35 + expKick
			end

			local amp = shake
			if t < CFG.SilenceAt then
				amp += 0.02 + 0.15 * progress * progress
			elseif t < CFG.BurstAt then
				amp = 0.012
			end
			shake = math.max(0, shake - dt * 2)
			punch *= math.exp(-dt * 3.2)
			kick *= math.exp(-dt * 3)

			local pos, look, fov = shotAt(t)
			local toLook = look - pos
			if toLook.Magnitude > 0.01 then
				pos -= toLook.Unit * kick
			end
			camera.FieldOfView = fov + punch
			camera.CFrame = CFrame.lookAt(pos, look)
				* CFrame.new(noise2(t * 13, 1.3) * amp * S, noise2(t * 11, 7.1) * amp * S, 0)
				* CFrame.Angles(0, 0, noise2(t * 7, 3.3) * amp * 0.01)

			local dist = (pos - look).Magnitude
			mood.DOF.FocusDistance = math.max(dist, 1)
			mood.DOF.InFocusRadius = math.max(6 * S, dist * 0.35)

			RunService.RenderStepped:Wait()
		end
	end)
	if not ok then
		warn("[HatchCutscene] " .. tostring(err))
	end

	-- Cover with black (skip, error, or the normal ending), then put everything back
	keyConnection:Disconnect()
	Audio.StopAll(0.6)
	TweenService:Create(black, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	if not blackDone then
		task.wait(0.35)
	end

	if shell and shellBase then
		shell.CFrame = shellBase
		shell.Size = shellSize
		shell.Transparency = shellTransparency
	end
	for _, part in hiddenSource do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	if fxFolder then
		fxFolder:Destroy()
	end
	if mood then
		mood.Restore()
	end

	-- Wait until the server has moved us back to the field
	if typeof(stagePos) == "Vector3" then
		local deadline = os.clock() + 4
		while os.clock() < deadline do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - stagePos).Magnitude > 200 then
				break
			end
			task.wait(0.1)
		end
	end

	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = savedFov
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	for _, other in hiddenGuis do
		if other.Parent then
			other.Enabled = true
		end
	end
	for _, label in ui.Labels do
		hideLabel(label, 0.2)
	end
	hideLabel(ui.Subtitle, 0.2)
	TweenService:Create(black, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	tweenBars(ui.Top, ui.Bottom, 0, 0.5)
	task.delay(0.7, function()
		ui.Gui:Destroy()
	end)
	running = false
end

-- Play whenever the server bumps CutsceneId (not for a cutscene that was already over when we joined)
local lastId = Workspace:GetAttribute("CutsceneId") or 0
Workspace:GetAttributeChangedSignal("CutsceneId"):Connect(function()
	local id = Workspace:GetAttribute("CutsceneId") or 0
	if id <= lastId then
		return
	end
	lastId = id
	task.wait() -- let the other attributes arrive
	if Workspace:GetAttribute("Cutscene") == "Hatch" then
		task.spawn(run)
	end
end)

print("[HatchCutscene] v3 Init OK")
