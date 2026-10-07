local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- The same controller modules the rest of the client uses (cached, so GetAim works)
local controllers = script.Parent:WaitForChild("Controllers", 10)
local okE, EggView = pcall(require, controllers and controllers:WaitForChild("EggView", 10))
if not okE then
	EggView = nil
end
local okP, PickupController = pcall(require, controllers and controllers:WaitForChild("PickupController", 10))
if not okP then
	PickupController = nil
end

---------------------------------------------------------------------
-- Settings. Pos = studs from the camera: X right, Y up, Z forward is NEGATIVE.
-- Rot = extra tilt in degrees (X = tip up/down, Y = turn left/right, Z = roll). Scale = tool size.
-- Change these numbers to move a tool. Style: Swing, Drill, Sweep, Suck.
---------------------------------------------------------------------
local POSES = {
	IcePick = { Pos = Vector3.new(0.9, -1.2, -1.5), Rot = Vector3.new(0, 0, 0), Scale = 0.65, Style = "Swing" },
	Pickaxe = { Pos = Vector3.new(0.9, -1.2, -1.5), Rot = Vector3.new(55, 0, 0), Scale = 0.75, Style = "Swing" },
	Drill = { Pos = Vector3.new(0.8, -0.8, -1.9), Rot = Vector3.new(0, 0, 0), Scale = 1, Style = "Drill" },
	Brush = { Pos = Vector3.new(0.9, -0.85, -1.7), Rot = Vector3.new(0, 0, 0), Scale = 1, Style = "Sweep" },
	Vacuum = { Pos = Vector3.new(0.8, -0.8, -1.9), Rot = Vector3.new(0, 0, 0), Scale = 1, Style = "Suck" },
}
POSES.ClimbRig = { Pos = Vector3.new(0.9, -0.85, -1.7), Rot = Vector3.new(0, 0, 0), Scale = 1, Style = "Carry" } -- held still, no swing
local DEFAULT_POSE = { Pos = Vector3.new(0.9, -0.85, -1.7), Rot = Vector3.new(0, 0, 0), Scale = 1, Style = "Swing" }

local GLOVE = Color3.fromRGB(38, 36, 42)
local CUFF = Color3.fromRGB(62, 58, 66)
local SLEEVE = Color3.fromRGB(88, 98, 112)
local SKIN_FALLBACK = Color3.fromRGB(226, 176, 140)
local PIVOT = Vector3.new(0.9, -1.6, -0.2) -- the "shoulder" the swings turn around

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local viewFolder = Instance.new("Folder")
viewFolder.Name = "ViewModel"

local armItems = {} -- { Part, Offset } offsets are relative to the hand frame
local toolItems = {}
local armCharacter = nil
local currentTool = nil
local poseName = nil
local toolReady = false
local conns = {}
local hidden = false

local holding = false
local holdAmt = 0
local swingStart = -10
local swingDur = 0.2
local swingImpacted = true
local bobAmt = 0
local kick = 0
local kickRoll = 0
local HAND_KICK_DEG = 4 -- how far the hand dips on a landed hit (degrees at full strength)
local HAND_ROLL_DEG = 1.5 -- small sideways twist of the hand
local drillTimer = 0

