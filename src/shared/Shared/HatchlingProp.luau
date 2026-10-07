-- HatchlingProp (shared): builds the hatchling used by carrying, the field and the Release scene.
-- If ReplicatedStorage.DinoRig exists (the rigged triceratops), the hatchling is a small copy of it and its bones are
-- animated on every client by the DinoLife script. If it does not exist, the old rigid HatchStage.Hatchling is used.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HatchlingProp = {}

local FACE_FIX = math.pi / 2 -- OLD rigid model only
HatchlingProp.FACE_FIX = FACE_FIX
local RIG_HOLD_YAW = math.pi / 2 -- RIGGED hatchling: which way its head points while carried / on the field (try 0, math.pi, -math.pi / 2)
local HOLD = CFrame.new(0, -0.3, -2.2) -- where it sits in front of the player's chest
local ARM_ANGLE = math.rad(78) -- how far the arms are raised forward
local EMBER = Color3.fromRGB(255, 120, 60)

local function rigTemplate()
	local template = ReplicatedStorage:FindFirstChild("DinoRig")
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- The yaw the Release scene must add so the model faces its front (0 for the rigged hatchling, whose front is the rig's +Z)
function HatchlingProp.GetFaceFix()
	if rigTemplate() then
		return 0
	end
	return FACE_FIX
end

local function holdYaw()
	if rigTemplate() then
		return RIG_HOLD_YAW
	end
	return FACE_FIX
end

local function extents(part)
	local cf, s = part.CFrame, part.Size
	return Vector3.new(
		math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
		math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
		math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
	)
end

local function bounds(model)
	local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local e, p = extents(d), d.Position
			minX = math.min(minX, p.X - e.X / 2)
			maxX = math.max(maxX, p.X + e.X / 2)
			minY = math.min(minY, p.Y - e.Y / 2)
			maxY = math.max(maxY, p.Y + e.Y / 2)
			minZ = math.min(minZ, p.Z - e.Z / 2)
			maxZ = math.max(maxZ, p.Z + e.Z / 2)
		end
	end
	return minX, maxX, minY, maxY, minZ, maxZ
end

function HatchlingProp.GetTemplate()
	local rig = rigTemplate()
	if rig then
		return rig
	end
	local stage = Workspace:FindFirstChild("HatchStage")
	return (stage and stage:FindFirstChild("Hatchling", true)) or Workspace:FindFirstChild("Hatchling")
end

-- The old rigid hatchling (used only when there is no DinoRig)
local function makeRigid(height, name)
	local template = HatchlingProp.GetTemplate()
	if not template then
		return nil, nil
	end
	local model = template:Clone()
	if not model then
		return nil, nil
	end
	if model:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		model.Parent = wrapper
		model = wrapper
	end
	model.Name = name

	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("WeldConstraint")
			or d:IsA("Humanoid") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	model.Parent = Workspace

	local _, _, minY, maxY = bounds(model)
	if minY == math.huge then
		model:Destroy()
		return nil, nil
	end
	pcall(function()
		model:ScaleTo(model:GetScale() * height / math.max(maxY - minY, 0.05))
	end)

	local minX, maxX, minY2, _, minZ, maxZ = bounds(model)
	local rig = Instance.new("Part")
	rig.Name = "Rig"
	rig.Size = Vector3.new(0.5, 0.5, 0.5)
	rig.Transparency = 1
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.Massless = true
	rig.CFrame = CFrame.new((minX + maxX) / 2, minY2, (minZ + maxZ) / 2)
	rig.Parent = model
	model.PrimaryPart = rig

	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= rig then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rig
			weld.Part1 = p
			weld.Parent = p
		end
	end
	return model, rig
end

-- The rigged hatchling: a scaled copy of DinoRig. Its bones are animated by DinoLife (tag "DinoAnim").
local function makeRigged(template, height, name)
	local model = template:Clone()
	if not model then
		return nil, nil
	end
	model.Name = name
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local mesh = model.PrimaryPart
	if not mesh or not mesh:IsA("BasePart") then
		mesh = model:FindFirstChildWhichIsA("MeshPart")
	end
	if not mesh then
		model:Destroy()
		return nil, nil
	end
	model.Parent = Workspace
	pcall(function()
		model:ScaleTo(model:GetScale() * height / math.max(mesh.Size.Y, 0.05))
	end)

	-- An invisible part at its FEET. Its +Z is the front of the dinosaur (the mesh's front is -Z, so it is turned round).
	local rotation = mesh.CFrame - mesh.Position
	local feet = mesh.Position - mesh.CFrame.UpVector * (mesh.Size.Y / 2)
	local rig = Instance.new("Part")
	rig.Name = "Rig"
	rig.Size = Vector3.new(0.5, 0.5, 0.5)
	rig.Transparency = 1
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.Massless = true
	rig.CFrame = CFrame.new(feet) * rotation * CFrame.Angles(0, math.pi, 0)
	rig.Parent = model
	model.PrimaryPart = rig

	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= rig then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rig
			weld.Part1 = p
			weld.Parent = p
		end
	end

	model:SetAttribute("DinoProfile", "Hatchling")
	model:SetAttribute("DinoMode", "Idle")
	CollectionService:AddTag(model, "DinoAnim")
	return model, rig
end

-- Returns (model, rig). The rig is an invisible part at the hatchling's FEET; the front of the model is the rig's +Z.
-- Parts are left anchored: the caller decides what to do next.
function HatchlingProp.Make(height, name)
	local template = rigTemplate()
	if template then
		return makeRigged(template, height, name)
	end
	return makeRigid(height, name)
end

local function addGlow(rig, height)
	local light = Instance.new("PointLight")
	light.Color = EMBER
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = rig

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, height * 0.55, 0)
	attachment.Parent = rig
	local embers = Instance.new("ParticleEmitter")
	embers.Rate = 10
	embers.Color = ColorSequence.new(EMBER)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	embers.Lifetime = NumberRange.new(0.8, 1.4)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, 5, 0)
	embers.LightEmission = 1
	embers.Parent = attachment
	return light
