-- DinoAnimator (shared): bone animation for the rigged triceratops. Used for Mother and the hatchling.
-- Every rotation is described in MESH space (front = -Z, right = +X, up = +Y) and converted into each bone's own
-- rest frame, so it does not matter which way the bones were exported. Positive pitch = nose up, positive
-- LookYaw = look to the mesh's right. A leg angle > 0 swings the foot forward.
local DinoAnimator = {}
DinoAnimator.__index = DinoAnimator

-- Bone numbers (the digits at the end of the bone names)
local GROUP_BONES = {
	FrontRightLeg = { 29, 28, 27, 26, 25 },
	FrontLeftLeg = { 34, 33, 32, 31, 30 },
	HindRightLeg = { 17, 16, 15, 14, 13 },
	HindLeftLeg = { 22, 21, 20, 19, 18 },
	Tail = { 8, 7, 6, 5, 4 },
	Spine = { 3, 12, 11, 10, 9 },
	Head = { 24, 23 },
	Horns = { 36, 35, 38, 37 },
	Nose = { 40, 39 },
	Body = { 0, 1, 2 },
}
DinoAnimator.GroupNames = {
	"FrontRightLeg", "FrontLeftLeg", "HindRightLeg", "HindLeftLeg",
	"Tail", "Head", "Horns", "Nose", "Spine", "Body",
}

-- Tuning. Swing/Flex are radians. Stride = body lengths per full step cycle.
local PROFILES = {
	Mother = { Stride = 0.95, MaxCadence = 1.3, Swing = 0.42, Flex = 0.55, TailAmp = 0.22, TailFreq = 0.7, Rate = 7 },
	Hatchling = { Stride = 0.6, MaxCadence = 4.5, Swing = 0.7, Flex = 0.8, TailAmp = 0.45, TailFreq = 1.6, Rate = 12 },
}

-- Leg order of steps: front left, hind left, front right, hind right (matches the footfall dust in ReleaseCutscene)
local LEG_OFFSET = { FrontLeftLeg = 0, HindLeftLeg = 0.25, FrontRightLeg = 0.5, HindRightLeg = 0.75 }
-- How much of each angle goes to bone 1 (hip), 2, 3, 4, 5 (foot) of a leg chain
local SWING_W = { 1, 0.2, -0.3, 0, 0 }
local LIFT_W = { 0, -0.6, 0.9, -0.3, 0 }
local TUCK_W = { 0.5, -0.9, 0.7, 0, 0 }

local function smooth(current, target, dt, rate)
	return current + (target - current) * (1 - math.exp(-dt * rate))
end

local function boneNumber(bone)
	return tonumber(string.match(bone.Name, "(%d+)$"))
end

local function boneDepth(bone)
	local n, p = 0, bone.Parent
	while p and p:IsA("Bone") do
		n += 1
		p = p.Parent
	end
	return n
end