---------------------------------------------------------------------
-- Effects (client only)
---------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local DEBUG_FX = false -- true: print once a second what the Brush and Vacuum effects see
local lastDebug = 0

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ToolFX"
fxFolder.Parent = Workspace

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function ramp(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function fxPart(size)
	local p = Instance.new("Part")
	p.Size = size
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = fxFolder
	return p
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

-- Hit effects (Ice Pick, Pickaxe, Drill, Brush)
local impactPart = fxPart(Vector3.new(0.2, 0.2, 0.2))
local impactAttachment = Instance.new("Attachment")
impactAttachment.Parent = impactPart

local sparks = emitter(impactAttachment, {
	Texture = SPARKLE,
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 200)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 190, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 30)),
	}),
	LightEmission = 1,
	Size = ramp(0.55, 0),
	Transparency = ramp(0, 1),
	Lifetime = NumberRange.new(0.25, 0.6),
	Speed = NumberRange.new(16, 38),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -55, 0),
})
local embers = emitter(impactAttachment, {
	Texture = SPARKLE,
	Color = ColorSequence.new(Color3.fromRGB(255, 170, 60)),
	LightEmission = 1,
	Size = ramp(0.28, 0),
	Transparency = ramp(0.1, 1),
	Lifetime = NumberRange.new(0.6, 1.2),
	Speed = NumberRange.new(3, 10),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -8, 0),
	Drag = 1.5,
})
local dust = emitter(impactAttachment, {
	Texture = SMOKE,
	Color = ColorSequence.new(Color3.fromRGB(176, 166, 150)),
	Size = ramp(1.2, 4.5),
	Transparency = ramp(0.45, 1),
	Lifetime = NumberRange.new(0.7, 1.3),
	Speed = NumberRange.new(3, 9),
	SpreadAngle = Vector2.new(180, 180),
	Drag = 2.5,
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-60, 60),
})
local glow = emitter(impactAttachment, {
	Texture = SPARKLE,
	Color = ColorSequence.new(Color3.fromRGB(255, 220, 150)),
	LightEmission = 1,
	Size = ramp(5, 0),
	Transparency = ramp(0.35, 1),
	Lifetime = NumberRange.new(0.12, 0.16),
	Speed = NumberRange.new(0, 0),
})
local motes = emitter(impactAttachment, {
	Texture = SPARKLE,
	Color = ColorSequence.new(Color3.fromRGB(255, 232, 170)),
	LightEmission = 0.7,
	Size = ramp(0.22, 0),
	Transparency = ramp(0.2, 1),
	Lifetime = NumberRange.new(0.8, 1.4),
	Speed = NumberRange.new(1, 4),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, 2, 0),
})
local impactLight = Instance.new("PointLight")
impactLight.Color = Color3.fromRGB(255, 170, 80)
impactLight.Range = 14
impactLight.Brightness = 0
impactLight.Parent = impactPart

-- Vacuum effects: a wind vortex at the tool tip, pulling dust in from the ground
local vacRadius = 6
pcall(function()
	local cfg = require(ReplicatedStorage.Shared.GameConfig)
	for _, def in cfg.Pickup.Upgrades do
		if def.Id == "Vacuum" then
			vacRadius = math.min(def.Sweep, 8)
		end
	end
end)

local TIP_R = 2.0 -- radius of the swirl at the nozzle
local ARMS = 5
local FUNNEL = 3 -- emitters on the ground that shoot toward the nozzle
local FUNNEL_R = math.min(vacRadius * 0.7, 4.5)
local FUNNEL_LIFE = 0.4

-- ground dust pulled in from the whole area
local vacPart = fxPart(Vector3.new(vacRadius * 2, 0.2, vacRadius * 2))
local vacAttachment = Instance.new("Attachment")
vacAttachment.Parent = vacPart
local vacDust = emitter(vacAttachment, {
	Rate = 45,
	Shape = Enum.ParticleEmitterShape.Disc,
	ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
	ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	Texture = SMOKE,
	Color = ColorSequence.new(Color3.fromRGB(170, 190, 205)),
	Size = ramp(1.8, 0.3),
	Transparency = ramp(0.6, 1),
	Lifetime = NumberRange.new(0.5, 0.8),
	Speed = NumberRange.new(5, 8),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-120, 120),
})

-- soft glow and light at the nozzle
local vacCorePart = fxPart(Vector3.new(0.4, 0.4, 0.4))
local vacCoreAttachment = Instance.new("Attachment")
vacCoreAttachment.Parent = vacCorePart
local vacGlow = emitter(vacCoreAttachment, {
	Rate = 12,
	Texture = SMOKE,
	Color = ColorSequence.new(Color3.fromRGB(190, 225, 255)),
	LightEmission = 0.6,
	Size = ramp(1.4, 2.6),
	Transparency = ramp(0.75, 1),
	Lifetime = NumberRange.new(0.4, 0.6),
	Speed = NumberRange.new(0, 0),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-90, 90),
})
local vacLight = Instance.new("PointLight")
vacLight.Color = Color3.fromRGB(150, 200, 255)
vacLight.Range = 14
vacLight.Brightness = 0
vacLight.Parent = vacCorePart

