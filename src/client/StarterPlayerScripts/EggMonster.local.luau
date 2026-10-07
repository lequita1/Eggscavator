-- EggMonster v1: a scary horned shadow with red eyes inside the yolk. It grows and gets angrier as layers open.
-- Client only, decoration only. It never touches hits, money, the server or the egg's own parts.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- tune by eye ---------------------------------------------------------
local PROGRESS_BOOST = 1.5 -- 1 = scariness follows the true opened fraction; bigger = gets scary sooner
local MIN_SCALE = 0.7 -- monster size on an untouched egg (1 = fills the yolk)
local MAX_SCALE = 1.0
local SIZE = 1.7 -- overall size multiplier (the yolk is about 31 studs wide)
local BEAT_SLOW = 1.0 -- heartbeats per second at the start
local BEAT_FAST = 2.8 -- ... and when the egg is nearly open
local WIGGLE_MIN = 0.03 -- radians of wobble at the start
local WIGGLE_MAX = 0.2
local YOLK_TRANSPARENCY = 0.6 -- see-through yolk (0 = solid like before)
local YOLK_MATERIAL = Enum.Material.Neon
local YOLK_COLOR = Color3.fromRGB(255, 150, 45)
local YOLK_ANGRY = Color3.fromRGB(255, 70, 40)
local SHADOW_COLOR = Color3.fromRGB(30, 14, 10)
local EYE_DIM = Color3.fromRGB(210, 30, 25)
local EYE_HOT = Color3.fromRGB(255, 35, 25)
local OFFSET = 1.5 -- studs the monster leans toward you
local LAYER_COUNT = 6
----------------------------------------------------------------------

local attached = {}
local monsters = {}

local function beat(ph)
	return math.exp(-(((ph - 0.05) * 18) ^ 2)) + 0.7 * math.exp(-(((ph - 0.28) * 18) ^ 2))
end

