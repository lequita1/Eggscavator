local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local MAX_FLYERS = 30
local STAGGER = 0.035
local FALLBACK_COLOR = Color3.fromRGB(235, 200, 110)

local SellResult = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellResult", 10)
if not SellResult then
	warn("[SellFly] SellResult remote not found")
	return
end

local folder = Instance.new("Folder")
folder.Name = "SellFly"
folder.Parent = Workspace

-- What each piece item looks like, taken from the egg layers
local looks = {}
pcall(function()
	local egg = require(ReplicatedStorage.Shared.EggDefinitions).Stonehatch
	local step = egg.LayerStep or 0.05
	for index, layer in ipairs(egg.Layers) do
		looks[layer.PieceItem] = { Color = layer.Color, Material = layer.Material, Scale = 1 - (index - 1) * step }
	end
end)

-- One real patch mesh to copy (the pieces on the ground are copies of patches too)
local template = nil
task.spawn(function()
	local root = ReplicatedStorage:WaitForChild("EggPatches", 15)
	local patches = root and root:WaitForChild("Stonehatch", 15)
	if not patches then
		return
	end
	for _, part in patches:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Index") == 120 then
			template = part
			return
		end
	end
	template = patches:FindFirstChildWhichIsA("BasePart")
end)

-- Sparkles where the plates land
local popPart = Instance.new("Part")
popPart.Size = Vector3.new(0.2, 0.2, 0.2)
popPart.Transparency = 1
popPart.Anchored = true
popPart.CanCollide = false
popPart.CanTouch = false
popPart.CanQuery = false
popPart.Parent = folder
local popAttachment = Instance.new("Attachment")
popAttachment.Parent = popPart
local pop = Instance.new("ParticleEmitter")
pop.Enabled = false
pop.Rate = 0
pop.Texture = "rbxasset://textures/particles/sparkles_main.dds"
pop.Color = ColorSequence.new(Color3.fromRGB(255, 225, 130))
pop.LightEmission = 1
pop.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
pop.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
pop.Lifetime = NumberRange.new(0.3, 0.6)
pop.Speed = NumberRange.new(6, 14)
pop.SpreadAngle = Vector2.new(180, 180)
pop.Acceleration = Vector3.new(0, -20, 0)
pop.Parent = popAttachment

local flyers = {}

local function findCounter()
	local map = Workspace:FindFirstChild("Map")
	local station = map and map:FindFirstChild("SellStation")
	local counter = station and station:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		return counter
	end
	return nil
end

local function makePart(itemId)
	local look = looks[itemId]
	local scale = if look then look.Scale else 1
	local part
	if template then
		part = template:Clone()
		part.Size = template.Size * 0.3 * scale
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(1.2, 0.3, 1.2) * scale
	end
	part.Color = if look then look.Color else FALLBACK_COLOR
	part.Material = if look then look.Material else Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Where a plate starts: low in front of the camera (first person), else the body
local function startPoint()
	local cam = Workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Custom then
		local offset = CFrame.new((math.random() - 0.5) * 1.4, -1.1 + (math.random() - 0.5) * 0.4, -1.6)
		return (cam.CFrame * offset).Position
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position + Vector3.new(0, 0.5, 0)
	end
	return nil
end

SellResult.OnClientEvent:Connect(function(summary)
	if typeof(summary) ~= "table" or typeof(summary.Lines) ~= "table" then
		return
	end
	local counter = findCounter()
	if not counter then
		return
	end

	local total = 0
	for _, line in summary.Lines do
		total += line.Count or 0
	end
	if total <= 0 then
		return
	end
	local scale = math.min(1, MAX_FLYERS / total)
	local queue = {}
	for _, line in summary.Lines do
		local n = math.max(1, math.floor((line.Count or 1) * scale + 0.5))
		for _ = 1, n do
			table.insert(queue, line.ItemId)
		end
	end
	for i = #queue, 2, -1 do
		local j = math.random(i)
		queue[i], queue[j] = queue[j], queue[i]
	end

	local top = counter.Position + Vector3.new(0, counter.Size.Y / 2 + 0.6, 0)
	local now = os.clock()
	for i, itemId in queue do
		local last = i == #queue
		table.insert(flyers, {
			Part = makePart(itemId),
			Start = now + (i - 1) * STAGGER,
			Duration = if last then 0.75 else 0.5 + math.random() * 0.2,
			To = top + Vector3.new((math.random() - 0.5) * 2.4, 0, (math.random() - 0.5) * 2.4),
			Spin = Vector3.new(math.random() * 10, math.random() * 10, math.random() * 6),
			Last = last,
		})
	end
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #flyers, 1, -1 do
		local f = flyers[i]
		local t = (now - f.Start) / f.Duration
		if t >= 0 then
			if not f.From then
				f.From = startPoint() or f.To
				local mid = f.From:Lerp(f.To, 0.5)
				f.Control = mid + Vector3.new((math.random() - 0.5) * 3, 4 + math.random() * 2, (math.random() - 0.5) * 3)
				f.BaseSize = f.Part.Size
				f.Part.Parent = folder
			end
			if t >= 1 then
				f.Part:Destroy()
				table.remove(flyers, i)
				popPart.Position = f.To
				pop:Emit(if f.Last then 18 else 3)
			else
				local e = t ^ 1.5
				local a = f.From:Lerp(f.Control, e)
				local b = f.Control:Lerp(f.To, e)
				f.Part.CFrame = CFrame.new(a:Lerp(b, e)) * CFrame.Angles(f.Spin.X * t, f.Spin.Y * t, f.Spin.Z * t)
				f.Part.Size = f.BaseSize * (1 - 0.5 * t)
			end
		end
	end
end)

print("[SellFly] Init OK")