-- pinwheel at the tip: emitters orbit the nozzle and shoot inward at an angle
local vacArms = {}
for i = 1, ARMS do
	local part = fxPart(Vector3.new(0.3, 0.3, 0.3))
	local att = Instance.new("Attachment")
	att.Parent = part
	local streak = emitter(att, {
		Rate = 50,
		EmissionDirection = Enum.NormalId.Front,
		Texture = SPARKLE,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Color = ColorSequence.new(Color3.fromRGB(205, 232, 255)),
		LightEmission = 0.8,
		Size = ramp(0.5, 0.05),
		Transparency = ramp(0.1, 1),
		Lifetime = NumberRange.new(0.35, 0.45),
		Speed = NumberRange.new(TIP_R * 2.4, TIP_R * 3),
		SpreadAngle = Vector2.new(5, 5),
	})
	local wisp = emitter(att, {
		Rate = 16,
		EmissionDirection = Enum.NormalId.Front,
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(215, 235, 250)),
		LightEmission = 0.25,
		Size = ramp(1.2, 0.3),
		Transparency = ramp(0.7, 1),
		Lifetime = NumberRange.new(0.4, 0.55),
		Speed = NumberRange.new(TIP_R * 1.8, TIP_R * 2.2),
		SpreadAngle = Vector2.new(8, 8),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-150, 150),
	})
	vacArms[i] = { part = part, streak = streak, wisp = wisp }
end

-- funnel: ground emitters orbit and aim at the nozzle (speed is set every frame from the distance)
local vacFunnel = {}
for i = 1, FUNNEL do
	local part = fxPart(Vector3.new(0.3, 0.3, 0.3))
	local att = Instance.new("Attachment")
	att.Parent = part
	local streak = emitter(att, {
		Rate = 45,
		EmissionDirection = Enum.NormalId.Front,
		Texture = SPARKLE,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Color = ColorSequence.new(Color3.fromRGB(205, 232, 255)),
		LightEmission = 0.8,
		Size = ramp(0.6, 0.05),
		Transparency = ramp(0.1, 1),
		Lifetime = NumberRange.new(FUNNEL_LIFE * 0.95, FUNNEL_LIFE * 1.05),
		Speed = NumberRange.new(20, 22),
		SpreadAngle = Vector2.new(4, 4),
	})
	local wisp = emitter(att, {
		Rate = 16,
		EmissionDirection = Enum.NormalId.Front,
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(205, 225, 240)),
		LightEmission = 0.2,
		Size = ramp(1.8, 0.4),
		Transparency = ramp(0.65, 1),
		Lifetime = NumberRange.new(FUNNEL_LIFE * 0.95, FUNNEL_LIFE * 1.05),
		Speed = NumberRange.new(20, 22),
		SpreadAngle = Vector2.new(6, 6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
	})
	vacFunnel[i] = { part = part, streak = streak, wisp = wisp }
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local Debris = game:GetService("Debris")
local CHIP_COLORS = {
	Color3.fromRGB(236, 226, 206),
	Color3.fromRGB(205, 190, 165),
	Color3.fromRGB(170, 158, 140),
}

-- small stone chips that fly off and fall (only seen by this player)
local function chips(position, amount)
	for _ = 1, amount do
		local c = Instance.new("Part")
		local s = 0.12 + math.random() * 0.2
		c.Size = Vector3.new(s, s * (0.6 + math.random() * 0.5), s)
		c.Color = CHIP_COLORS[math.random(#CHIP_COLORS)]
		c.Material = Enum.Material.Slate
		c.CanTouch = false
		c.CanQuery = false
		c.CastShadow = false
		c.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		c.Parent = fxFolder
		c.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 22, 10 + math.random() * 14, (math.random() - 0.5) * 22)
		c.AssemblyAngularVelocity = Vector3.new(math.random() * 20, math.random() * 20, math.random() * 20)
		TweenService:Create(c, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.new(0.02, 0.02, 0.02),
		}):Play()
		Debris:AddItem(c, 0.9)
	end
end

-- strength: 1 = a full hit, about 0.4 = a drill tick
local function impact(position, strength)
	impactPart.Position = position
	sparks:Emit(math.floor(8 + 26 * strength))
	embers:Emit(math.floor(3 + 10 * strength))
	dust:Emit(math.floor(3 + 9 * strength))
	if strength >= 0.8 then
		glow:Emit(2)
		chips(position, 7)
	elseif math.random() < 0.35 then
		chips(position, 2)
	end
	impactLight.Brightness = 1.5 + 3 * strength
	TweenService:Create(impactLight, TweenInfo.new(0.15), { Brightness = 0 }):Play()
end

local function brushDust(position)
	impactPart.Position = position + Vector3.new(0, 0.2, 0)
	dust:Emit(2)
	motes:Emit(2)
end