end

---------------------------------------------------------------------
-- Carrying: held out in both arms, thrashing and lunging
---------------------------------------------------------------------
local function findShoulders(character)
	local list = {}
	for _, m in character:GetDescendants() do
		if m:IsA("Motor6D") then
			local n = string.gsub(m.Name, "%s", "")
			if n == "RightShoulder" or n == "LeftShoulder" then
				table.insert(list, { Motor = m, C0 = m.C0 })
			end
		end
	end
	return list
end

local function poseArms(list, angle)
	for _, e in list do
		if e.Motor.Parent then
			local p = e.C0.Position
			e.Motor.C0 = CFrame.new(p) * CFrame.Angles(angle, 0, 0) * CFrame.new(-p) * e.C0
		end
	end
end

local function restoreArms(list)
	for _, e in list do
		if e.Motor.Parent then
			e.Motor.C0 = e.C0
		end
	end
end

function HatchlingProp.AttachToCarrier(character, height)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local model, rig = HatchlingProp.Make(height, "CarriedCore")
	if not model or not rig then
		return nil
	end
	model:SetAttribute("DinoMode", "Carried")

	local facing = CFrame.Angles(0, math.pi + holdYaw(), 0)
	model:PivotTo(root.CFrame * HOLD * facing)

	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = rig
	weld.C0 = HOLD * facing
	weld.C1 = CFrame.new()
	weld.Parent = rig

	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	local light = addGlow(rig, height)
	model.Parent = character

	local arms = findShoulders(character)
	local t0, seed = os.clock(), math.random() * 100
	local connection
	connection = RunService.Heartbeat:Connect(function()
		-- Stops when the hatchling is dropped, delivered or renamed (the Release scene renames it)
		if not model.Parent or model.Name ~= "CarriedCore" or not weld.Parent or not root.Parent then
			connection:Disconnect()
			pcall(restoreArms, arms)
			return
		end
		local t = os.clock() - t0
		local fit = math.max(0, math.sin(t * 1.7 + seed)) ^ 3 -- now and then it goes wild
		local amp = 1 + 2.2 * fit
		local snap = math.max(0, math.sin(t * 3.3)) ^ 8 -- the head snaps forward
		local bob = math.sin(t * 11) * 0.1 * amp
		local roll = math.sin(t * 13) * 0.16 * amp
		local yaw = math.sin(t * 8.5 + 1) * 0.35 * amp
		local pitch = 0.35 * snap + math.sin(t * 10) * 0.05 * amp
		weld.C0 = HOLD * CFrame.new(0, bob, -snap * 0.25) * facing * CFrame.Angles(pitch, yaw, roll)
		light.Brightness = 1.5 + 1.8 * snap + 0.8 * fit
		pcall(poseArms, arms, ARM_ANGLE + math.sin(t * 13) * 0.05 * amp)
	end)
	return model
end

---------------------------------------------------------------------
-- The field core: the orb becomes a trembling hatchling
---------------------------------------------------------------------
function HatchlingProp.DressFieldCore(core, height)
	if not core or not core:IsA("BasePart") or not core.Parent then
		return false
	end
	local model, rig = HatchlingProp.Make(height, "CoreHatchling")
	if not model or not rig then
		return false
	end
	model:SetAttribute("DinoMode", "Field")

	local base = CFrame.new(0, -core.Size.Y / 2, 0)
	local facing = CFrame.Angles(0, math.pi + holdYaw(), 0)
	model:PivotTo(core.CFrame * base * facing)

	local weld = Instance.new("Weld")
	weld.Part0 = core
	weld.Part1 = rig
	weld.C0 = base * facing
	weld.C1 = CFrame.new()
	weld.Parent = rig
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	addGlow(rig, height)
	model.Parent = core.Parent
	core.Transparency = 1 -- the old yellow sphere disappears (its light and prompt stay)
	core.Destroying:Connect(function()
		model:Destroy()
	end)

	local t0 = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not weld.Parent or not core.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - t0
		local hop = math.max(0, math.sin(t * 2.1)) ^ 4 * height * 0.12
		local look = math.sin(t * 0.8) * 0.9
		local snap = math.max(0, math.sin(t * 1.3 + 1)) ^ 10
		weld.C0 = base * CFrame.new(0, hop, 0) * facing
			* CFrame.Angles(0.25 * snap, look, math.sin(t * 22) * 0.03 + math.sin(t * 5) * 0.04)
	end)
	return true
end

return HatchlingProp