local function newPart(parent, kind, size, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	if kind == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

-- the monster, built in its own frame: forward = -Z (toward you), up = +Y
local function buildBits(folder)
	local bits = {}
	local function body(kind, size, rel)
		table.insert(bits, {
			part = newPart(folder, kind, size, SHADOW_COLOR, Enum.Material.SmoothPlastic),
			size = size,
			rel = rel,
			eye = false,
		})
	end

	body("ball", Vector3.new(6, 5, 8), CFrame.new(0, 0, 0)) -- skull
	body("ball", Vector3.new(3.2, 3, 4.5), CFrame.new(0, -0.6, -4.4)) -- snout
	body("cyl", Vector3.new(0.8, 11, 11), CFrame.new(0, 1.6, 3.4) * CFrame.Angles(0, math.pi / 2, 0)) -- frill disc

	for i = 0, 8 do -- frill spikes
		local ang = math.rad(-100 + i * 25)
		local pos = Vector3.new(math.sin(ang) * 5.7, 1.6 + math.cos(ang) * 5.7, 3.4)
		body("block", Vector3.new(0.9, 2.6, 0.9), CFrame.new(pos) * CFrame.Angles(0, 0, -ang))
	end

	for _, side in { -1, 1 } do -- brow horns
		local base = CFrame.new(side * 2.3, 2.4, -3.0) * CFrame.Angles(math.rad(14), math.rad(90 - side * 8), 0)
		body("cyl", Vector3.new(5.5, 1.2, 1.2), base)
		body("cyl", Vector3.new(3.2, 0.65, 0.65), base * CFrame.new(4.2, 0, 0))
	end

	body("cyl", Vector3.new(2.8, 1.0, 1.0), CFrame.new(0, 1.2, -6.0) * CFrame.Angles(math.rad(40), math.rad(90), 0)) -- nose horn

	local lights = {}
	for _, side in { -1, 1 } do -- eyes
		local size = Vector3.new(2.2, 1.2, 1.0)
		local part = newPart(folder, "ball", size, EYE_DIM, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 40, 30)
		light.Range = 14
		light.Brightness = 1
		light.Shadows = false
		light.Parent = part
		table.insert(lights, light)
		table.insert(bits, { part = part, size = size, pos = Vector3.new(side * 1.9, 1.1, -2.75), side = side, eye = true })
	end
	return bits, lights
end

local function computeTarget(model)
	local s = model:GetAttribute("PatchLayer")
	if type(s) ~= "string" or #s == 0 then
		return 0
	end
	local sum = 0
	for i = 1, #s do
		local d = tonumber(string.sub(s, i, i)) or 1
		sum += math.clamp(d - 1, 0, LAYER_COUNT)
	end
	return math.clamp(sum / (#s * LAYER_COUNT) * PROGRESS_BOOST, 0, 1)
end

local function cleanup(m)
	if m.dead then
		return
	end
	m.dead = true
	pcall(function()
		if m.core and m.core.Parent then
			m.core.Transparency = m.coreOrig.Transparency
		end
	end)
	for _, c in m.conns do
		c:Disconnect()
	end
	pcall(function()
		m.folder:Destroy()
	end)
	pcall(function()
		if m.yolk.Parent then
			m.yolk.Transparency = m.orig.Transparency
			m.yolk.Color = m.orig.Color
			m.yolk.Material = m.orig.Material
			if m.glow then
				m.glow.Color = m.orig.GlowColor
				m.glow.Brightness = m.orig.GlowBrightness
			end
		end
	end)
end

local function update(m, dt, t, camPos)
	local yolk = m.yolk
	if not yolk.Parent or not m.folder.Parent then
		return false
	end

	m.p += (m.target - m.p) * (1 - math.exp(-dt * 1.5))
	if m.core and m.core.Parent and not m.dying and m.core.Transparency < 1 then
		m.core.Transparency = 1
	end
	local p = m.p
	local k = MIN_SCALE + (MAX_SCALE - MIN_SCALE) * p

	local fade = 1
	if m.dying then
		fade = 1 - math.clamp((t - m.dying) / 0.35, 0, 1)
		if fade <= 0 then
			return false
		end
	end

	-- face the player (eyes follow you, a little late)
	local centre = yolk.Position
	local dir = camPos - centre
	local h = Vector3.new(dir.X, 0, dir.Z)
	local hm = h.Magnitude
	if hm < 0.5 then
		h = Vector3.new(0, 0, 1)
		hm = 1
	end
	local aim = Vector3.new(h.X, math.clamp(dir.Y, -hm * 0.8, hm * 1.6), h.Z)
	local target = CFrame.lookAt(Vector3.zero, aim)
	m.face = m.face:Lerp(target, 1 - math.exp(-dt * 2.5))

	-- heartbeat and wiggle
	local freq = BEAT_SLOW + (BEAT_FAST - BEAT_SLOW) * p
	local pulse = beat((t * freq) % 1)
	local amp = (WIGGLE_MIN + (WIGGLE_MAX - WIGGLE_MIN) * p) * (1 + 0.6 * pulse)
	local wob = CFrame.Angles(amp * math.sin(t * 6.7), amp * 0.6 * math.sin(t * 8.9 + 2), amp * math.sin(t * 5.3 + 1))
	local frame = CFrame.new(centre + aim.Unit * (OFFSET * k)) * m.face * wob
	local s = k * SIZE * (1 + 0.06 * pulse * (0.4 + p)) * fade

	-- blink now and then
	local blinking = t < m.blinkEnd
	if not blinking and t >= m.blinkAt then
		m.blinkEnd = t + 0.16
		m.blinkAt = t + 3 + math.random() * 4
		blinking = true
	end
	local grow = 0.85 + 0.6 * p
	local eyeMul = Vector3.new(grow * (1 + 0.2 * pulse), grow * (if blinking then 0.12 else 1), grow)
	local slant = math.rad(5 + 23 * p)
	local bodyT = 0.2 - 0.2 * p
	local eyeColor = EYE_DIM:Lerp(EYE_HOT, p)

	for _, bit in m.bits do
		local part = bit.part
		if bit.eye then
			part.CFrame = frame * (CFrame.new(bit.pos * s) * CFrame.Angles(0, 0, bit.side * slant))
			part.Size = bit.size * s * eyeMul
			part.Color = eyeColor
		else
			part.CFrame = frame * (CFrame.new(bit.rel.Position * s) * (bit.rel - bit.rel.Position))
			part.Size = bit.size * s
			part.Transparency = bodyT
		end
	end
	for _, light in m.lights do
		light.Brightness = (0.8 + 2.2 * p) * (0.7 + 0.5 * pulse)
	end

	-- the yolk glow turns from warm orange to angry red
	yolk.Color = YOLK_COLOR:Lerp(YOLK_ANGRY, p * 0.8)
	if m.glow then
		m.glow.Color = Color3.fromRGB(255, 170, 70):Lerp(Color3.fromRGB(255, 60, 40), p)
		m.glow.Brightness = (0.9 + 1.4 * p) * (0.8 + 0.5 * pulse)
	end
	return true
end

local function attach(eggFolder)
	if attached[eggFolder] then
		return
	end
	attached[eggFolder] = true
	local yolk = eggFolder:WaitForChild("Yolk", 20)
	local eggs = Workspace:WaitForChild("Eggs", 20)
	local model = eggs and eggs:WaitForChild(eggFolder.Name, 20)
	if not (yolk and yolk:IsA("BasePart") and model) then
		warn("[EggMonster] could not find the yolk or the egg model for " .. eggFolder.Name)
		return
	end
	if model:GetAttribute("Broken") then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "EggMonster_" .. eggFolder.Name
	folder.Parent = Workspace

	local bits, lights = buildBits(folder)
	local glow = yolk:FindFirstChildOfClass("PointLight")
	local m = {
		folder = folder,
		yolk = yolk,
		model = model,
		bits = bits,
		lights = lights,
		glow = glow,
		face = CFrame.identity,
		p = computeTarget(model),
		target = computeTarget(model),
		blinkAt = os.clock() + 3,
		blinkEnd = 0,
		conns = {},
		orig = {
			Transparency = yolk.Transparency,
			Color = yolk.Color,
			Material = yolk.Material,
			GlowColor = if glow then glow.Color else Color3.new(1, 1, 1),
			GlowBrightness = if glow then glow.Brightness else 0,
		},
	}
	yolk.Transparency = YOLK_TRANSPARENCY
	local core = model:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		m.core = core
		m.coreOrig = { Transparency = core.Transparency }
		core.Transparency = 1
	end
	yolk.Material = YOLK_MATERIAL
	yolk.Color = YOLK_COLOR

	table.insert(m.conns, model:GetAttributeChangedSignal("PatchLayer"):Connect(function()
		m.target = computeTarget(model)
	end))
	table.insert(m.conns, model:GetAttributeChangedSignal("Broken"):Connect(function()
		if model:GetAttribute("Broken") and not m.dying then
			m.dying = os.clock()
		end
	end))
	table.insert(monsters, m)
	print("[EggMonster] attached to " .. eggFolder.Name)
end

RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local t = os.clock()
	for i = #monsters, 1, -1 do
		local m = monsters[i]
		local ok, alive = pcall(update, m, dt, t, cam.CFrame.Position)
		if not ok then
			warn("[EggMonster] step failed, removing the monster: " .. tostring(alive))
			alive = false
		end
		if not alive then
			cleanup(m)
			table.remove(monsters, i)
		end
	end
end)

task.spawn(function()
	local root = Workspace:WaitForChild("EggView", 60)
	if not root then
		warn("[EggMonster] Workspace.EggView never appeared")
		return
	end
	for _, c in root:GetChildren() do
		if c:IsA("Folder") then
			task.spawn(attach, c)
		end
	end
	root.ChildAdded:Connect(function(c)
		if c:IsA("Folder") then
			task.spawn(attach, c)
		end
	end)
end)

print("[EggMonster] Init OK (v2)")
-- END OF EGGMONSTER