local function setSuck(point, tipCF)
	local on = point ~= nil and tipCF ~= nil
	if on then
		local t = os.clock()
		local tip = tipCF.Position
		local toGround = point - tip
		local axis = if toGround.Magnitude > 0.5 then toGround.Unit else tipCF.LookVector
		local ref = if math.abs(axis.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
		local right = axis:Cross(ref).Unit
		local up = right:Cross(axis)
		local nozzle = tip + axis * 0.3

		vacPart.CFrame = CFrame.new(point + Vector3.new(0, 0.25, 0))
		vacCorePart.CFrame = CFrame.new(nozzle)

		-- pinwheel around the nozzle
		local skew = CFrame.fromAxisAngle(axis, 0.6)
		for i, arm in vacArms do
			local ang = t * 4 + (i - 1) * (math.pi * 2 / ARMS)
			local pos = nozzle + (right * math.cos(ang) + up * math.sin(ang)) * TIP_R
			local dir = skew:VectorToWorldSpace((nozzle - pos).Unit)
			arm.part.CFrame = CFrame.lookAt(pos, pos + dir)
		end

		-- funnel from the ground into the nozzle
		for i, f in vacFunnel do
			local ang = -t * 3 + (i - 1) * (math.pi * 2 / FUNNEL)
			local pos = point + Vector3.new(math.cos(ang) * FUNNEL_R, 0.3, math.sin(ang) * FUNNEL_R)
			local spd = math.max((nozzle - pos).Magnitude, 1) / FUNNEL_LIFE
			f.part.CFrame = CFrame.lookAt(pos, nozzle)
			f.streak.Speed = NumberRange.new(spd * 0.97, spd * 1.03)
			f.wisp.Speed = NumberRange.new(spd * 0.97, spd * 1.03)
		end
	end
	for _, arm in vacArms do
		arm.streak.Enabled = on
		arm.wisp.Enabled = on
	end
	for _, f in vacFunnel do
		f.streak.Enabled = on
		f.wisp.Enabled = on
	end
	vacDust.Enabled = on
	vacGlow.Enabled = on
	vacLight.Brightness = if on then 2 else 0
end

local function aimPoint()
	if not EggView then
		return nil
	end
	local ok, eggId, position = pcall(EggView.GetAim)
	if ok and eggId then
		return position
	end
	return nil
end

local function pieceUnderAim()
	if not PickupController then
		return false
	end
	local ok, piece = pcall(PickupController.PieceUnderAim)
	return ok and piece ~= nil
end

-- Where the vacuum nozzle is: an Attachment named FxTip on the tool model, otherwise a guess in front of the camera
local function tipCFrame(cam)
	local found = viewFolder:FindFirstChild("FxTip", true)
	if found and found:IsA("Attachment") then
		return found.WorldCFrame
	elseif found and found:IsA("BasePart") then
		return found.CFrame
	end
	return cam.CFrame * CFrame.new(0.9, -0.8, -3.2)
end

local function groundPoint(character, cam)
	rayParams.FilterDescendantsInstances = { character, viewFolder, fxFolder }
	local result = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 60, rayParams)
	return result and result.Position or nil
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
---------------------------------------------------------------------
-- Pickup fly-in: pieces taken by the Brush or Vacuum fly into the tool tip.
-- The server marks a piece with FlyTime and FlyUserId, keeps it for that long, then collects it.
---------------------------------------------------------------------
local MAX_FLYERS = 40
local flyers = {} -- [piece] = flight data
local flyCount = 0

local function startFly(piece)
	if flyers[piece] or not piece:IsA("BasePart") or flyCount >= MAX_FLYERS then
		return
	end
	local dur = piece:GetAttribute("FlyTime")
	if type(dur) ~= "number" or dur <= 0 then
		return
	end
	local gui = piece:FindFirstChild("CountLabel")
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = false
	end
	flyers[piece] = {
		t0 = os.clock(),
		dur = dur,
		userId = piece:GetAttribute("FlyUserId"),
		from = piece.Position,
		size = piece.Size,
		rot = piece.CFrame.Rotation,
		side = if math.random() < 0.5 then -1 else 1,
		sx = (math.random() - 0.5) * 14,
		sy = (math.random() - 0.5) * 14,
		sz = (math.random() - 0.5) * 14,
	}
	flyCount += 1
end

