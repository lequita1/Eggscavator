-- ReleaseCutscene v3 (client): Mother walks in, roars, the hatchling runs to her, they leave together.
-- Both are moved LOCALLY every frame and their bones are animated by DinoAnimator, so it is smooth and nothing is
-- replicated. It also works with the old rigid models (no bones = no bone animation).
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DinoAnimator = require(Shared:WaitForChild("DinoAnimator"))
local HatchlingProp = require(Shared:WaitForChild("HatchlingProp"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CFG = {
	Total = 21.2, -- keep Mother.ReleaseCutsceneTime in GameConfig at least 1.5 higher
	BarHeight = 0.1,
	MotherFaceFix = 0, -- set to math.pi if Mother walks BACKWARDS
	HatchFaceFix = 0, -- only used if HatchlingProp has no GetFaceFix
	Bank = 0.05, -- how much it leans into turns (negative = lean the other way)
	FaceArrow = false, -- true = show a green arrow showing where the CODE thinks "forward" is (for the facing test)
	FollowGround = true, -- Mother follows the terrain. Set false if she floats or sinks.
	WalkStart = 0.5,
	ArriveAt = 9.0,
	RoarAt = 9.8,
	RunAt = 11.6, -- the hatchling is set free
	RunTime = 2.4,
	GreetAt = 14.0,
	TurnAt = 15.2,
	TurnTime = 2.0,
	LeaveAt = 17.2,
	BlackAt = 20.4,
}

local SUBS = {
	{ 0.8, 4.2, "The ground is trembling..." },
	{ 12.0, 15.0, "Mother found her hatchling." },
	{ 17.4, 20.0, "Free at last." },
}

local DUST = Color3.fromRGB(190, 175, 150)
local COOL = Color3.fromRGB(205, 215, 235)
local WARM = Color3.fromRGB(255, 236, 205)

local function ease(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function noise(x, y)
	return math.noise(x, y, 0.5) * 2
end
local function yawOf(v)
	return math.atan2(v.X, v.Z)
end
local function angleDiff(a, b) -- the shortest signed turn from a to b
	return (b - a + math.pi) % (math.pi * 2) - math.pi
end

local function extents(part)
	local cf, s = part.CFrame, part.Size
	return Vector3.new(
		math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
		math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
		math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
	)
end

local function lowestPoint(model)
	local low = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			low = math.min(low, d.Position.Y - extents(d).Y / 2)
		end
	end
	return low
end

local function tweenBars(top, bottom, height, duration)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(top, info, { Size = UDim2.fromScale(1, height) }):Play()
	TweenService:Create(bottom, info, { Size = UDim2.fromScale(1, height) }):Play()
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ReleaseCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 95

	local function frame(z, color, trans)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BackgroundTransparency = trans
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Parent = gui
		return f
	end
	local top = frame(5, Color3.new(0, 0, 0), 0)
	top.Size = UDim2.fromScale(1, 0)
	local bottom = frame(5, Color3.new(0, 0, 0), 0)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.fromScale(1, 0)
	local black = frame(20, Color3.new(0, 0, 0), 0)
	black.Size = UDim2.fromScale(1, 1)

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.84)
	subtitle.Size = UDim2.fromScale(0.8, 0.06)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = ""
	subtitle.TextColor3 = Color3.fromRGB(255, 240, 215)
	subtitle.TextScaled = true
	subtitle.TextTransparency = 1
	subtitle.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
	subtitle.TextStrokeTransparency = 1
	subtitle.ZIndex = 6
	subtitle.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = subtitle

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
	return gui, black, top, bottom, subtitle, skip
end

local running = false

local function run()
	if running then
		return
	end
	running = true

	local padPos = Workspace:GetAttribute("ReleasePadPosition")
	local home = Workspace:GetAttribute("MotherHome")
	local mother = Workspace:FindFirstChild("Dino")
	local runner = Workspace:WaitForChild("ReleaseHatchling", 3)

	local gui, black, top, bottom, subtitle, skipButton = buildGui()
	gui.Parent = playerGui
	tweenBars(top, bottom, CFG.BarHeight, 0.5)

	local hiddenGuis = {}
	for _, other in playerGui:GetChildren() do
		if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
			other.Enabled = false
			table.insert(hiddenGuis, other)
		end
	end

	local skipped = false
	skipButton.Activated:Connect(function()
		skipped = true
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space then
			skipped = true
		end
	end)

	local camera = Workspace.CurrentCamera
	local savedFov = camera.FieldOfView
	local savedExposure = Lighting.ExposureCompensation
	local fx, bloom, grade = nil, nil, nil
	local mAnim, hAnim = nil, nil
	local blackDone = false

	local ok, err = pcall(function()
		assert(mother and mother.PrimaryPart, "Workspace.Dino (Mother) not found")
		assert(typeof(padPos) == "Vector3" and typeof(home) == "CFrame", "pad or Mother data missing")

		fx = Instance.new("Folder")
		fx.Name = "ReleaseFX"
		fx.Parent = Workspace

		-- Bone animation (nil if the model has no bones: the old rigid models still work)
		mother:SetAttribute("Manual", true) -- tells DinoLife to leave these two alone
		Workspace:SetAttribute("MotherShow", true) -- MotherHider reveals her for the scene
		local okM, animM = pcall(DinoAnimator.new, mother, "Mother")
		if okM then
			mAnim = animM
		end
		if runner then
			runner:SetAttribute("Manual", true)
			local okH, animH = pcall(DinoAnimator.new, runner, "Hatchling")
			if okH then
				hAnim = animH
			end
		end

		local size = mother:GetExtentsSize()
		local L = math.max(size.X, size.Z) -- Mother's length
		local Hm = size.Y -- Mother's height
		local sc = math.clamp(L / 40, 0.6, 3)
		local mFeet = lowestPoint(mother)
		local pivotAbove = home.Position.Y - mFeet

		local hh, hFoot = 8, 0
		if runner then
			hh = runner:GetExtentsSize().Y
			hFoot = runner:GetPivot().Position.Y - lowestPoint(runner)
		end

		-- Ground height under a point. Looks through trees and rocks, lands on terrain or flat floors.
		local ignore = { mother, fx }
		if runner then
			table.insert(ignore, runner)
		end
		for _, plr in Players:GetPlayers() do
			if plr.Character then
				table.insert(ignore, plr.Character)
			end
		end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = ignore
		local function g(pos, fallback)
			if not CFG.FollowGround then
				return fallback
			end
			local origin = Vector3.new(pos.X, fallback + 250, pos.Z)
			for _ = 1, 8 do
				local hit = Workspace:Raycast(origin, Vector3.new(0, -700, 0), rayParams)
				if not hit then
					return fallback
				end
				local inst = hit.Instance
				if inst:IsA("Terrain") or inst.Size.Y <= 6 or (inst.Size.X >= 100 and inst.Size.Z >= 100) then
					return hit.Position.Y
				end
				table.insert(ignore, inst) -- a tree, rock or building: look through it
				rayParams.FilterDescendantsInstances = ignore
			end
			return fallback
		end
		local function onGround(pos, height, fallback)
			return Vector3.new(pos.X, g(pos, fallback) + height, pos.Z)
		end

		-- Geometry: Mother comes from her home side toward the pad
		local P = padPos
		local toMother = flat(home.Position - P)
		if toMother.Magnitude < 1 then
			toMother = -flat(home.LookVector)
		end
		local d = toMother.Unit -- from the pad toward Mother
		local u = -d -- from Mother toward the pad (the way she walks)
		local side = Vector3.new(-d.Z, 0, d.X)
		local up = Vector3.yAxis
		local stopDist = L * 1.1 + 18
		local approach = math.max(120, L * 2.4)
		local T = P + d * stopDist -- where she stops
		local S = P + d * (stopDist + approach) -- where she appears
		local leaveAcc = L * 0.14

		-- Lighting mood, on this player's screen only
		bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.5
		bloom.Size = 28
		bloom.Threshold = 0.95
		bloom.Parent = Lighting
		grade = Instance.new("ColorCorrectionEffect")
		grade.Contrast = 0.12
		grade.Saturation = 0.05
		grade.TintColor = COOL
		grade.Parent = Lighting

		-- Effects
		local function puff(position, psize, count)
			local holder = Instance.new("Part")
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Transparency = 1
			holder.Size = Vector3.one
			holder.Position = position
			holder.Parent = fx
			local e = Instance.new("ParticleEmitter")
			e.Enabled = false
			e.Rate = 0
			e.Color = ColorSequence.new(DUST)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, psize), NumberSequenceKeypoint.new(1, psize * 3.5) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(1.2, 2.2)
			e.Speed = NumberRange.new(4 * sc, 14 * sc)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Drag = 3
			e.Acceleration = Vector3.new(0, 2, 0)
			e.Parent = holder
			e:Emit(count)
			Debris:AddItem(holder, 4)
		end

		-- Mother's roar sound is reused (pitched up) as the hatchling's cry
		local roarSrc = mother.PrimaryPart:FindFirstChild("Mother_Roar")
		local function cry(parentPart, speed, volume)
			if roarSrc and roarSrc:IsA("Sound") and roarSrc.SoundId ~= "" and parentPart then
				local s = roarSrc:Clone()
				s.Looped = false
				s.PlaybackSpeed = speed
				s.Volume = volume
				s.Parent = parentPart
				s:Play()
				Debris:AddItem(s, 8)
			end
		end

		-- Placing Mother and the hatchling (smoothed to the ground)
		local mY = g(S, mFeet)
		local function placeMother(pos, dir, pitch, roll, lift, dt)
			mY = lerp(mY, g(pos, mFeet), 1 - math.exp(-dt * 6))
			local pivotPos = Vector3.new(pos.X, mY + pivotAbove + lift, pos.Z)
			mother:PivotTo(
				CFrame.lookAt(pivotPos, pivotPos + dir)
					* CFrame.Angles(0, CFG.MotherFaceFix, 0)
					* CFrame.Angles(pitch, 0, roll)
			)
		end

		-- ===== Hatchling motion: a yaw spring, so it always turns the short way =====
		local FACE = if HatchlingProp.GetFaceFix then HatchlingProp.GetFaceFix() else (HatchlingProp.FACE_FIX or CFG.HatchFaceFix)
		local W = math.max(math.min(size.X, size.Z), hh * 1.5) -- Mother's width
		local nuzzle = flat(T + u * (L * 0.5 + hh * 1.2)) -- where it stops in front of her snout
		local lookEnd = CFG.TurnAt + CFG.TurnTime - 0.3 -- the look-back ends as she finishes turning
		local TROT_TIME = 2.6
		local cryTimes = { CFG.RunAt, CFG.GreetAt + 0.5, CFG.TurnAt + 0.9 }

		local hyaw, hyawVel = yawOf(d), 0
		local hY = g(P, P.Y)
		local hvel = Vector3.zero
		local lastHpos = flat(P)
		local hStride, lastStepNo = 0, 0
		local skidDone, chirp3 = false, false
		local turnSteps = -1
		local lastCamPos = P

		-- Facing test: a green arrow that shows where the code thinks the hatchling's front is
		local arrow = nil
		if CFG.FaceArrow and runner then
			arrow = Instance.new("Part")
			arrow.Anchored = true
			arrow.CanCollide = false
			arrow.CanQuery = false
			arrow.CanTouch = false
			arrow.Material = Enum.Material.Neon
			arrow.Color = Color3.fromRGB(80, 255, 120)
			arrow.Size = Vector3.new(hh * 0.12, hh * 0.12, hh * 1.4)
			arrow.Parent = fx
		end

		local function turnToward(targetYaw, dt)
			local k = 130
			local c = 2 * math.sqrt(k) * 0.85
			hyawVel += (angleDiff(hyaw, targetYaw) * k - hyawVel * c) * dt
			hyawVel = math.clamp(hyawVel, -9, 9)
			hyaw += hyawVel * dt
		end

		-- noseUp > 0 tips the nose up, roll leans it sideways. Facing comes from hyaw.
		local function placeHatch(pos, lift, noseUp, roll, dt)
			hY = lerp(hY, g(pos, P.Y), 1 - math.exp(-dt * 10))
			local pivotPos = Vector3.new(pos.X, hY + lift + hFoot, pos.Z)
			runner:PivotTo(
				CFrame.new(pivotPos)
					* CFrame.Angles(0, hyaw + FACE, 0)
					* CFrame.Angles(-noseUp, 0, roll)
			)
		end

		-- State
		local mpos, mdir = S, u
		local lastMpos = S
		local spdS, phase, lastStep, lastQ = 0, 0, 0, 0
		local shake, punch, bloomKick = 0, 0, 0
		local roarDone, chirp1, chirp2, reply = false, false, false, false
		local hp = flat(P)
		local hpos3 = P
		local mbase = Vector3.new(S.X, mY, S.Z)
		local subShown, subHidden = {}, {}

		-- q = which foot lands: 0 front left, 1 hind left, 2 front right, 3 hind right
		local function footfall(k, q)
			local right = Vector3.new(-mdir.Z, 0, mdir.X)
			local frontLeg = q % 2 == 0
			local leftLeg = (q % 4) < 2
			local fp = mpos
				+ right * ((if leftLeg then -1 else 1) * L * 0.12)
				+ mdir * ((if frontLeg then 1 else -1) * L * 0.28)
			puff(Vector3.new(fp.X, g(fp, mFeet) + 0.5, fp.Z), 2.5 * sc, math.floor(8 + 14 * k))
			local camDist = (camera.CFrame.Position - mpos).Magnitude
			shake = math.max(shake, 0.55 * k * math.clamp(1 - camDist / (L * 5), 0, 1))
		end

		-- First frame: cut in, then fade up from black
		camera.CameraType = Enum.CameraType.Scriptable
		TweenService:Create(black, TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()

		local start = os.clock()
		local last = start

		while true do
			local now = os.clock()
			local t = now - start
			local dt = math.min(now - last, 0.05)
			last = now
			if skipped or t >= CFG.Total then
				break
			end

			---------------------------------------------------------
			-- Mother's path
			---------------------------------------------------------
			if t < CFG.WalkStart then
				mpos, mdir = S, u
			elseif t < CFG.ArriveAt then
				local x = (t - CFG.WalkStart) / (CFG.ArriveAt - CFG.WalkStart)
				mpos = S:Lerp(T, 1 - (1 - x) ^ 1.6)
				mdir = u
			elseif t < CFG.TurnAt then
				mpos, mdir = T, u
			else
				local a = ease((t - CFG.TurnAt) / CFG.TurnTime)
				mdir = CFrame.Angles(0, math.pi * a, 0):VectorToWorldSpace(u)
				local tau = math.max(0, t - CFG.LeaveAt)
				mpos = T - u * (0.5 * leaveAcc * tau * tau)
			end

			-- Gait: heavy steps that follow her real speed. With bones, the dust lands when a real foot lands.
			local spd = if dt > 0 then flat(mpos - lastMpos).Magnitude / dt else 0
			lastMpos = mpos
			spdS = lerp(spdS, spd, 1 - math.exp(-dt * 8))
			local k = math.clamp(spdS / math.max(L * 0.18, 4), 0, 1)
			local ph
			if mAnim then
				ph = mAnim.Phase * math.pi * 4 -- one step every pi, in time with her legs
				local q = math.floor(mAnim.Phase * 4)
				if q ~= lastQ then
					lastQ = q
					if mAnim.Gait > 0.35 then
						footfall(k, q)
					end
				end
			else
				phase += spdS / math.max(L * 0.3, 3) * math.pi * dt
				ph = phase
				local stepNo = math.floor(phase / math.pi)
				if stepNo > lastStep then
					lastStep = stepNo
					footfall(k, stepNo)
				end
			end
			local lift = (math.abs(math.sin(ph)) - 0.5) * L * 0.03 * k
			local roll = math.sin(ph) * 0.05 * k
			local pitch = math.cos(ph * 2) * 0.02 * k

			-- The roar: she rears up (with bones the head and neck do most of it)
			local tr = t - CFG.RoarAt
			local roarEnv = 0
			if tr >= 0 and tr < 1.9 then
				roarEnv = ease(tr / 0.35) * (1 - ease((tr - 1.2) / 0.7))
				pitch += (if mAnim then 0.14 else 0.32) * roarEnv
				lift += L * 0.05 * roarEnv
				roll += math.sin(t * 30) * 0.01 * roarEnv
				shake = math.max(shake, 0.4 * roarEnv)
			end
			-- The nuzzle: she lowers her head to the hatchling
			local nuzzleA = 0
			if t >= CFG.GreetAt and t < CFG.TurnAt then
				nuzzleA = math.sin(((t - CFG.GreetAt) / (CFG.TurnAt - CFG.GreetAt)) * math.pi)
				pitch -= 0.12 * nuzzleA
				roll += math.sin(t * 2.3) * 0.02
			end

			placeMother(mpos, mdir, pitch, roll, lift, dt)
			mbase = Vector3.new(mpos.X, mY, mpos.Z)

			-- Mother's bones: legs from her speed, head up for the roar, head turns to the hatchling and lowers to nuzzle it
			if mAnim then
				local turning = t >= CFG.TurnAt and t < CFG.TurnAt + CFG.TurnTime
				local animSpeed = if turning then math.max(spdS, L * 0.12) else spdS
				local lookYaw = 0
				if t >= CFG.GreetAt and t < CFG.TurnAt + 0.8 then
					local toH = flat(hpos3 - mpos)
					if toH.Magnitude > 1 then
						local dirH = toH.Unit
						local right = Vector3.new(-mdir.Z, 0, mdir.X)
						lookYaw = math.clamp(math.atan2(dirH:Dot(right), dirH:Dot(mdir)), -0.9, 0.9)
					end
				end
				mAnim:Step(dt, { Speed = animSpeed, Roar = roarEnv, LookYaw = lookYaw, LookPitch = -0.45 * nuzzleA })
			end

			-- shuffling steps (with dust and a small shake) while she turns around
			if t >= CFG.TurnAt and t < CFG.TurnAt + CFG.TurnTime then
				local n = math.floor((t - CFG.TurnAt) / 0.55)
				if n > turnSteps then
					turnSteps = n
					footfall(0.55, n)
				end
			end

			if not roarDone and t >= CFG.RoarAt then
				roarDone = true
				cry(mother.PrimaryPart, 0.9, 1)
				shake = 1.4
				punch = 10
				bloomKick = 1.2
				puff(Vector3.new(mpos.X, mY + 1, mpos.Z), 7 * sc, 70)
			end
			if not chirp1 and t >= CFG.RunAt then
				chirp1 = true
				cry(runner and runner.PrimaryPart or mother.PrimaryPart, 2.3, 0.5)
			end
			if not reply and t >= CFG.GreetAt then
				reply = true
				cry(mother.PrimaryPart, 0.65, 0.5)
			end
			if not chirp2 and t >= CFG.GreetAt + 0.5 then
				chirp2 = true
				cry(runner and runner.PrimaryPart or mother.PrimaryPart, 2.1, 0.55)
			end

			---------------------------------------------------------
			-- The hatchling
			---------------------------------------------------------
			if runner then
				local runEnd = CFG.RunAt + CFG.RunTime
				local jump, noseUp, hroll, look, glance, excite = 0, 0, 0, nil, 0, 0.25
				local hold = nuzzle + u * hh -- where it backs off to when it looks back at us

				if t < CFG.RunAt then
					-- WAITING at the pad: glances around, then watches Mother, shivering. It flinches at the roar.
					hp = flat(P)
					look = yawOf(d) + 1.1 * math.sin(t * 2.0) * (1 - ease(t / 3.4))
					hroll += math.sin(t * 26) * 0.03
					local r = t - CFG.RoarAt
					if r >= 0 and r < 0.6 then
						local s = math.sin(math.pi * r / 0.6)
						jump += hh * 0.3 * s
						noseUp += 0.35 * s
						hroll += math.sin(t * 40) * 0.08 * s
						look += 0.4 * s
						excite = 1
					end
					-- wind-up: it pulls back and crouches just before it bolts
					local w = ease((t - (CFG.RunAt - 0.55)) / 0.55)
					hp = hp - d * (hh * 0.15 * w)
					noseUp -= 0.28 * w
					hroll += math.sin(t * 34) * 0.05 * w
				elseif t < runEnd then
					-- RUNNING to her snout: weaves like an excited puppy, then skids to a stop
					local a = (t - CFG.RunAt) / CFG.RunTime
					local from = flat(P) - d * (hh * 0.15)
					hp = from:Lerp(nuzzle, ease(a)) + side * (math.sin(a * math.pi * 2) * hh * 0.3 * (1 - a))
					noseUp -= 0.28 * (1 - ease(math.min(a * 3, 1)))
					excite = 0.8
					if a > 0.8 then
						noseUp += 0.32 * math.sin(math.pi * (a - 0.8) / 0.2)
						if not skidDone and a > 0.86 then
							skidDone = true
							puff(Vector3.new(hp.X, hY + 0.5, hp.Z), hh * 0.2, 14)
						end
					end
				elseif t < CFG.TurnAt then
					-- GREETING: looks up at her snout and bounces with joy
					hp = nuzzle
					look = yawOf(flat(T + u * (L * 0.5)) - hp)
					local g1 = t - runEnd
					if g1 >= 0 and g1 < 1.2 then
						jump += hh * 0.22 * math.abs(math.sin(g1 * math.pi / 0.6))
					end
					noseUp += 0.2 * ease(g1 / 0.4) + 0.06 * math.sin(t * 3)
					hroll += math.sin(t * 15) * 0.05
					excite = 1
				elseif t < lookEnd then
					-- LOOKING BACK: Mother turns around. It backs off, looks at us, chirps and hops.
					local a = ease((t - CFG.TurnAt) / 1.0)
					hp = nuzzle + u * (hh * a)
					look = yawOf(flat(lastCamPos) - hp)
					local h = t - (CFG.TurnAt + 0.9)
					if h >= 0 and h < 0.6 then
						jump += hh * 0.25 * math.sin(math.pi * h / 0.6)
					end
					noseUp += 0.2 * (1 - a)
					hroll += math.sin(t * 12) * 0.04
					excite = 1
				else
					-- TROTTING around her flank to lead the way
					local tt = t - lookEnd
					local a = ease(tt / TROT_TIME)
					local P1 = flat(T) + side * (W * 0.5 + hh * 1.4)
					local P2 = flat(mpos) + d * (L * 0.5 + hh * 1.1) + side * (hh * 0.8)
					local b = 1 - a
					hp = hold * (b * b) + P1 * (2 * b * a) + P2 * (a * a)
					hp += side * (math.sin(tt * 2.2) * hh * 0.2 * ease((tt - TROT_TIME) / 1.0))
					glance = math.sin(math.pi * math.clamp((t - (CFG.LeaveAt + 2.1)) / 0.9, 0, 1))
					excite = 0.7
				end

				-- Gait, driven by how fast it is really moving: bounce, waddle and footfall dust
				local vel = flat(hp - lastHpos) / math.max(dt, 0.001)
				lastHpos = hp
				hvel = hvel:Lerp(vel, 1 - math.exp(-dt * 12))
				local hspd = hvel.Magnitude
				local sf = math.clamp(hspd / (hh * 2.4), 0, 1)
				hStride += hspd * dt / (hh * 0.55)
				local hlift = jump + math.abs(math.sin(hStride * math.pi)) * hh * (if hAnim then 0.05 else 0.1) * sf
				hroll += math.sin(hStride * math.pi) * (if hAnim then 0.05 else 0.09) * sf
				noseUp += math.cos(hStride * 2 * math.pi) * 0.04 * sf - 0.1 * sf
				local stepNo = math.floor(hStride)
				if stepNo > lastStepNo then
					lastStepNo = stepNo
					if sf > 0.35 then
						puff(Vector3.new(hp.X, hY + 0.3, hp.Z), hh * 0.14, 2)
					end
				end

				-- Facing: a look target if the scene gives one, otherwise the way it is moving
				local faceYaw = look
				if not faceYaw then
					faceYaw = if hspd > hh * 0.8 then yawOf(hvel) else hyaw
				end
				if glance > 0 then
					faceYaw += glance * angleDiff(faceYaw, yawOf(flat(lastCamPos) - hp)) * 0.7
				end
				turnToward(faceYaw, dt)
				hroll += math.clamp(hyawVel * CFG.Bank, -0.3, 0.3) -- leans into its turns

				placeHatch(hp, hlift, noseUp, hroll, dt)
				hpos3 = Vector3.new(hp.X, hY + hlift, hp.Z)

				-- Its bones: legs from its speed, legs tucked for hops, tail wag, head leads every turn, head up for a chirp
				if hAnim then
					local chirp = 0
					for _, ct in cryTimes do
						local cu = t - ct
						if cu >= 0 and cu < 0.5 then
							chirp = math.max(chirp, math.sin(math.pi * cu / 0.5))
						end
					end
					hAnim:Step(dt, {
						Speed = hspd,
						Tuck = math.clamp(jump / (hh * 0.2), 0, 1),
						Excite = excite,
						Roar = 0.55 * chirp,
						LookYaw = -math.clamp(angleDiff(hyaw, faceYaw), -1.1, 1.1),
					})
				end

				if not chirp3 and t >= CFG.TurnAt + 0.9 then
					chirp3 = true
					cry(runner.PrimaryPart or mother.PrimaryPart, 2.4, 0.55)
				end
				if arrow then
					local dirv = Vector3.new(math.sin(hyaw), 0, math.cos(hyaw))
					local c = hpos3 + up * (hh * 0.6) + dirv * hh
					arrow.CFrame = CFrame.lookAt(c, c + dirv)
				end
			end

			---------------------------------------------------------
			-- Camera
			---------------------------------------------------------
			local camPos, camLook, fov
			if t < 3.4 then
				-- low, behind the hatchling, watching the horizon
				local a = ease(t / 3.4)
				camPos = onGround(P - d * lerp(hh * 2.4, hh * 1.5, a), hh * 0.45, P.Y)
				camLook = mbase + up * (Hm * 0.4)
				fov = lerp(58, 50, a)
			elseif t < CFG.ArriveAt then
				-- a side tracking shot as she passes
				local a = ease((t - 3.4) / (CFG.ArriveAt - 3.4))
				camPos = onGround(S:Lerp(T, 0.42 + 0.3 * a) + side * (L * 1.5), hh * 0.7, P.Y)
				camLook = mbase + up * (Hm * 0.4)
				fov = 52
			elseif t < CFG.RunAt then
				-- looking up at her as she rears and roars
				local a = ease((t - CFG.ArriveAt) / (CFG.RunAt - CFG.ArriveAt))
				camPos = onGround(P + d * (stopDist * 0.4) + side * (hh * 2.6), hh * 0.5, P.Y)
				camLook = mbase + u * (L * 0.3) + up * (Hm * 0.7)
				fov = lerp(62, 46, a)
			elseif t < CFG.GreetAt then
				-- following the hatchling as it runs
				camPos = onGround(P:Lerp(T, 0.5) + side * L, hh * 0.7, P.Y)
				camLook = (hpos3 + up * (hh * 0.5)):Lerp(mbase + up * (Hm * 0.45), 0.25)
				fov = 50
			elseif t < lookEnd then
				-- the reunion in profile, drifting round to the front as it looks back at us
				local a = ease((t - CFG.GreetAt) / (lookEnd - CFG.GreetAt))
				camPos = onGround(nuzzle + side * (hh * 4.6 - a * hh) + u * (hh * (0.4 + a * 2.6)), hh * 0.85, P.Y)
				camLook = (hpos3 + up * (hh * 0.55)):Lerp(mbase + u * (L * 0.4) + up * (Hm * 0.5), 0.3 * (1 - a))
				fov = lerp(42, 36, a)
			else
				-- crane up and back as they walk away together
				local a = ease((t - lookEnd) / (CFG.Total - lookEnd))
				local p0 = onGround(nuzzle + side * (hh * 3.6) + u * (hh * 3.0), hh * 0.85, P.Y)
				local p1 = onGround(T + side * (L * 1.5) + u * (L * 0.3), Hm * 0.8, P.Y)
				camPos = p0:Lerp(p1, a)
				camLook = (hpos3 + up * (hh * 0.55)):Lerp((mbase + hpos3) / 2 + up * (Hm * 0.3), a)
				fov = lerp(36, 46, a)
			end

			shake = math.max(0, shake - dt * 1.8)
			punch *= math.exp(-dt * 3)
			bloomKick *= math.exp(-dt * 2.5)
			local amp = shake + (if t < CFG.ArriveAt then 0.04 * k else 0.01)
			lastCamPos = camPos
			camera.FieldOfView = fov + punch
			camera.CFrame = CFrame.lookAt(camPos, camLook)
				* CFrame.new(noise(t * 13, 1.3) * amp * sc, noise(t * 11, 7.1) * amp * sc, 0)
				* CFrame.Angles(0, 0, noise(t * 7, 3.3) * amp * 0.01)

			-- Mood: cold and tense, then warm for the reunion
			local warm = ease((t - 13.5) / 2.5)
			grade.TintColor = COOL:Lerp(WARM, warm)
			bloom.Intensity = 0.5 + 0.5 * warm + bloomKick
			Lighting.ExposureCompensation = lerp(-0.25, 0.1, warm) + bloomKick * 0.3

			-- Subtitles
			for i, s in SUBS do
				if not subShown[i] and t >= s[1] then
					subShown[i] = true
					subtitle.Text = s[3]
					TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
				end
				if subShown[i] and not subHidden[i] and t >= s[2] then
					subHidden[i] = true
					TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end
			end
			if not blackDone and t >= CFG.BlackAt then
				blackDone = true
				TweenService:Create(black, TweenInfo.new(0.7), { BackgroundTransparency = 0 }):Play()
			end

			RunService.RenderStepped:Wait()
		end
	end)
	if not ok then
		warn("[ReleaseCutscene] " .. tostring(err))
	end

	-- Cover with black (skip, error or the normal ending), then put everything back
	keyConn:Disconnect()
	TweenService:Create(black, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	if not blackDone then
		task.wait(0.35)
	end

	Workspace:SetAttribute("MotherShow", nil) -- hide her again (the screen is already black here)
	if mAnim then
		mAnim:Reset()
	end
	if hAnim then
		hAnim:Reset()
	end
	if mother then
		mother:SetAttribute("Manual", nil) -- DinoLife takes over again
	end
	if runner then
		runner:SetAttribute("Manual", nil)
	end
	if mother and typeof(home) == "CFrame" then
		pcall(function()
			mother:PivotTo(home)
		end)
	end
	if runner then
		for _, d in runner:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
	end
	if fx then
		fx:Destroy()
	end
	if bloom then
		bloom:Destroy()
	end
	if grade then
		grade:Destroy()
	end
	Lighting.ExposureCompensation = savedExposure

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
	TweenService:Create(black, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	tweenBars(top, bottom, 0, 0.5)
	task.delay(0.7, function()
		gui:Destroy()
	end)
	running = false
end

local lastId = Workspace:GetAttribute("CutsceneId") or 0
Workspace:GetAttributeChangedSignal("CutsceneId"):Connect(function()
	local id = Workspace:GetAttribute("CutsceneId") or 0
	if id <= lastId then
		return
	end
	lastId = id
	task.wait()
	if Workspace:GetAttribute("Cutscene") == "Release" then
		task.spawn(run)
	end
end)

print("[ReleaseCutscene] v3 Init OK")