function DinoAnimator.new(model, profileName)
	local mesh = model:FindFirstChildWhichIsA("MeshPart") or model:FindFirstChildWhichIsA("MeshPart", true)
	assert(mesh, "DinoAnimator: no MeshPart in " .. model.Name)

	local meshRot = mesh.CFrame - mesh.CFrame.Position
	local byNumber, all = {}, {}
	for _, d in mesh:GetDescendants() do
		if d:IsA("Bone") then
			d.Transform = CFrame.new()
			local number = boneNumber(d)
			local world = d.WorldCFrame
			local q = meshRot:Inverse() * (world - world.Position)
			local entry = { Bone = d, Number = number, Depth = boneDepth(d), Q = q, Qi = q:Inverse(), X = 0, Y = 0, Z = 0 }
			table.insert(all, entry)
			if number then
				byNumber[number] = entry
			end
		end
	end
	assert(#all > 0, "DinoAnimator: " .. model.Name .. " has no Bones")

	local groups = {}
	for name, numbers in GROUP_BONES do
		local list = {}
		for _, n in numbers do
			if byNumber[n] then
				table.insert(list, byNumber[n])
			end
		end
		-- root of the chain first: fewer bone ancestors first, then the higher number first
		table.sort(list, function(a, b)
			if a.Depth ~= b.Depth then
				return a.Depth < b.Depth
			end
			return a.Number > b.Number
		end)
		groups[name] = list
	end

	local size = mesh.Size
	return setmetatable({
		Model = model,
		Mesh = mesh,
		All = all,
		Groups = groups,
		Profile = PROFILES[profileName] or PROFILES.Hatchling,
		Length = math.max(size.X, size.Z),
		Phase = 0,
		Gait = 0,
		Debug = nil,
		_t = 0,
		_tailT = 0,
		_yaw = 0,
		_pitch = 0,
		_roar = 0,
		_tuck = 0,
		_excite = 0,
	}, DinoAnimator)
end

function DinoAnimator:SetProfile(name)
	self.Profile = PROFILES[name] or self.Profile
end

function DinoAnimator:Reset()
	for _, e in self.All do
		if e.Bone.Parent then
			e.Bone.Transform = CFrame.new()
		end
		e.X, e.Y, e.Z = 0, 0, 0
	end
	self.Gait, self.Phase = 0, 0
	self._yaw, self._pitch, self._roar, self._tuck, self._excite = 0, 0, 0, 0, 0
end

function DinoAnimator:_pose(dt, p, L)
	local prof = self.Profile
	local rate = prof.Rate
	local groups = self.Groups
	self._t += dt
	local t = self._t

	local speed = p.Speed or 0
	self.Gait = smooth(self.Gait, math.clamp(speed / (L * 0.12), 0, 1), dt, 8)
	local gait = self.Gait
	local cadence = math.min(speed / (L * prof.Stride), prof.MaxCadence)
	self.Phase = (self.Phase + dt * cadence) % 1

	self._yaw = smooth(self._yaw, math.clamp(p.LookYaw or 0, -1.2, 1.2), dt, rate)
	self._pitch = smooth(self._pitch, p.LookPitch or 0, dt, rate)
	self._roar = smooth(self._roar, p.Roar or 0, dt, 14)
	self._tuck = smooth(self._tuck, p.Tuck or 0, dt, 16)
	self._excite = smooth(self._excite, p.Excite or 0, dt, 5)
	local yaw, pitch, roar, tuck, excite = self._yaw, self._pitch, self._roar, self._tuck, self._excite
	local cycle = self.Phase * math.pi * 2

	-- Legs
	for name, offset in LEG_OFFSET do
		local a = cycle + offset * math.pi * 2
		local swing = math.sin(a) * prof.Swing * gait
		local lift = math.max(0, math.cos(a)) * gait * prof.Flex
		for i, e in groups[name] do
			e.X += swing * (SWING_W[i] or 0) + lift * (LIFT_W[i] or 0) + tuck * (TUCK_W[i] or 0)
		end
	end

	-- Tail: a wave that gets bigger and faster when excited
	self._tailT += dt * prof.TailFreq * (1 + excite * 1.5) * math.pi * 2
	local tail = groups.Tail
	local tailAmp = prof.TailAmp * (0.35 + 0.65 * excite + 0.4 * gait)
	for i, e in tail do
		e.Y += tailAmp * math.sin(self._tailT - i * 0.8) / math.max(#tail * 0.5, 1)
			+ 0.05 * gait * math.sin(cycle)
	end

	-- Head and neck
	local head = groups.Head
	local up = pitch + roar * 0.6 + math.sin(cycle * 2) * 0.04 * gait
	for _, e in head do
		e.Y -= yaw / #head -- positive yaw = look right; a positive Y rotation turns left
		e.X += up / #head
	end

	-- Spine: breathing, rearing for the roar, a sway when walking
	for _, e in groups.Spine do
		e.X += math.sin(t * 1.6) * 0.015 + roar * 0.1
		e.Y += math.sin(cycle) * 0.04 * gait
	end
	for _, e in groups.Body do
		e.Z += math.sin(cycle) * 0.025 * gait
	end

	-- Horns and nose follow the roar
	for _, e in groups.Horns do
		e.Z += math.sin(t * 35) * 0.04 * roar
	end
	for _, e in groups.Nose do
		e.X += roar * 0.25
	end
end

function DinoAnimator:Step(dt, p)
	p = p or {}
	local size = self.Mesh.Size
	local L = math.max(size.X, size.Z)
	self.Length = L

	for _, e in self.All do
		e.X, e.Y, e.Z = 0, 0, 0
	end

	if self.Debug then
		-- Bone test: only the chosen group moves. Legs and spine swing on X, everything else turns on Y.
		local list = self.Groups[self.Debug.Group]
		local onX = string.find(self.Debug.Group, "Leg") or self.Debug.Group == "Spine"
		for _, e in list or {} do
			if onX then
				e.X = self.Debug.Angle
			else
				e.Y = self.Debug.Angle
			end
		end
	else
		self:_pose(dt, p, L)
	end

	for _, e in self.All do
		if e.Bone.Parent then
			e.Bone.Transform = e.Qi * CFrame.Angles(e.X, e.Y, e.Z) * e.Q
		end
	end
end

return DinoAnimator