-- Where the piece is heading: your own tool tip, or the body of the player who is collecting it
local function flyTarget(f, cam)
	if f.userId == player.UserId then
		if cam and viewFolder.Parent then
			return tipCFrame(cam).Position
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return root and root.Position + Vector3.new(0, 1, 0)
	end
	local other = f.userId and Players:GetPlayerByUserId(f.userId)
	local root = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position + Vector3.new(0, 1, 0)
end

local function updateFlyers(cam, now)
	if next(flyers) == nil then
		return
	end
	for piece, f in flyers do
		if not piece.Parent then
			flyers[piece] = nil
			flyCount -= 1
			continue
		end
		local target = flyTarget(f, cam)
		local p = (now - f.t0) / f.dur
		if not target or p >= 1 then
			piece.LocalTransparencyModifier = 1 -- hidden until the server removes it
			if target then
				impactPart.Position = target
				motes:Emit(2) -- small sparkle puff where it lands
			end
			flyers[piece] = nil
			flyCount -= 1
			continue
		end

		local q = 0.3 * p + 0.7 * p * p -- speeds up as it nears the tool
		local from = f.from
		local dir = target - from
		local dist = dir.Magnitude
		local side = dir:Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
		local ctrl = (from + target) / 2 + Vector3.new(0, 1.2 + dist * 0.12, 0) + side * (f.side * dist * 0.2)
		local a = 1 - q
		local pos = from * (a * a) + ctrl * (2 * a * q) + target * (q * q)

		-- a small swirl that tightens toward the nozzle
		local axis = if dist > 0.01 then dir.Unit else Vector3.yAxis
		local ref = if math.abs(axis.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
		local r1 = axis:Cross(ref).Unit
		local r2 = r1:Cross(axis)
		local ang = p * math.pi * 2.5 * f.side
		pos += (r1 * math.cos(ang) + r2 * math.sin(ang)) * (0.7 * (1 - q) * math.min(dist / 5, 1))

		piece.Size = f.size * (1 - 0.9 * q)
		piece.CFrame = CFrame.new(pos) * f.rot * CFrame.Angles(f.sx * p, f.sy * p, f.sz * p)
	end
end

local function watchPiece(piece)
	if piece:GetAttribute("FlyTime") then
		startFly(piece)
	end
	piece:GetAttributeChangedSignal("FlyTime"):Connect(function()
		startFly(piece)
	end)
end

task.spawn(function()
	local folder = Workspace:WaitForChild("Pieces", 30)
	if not folder then
		return
	end
	for _, piece in folder:GetChildren() do
		watchPiece(piece)
	end
	folder.ChildAdded:Connect(watchPiece)
end)

local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function block(size, color, material, offset)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = viewFolder
	return { Part = p, Offset = offset }
end

local function clearItems(list)
	for _, item in list do
		item.Part:Destroy()
	end
	table.clear(list)
end

-- The glove, forearm and sleeve. The hand frame has its fingers along -Y and the arm along +Y.
local function buildArm(character)
	clearItems(armItems)
	armCharacter = character
	local skin = SKIN_FALLBACK
	local lower = character and character:FindFirstChild("RightLowerArm")
	if lower and lower:IsA("BasePart") then
		skin = lower.Color
	end
	local fabric = Enum.Material.Fabric
	table.insert(armItems, block(Vector3.new(0.46, 0.5, 0.4), GLOVE, fabric, CFrame.new(0, -0.05, 0)))
	table.insert(armItems, block(Vector3.new(0.5, 0.16, 0.44), GLOVE, fabric, CFrame.new(0, -0.34, 0)))
	table.insert(armItems, block(Vector3.new(0.16, 0.34, 0.2), GLOVE, fabric, CFrame.new(-0.28, -0.1, -0.12)))
	table.insert(armItems, block(Vector3.new(0.5, 0.2, 0.46), CUFF, fabric, CFrame.new(0, 0.28, 0)))
	table.insert(armItems, block(Vector3.new(0.34, 1.3, 0.34), skin, Enum.Material.SmoothPlastic, CFrame.new(0, 1.0, 0)))
	table.insert(armItems, block(Vector3.new(0.56, 0.8, 0.56), SLEEVE, fabric, CFrame.new(0, 1.9, 0)))
end

-- Copies the real tool's parts into the viewmodel, keeping their place relative to the Handle.
local function buildTool(tool, handle, toolRel, scale)
	clearItems(toolItems)
	local rel0 = CFrame.new(toolRel.Position * scale) * toolRel.Rotation
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local copy = d:Clone()
			for _, child in copy:GetChildren() do
				if not (child:IsA("SpecialMesh") or child:IsA("SurfaceAppearance") or child:IsA("Texture") or child:IsA("Decal")) then
					child:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanTouch = false
			copy.CanQuery = false
			copy.CastShadow = false
			copy.Massless = true
			copy.Size = d.Size * scale
			copy.Parent = viewFolder
			local rel = handle.CFrame:ToObjectSpace(d.CFrame)
			table.insert(toolItems, { Part = copy, Offset = rel0 * (CFrame.new(rel.Position * scale) * rel.Rotation) })
		end
	end
end

local function setRealToolHidden(tool, value)
	if not tool then
		return
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if value then 1 else 0
		end
	end
end

local function around(pitch, yaw, roll, move)
	return CFrame.new(PIVOT)
		* CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
		* CFrame.new(-PIVOT)
		* CFrame.new(move)
end

local function startSwing(duration)
	swingStart = os.clock()
	swingDur = duration
	swingImpacted = false
end

---------------------------------------------------------------------
-- Equip / unequip
---------------------------------------------------------------------
local function switchTool(tool)
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	if currentTool and hidden then
		setRealToolHidden(currentTool, false)
	end
	clearItems(toolItems)
	currentTool = tool
	toolReady = false
	holding = false
	holdAmt = 0
	swingStart = -10
	swingImpacted = true
	if not tool then
		poseName = nil
		return
	end
	poseName = tool:GetAttribute("ToolId") or tool:GetAttribute("GearId")
	local pose = POSES[poseName] or DEFAULT_POSE
	local function interval()
		return tool:GetAttribute("AttackInterval") or 0.4
	end
	table.insert(conns, tool.Activated:Connect(function()
		holding = true
		local now = os.clock()
		if pose.Style == "Swing" then
			if now - swingStart >= interval() * 0.9 then
				startSwing(math.clamp(interval() * 0.9, 0.12, 0.6))
			end
		elseif pose.Style == "Sweep" then
			if now - swingStart >= 0.3 then
				startSwing(0.3)
			end
		end
	end))
	table.insert(conns, tool.Deactivated:Connect(function()
		holding = false
	end))
	table.insert(conns, tool.Unequipped:Connect(function()
		holding = false
	end))
end

---------------------------------------------------------------------
-- Animation (returns a CFrame in camera space)
---------------------------------------------------------------------
local function animation(style, now)
	if style == "Swing" or style == "Sweep" then
		local p = (now - swingStart) / swingDur
		if p < 0 or p >= 1 then
			return CFrame.identity
		end
		if style == "Sweep" then
			local yaw = 22 - 44 * smooth(p)
			local pitch = -10 * math.sin(p * math.pi)
			return around(pitch, yaw, 0, Vector3.zero)
		end
		local amp = math.clamp(swingDur / 0.4, 0.45, 1)
		local pitch, thrust
		if p < 0.3 then
			local a = smooth(p / 0.3)
			pitch, thrust = 38 * a, -0.1 * a
		elseif p < 0.5 then
			local a = (p - 0.3) / 0.2
			a = a * a
			pitch, thrust = 38 - 82 * a, -0.1 + 0.55 * a
		else
			local a = smooth((p - 0.5) / 0.5)
			pitch, thrust = -44 * (1 - a), 0.45 * (1 - a)
		end
		return around(pitch * amp, 0, 0, Vector3.new(0, 0, -thrust * amp))
	elseif style == "Drill" then
		local k = holdAmt
		return CFrame.new(math.sin(now * 63) * 0.012 * k, math.sin(now * 57 + 1) * 0.012 * k, -0.2 * k)
			* CFrame.Angles(math.rad(math.sin(now * 47) * 0.8 * k), math.rad(math.sin(now * 51) * 0.8 * k), 0)
	elseif style == "Suck" then
		local k = holdAmt
		return CFrame.new(math.sin(now * 41) * 0.008 * k, 0, math.sin(now * 14) * 0.03 * k - 0.1 * k)
	end
	return CFrame.identity
end

---------------------------------------------------------------------
-- Every frame, after the camera has moved
---------------------------------------------------------------------
local function step(dt)
	local cam = Workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = character and character:FindFirstChildOfClass("Tool")
	updateFlyers(cam, os.clock())

	if tool ~= currentTool then
		switchTool(tool)
	end

	local active = cam ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and cam.CameraType == Enum.CameraType.Custom
		and tool ~= nil
	if not active then
		viewFolder.Parent = nil
		setSuck(nil)
		if hidden then
			setRealToolHidden(currentTool, false)
			hidden = false
		end
		return
	end

	if armCharacter ~= character then
		buildArm(character)
	end

	if not toolReady then
		local handle = tool:FindFirstChild("Handle")
		local rightHand = character:FindFirstChild("RightHand")
		if handle and handle:IsA("BasePart") and rightHand and rightHand:FindFirstChild("RightGrip") then
			local pose = POSES[poseName] or DEFAULT_POSE
			buildTool(tool, handle, rightHand.CFrame:ToObjectSpace(handle.CFrame), pose.Scale)
			toolReady = true
		end
	end

	setRealToolHidden(tool, true)
	hidden = true
	if viewFolder.Parent ~= cam then
		viewFolder.Parent = cam
	end

	local pose = POSES[poseName] or DEFAULT_POSE
	local style = pose.Style
	local now = os.clock()

	-- Held click on a swinging tool repeats the swing like ToolController does
	if holding and style == "Swing" and tool:GetAttribute("HoldEnabled") then
		local interval = tool:GetAttribute("AttackInterval") or 0.4
		if now - swingStart >= interval then
			startSwing(math.clamp(interval * 0.9, 0.12, 0.6))
		end
	end
	local target = if holding then 1 else 0
	holdAmt += (target - holdAmt) * math.clamp(dt * 10, 0, 1)

	-- Effects: they use the camera before the little kick below is applied
	if style == "Swing" then
		local p = (now - swingStart) / swingDur
		if p >= 0.5 and p < 1 and not swingImpacted then
			swingImpacted = true
			local point = aimPoint()
			if point and not pieceUnderAim() then
				impact(point, 1)
				kick = math.clamp(swingDur / 0.6, 0.35, 1) -- the fast Ice Pick dips less than the slow Pickaxe
				kickRoll = (math.random() - 0.5) * 2
			end
		end
	elseif style == "Drill" then
		if holding and now - drillTimer > 0.05 then
			drillTimer = now
			local point = aimPoint()
			if point and not pieceUnderAim() then
				impact(point, 0.4)
			end
		end
	elseif style == "Sweep" then
		local p = (now - swingStart) / swingDur
		if p >= 0.1 and p < 0.9 then
			local point = groundPoint(character, cam)
			if point then
				brushDust(point + cam.CFrame.RightVector * ((p - 0.5) * 7))
			end
		end
	end
	local suckPoint = nil
	if style == "Suck" and holdAmt > 0.5 then
		suckPoint = groundPoint(character, cam)
	end
	setSuck(suckPoint, tipCFrame(cam))
	if DEBUG_FX and now - lastDebug > 1 and (style == "Sweep" or style == "Suck") then
		lastDebug = now
		print("[ViewModel] FX debug", poseName, style, "holding", holding, "ground", suckPoint or groundPoint(character, cam))
	end

	-- Hit feedback moves ONLY the hand and tool, never the camera (so the aim stays put). Drill vibration too.
	kick = kick * math.exp(-dt * 16)
	local shake = kick * 1.0
	if style == "Drill" then
		shake += holdAmt * math.sin(now * 70) * 0.25
	end
	local handKick = CFrame.Angles(math.rad(-shake * HAND_KICK_DEG), 0, math.rad(kickRoll * kick * HAND_ROLL_DEG))

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	bobAmt += (math.clamp(speed / 16, 0, 1) - bobAmt) * math.clamp(dt * 8, 0, 1)
	local bob = CFrame.new(math.sin(now * 7) * 0.03 * bobAmt, -math.abs(math.sin(now * 7)) * 0.035 * bobAmt, 0)

	local rot = pose.Rot
	local hand = cam.CFrame * handKick
		* bob
		* animation(style, now)
		* CFrame.new(pose.Pos)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		* CFrame.Angles(math.rad(90), 0, 0)

	for _, item in armItems do
		item.Part.CFrame = hand * item.Offset
	end
	for _, item in toolItems do
		item.Part.CFrame = hand * item.Offset
	end
end

RunService:BindToRenderStep("ViewModel", Enum.RenderPriority.Camera.Value + 1, step)
print("[ViewModel] Init OK")

