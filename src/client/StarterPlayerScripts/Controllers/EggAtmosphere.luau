local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local EggAtmosphere = {}

---------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------
local HEAR_DISTANCE = 120 -- plate pops and ambient fade out over this many studs
local SHAKE_DISTANCE = 140
local SHAKE_MAGNITUDE = 0.7 -- studs of camera wobble at full strength
local SHAKE_TIME = 0.9
local GLOW_COLOR = Color3.fromRGB(255, 200, 90)
local GLOW_MIN_BRIGHTNESS, GLOW_MAX_BRIGHTNESS = 0.3, 3.5 -- Core light: untouched egg to fully dug
local GLOW_MIN_RANGE, GLOW_MAX_RANGE = 20, 60

local Sounds
local watched = {} -- [eggModel] = { LastLayers }
local loops = {} -- [name] = { Sound, Base }
local glows = {} -- [PointLight] = egg model
local shakeUntil, shakeScale = 0, 0

local function distanceTo(position: Vector3): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return math.huge
	end
	return (camera.CFrame.Position - position).Magnitude
end

-- 0..1: how dug out the egg is (the same number the progress bar shows)
local function progressOf(model: Model): number
	if model:GetAttribute("Revealed") or model:GetAttribute("Broken") then
		return 1
	end
	local max = model:GetAttribute("MaxDurability") or 1
	return math.clamp(1 - (model:GetAttribute("Durability") or max) / max, 0, 1)
end

---------------------------------------------------------------------
-- Plate pops (any patch layer broke, by anyone)
---------------------------------------------------------------------
local function onLayersChanged(model: Model, state)
	local new = model:GetAttribute("PatchLayer")
	if type(new) ~= "string" then
		return
	end
	local old = state.LastLayers
	state.LastLayers = new
	if type(old) ~= "string" or #old ~= #new then
		return
	end
	for i = 1, #new do
		if string.byte(new, i) > string.byte(old, i) then
			local scale = math.clamp(1 - distanceTo(model:GetPivot().Position) / HEAR_DISTANCE, 0, 1)
			if scale > 0 then
				Sounds.Play("PlatePop", scale)
			end
			return -- one pop per update is enough
		end
	end
end

---------------------------------------------------------------------
-- Core glow (client only): there from the start, brighter as the egg is dug out
---------------------------------------------------------------------
local function attachGlow(model: Model)
	task.spawn(function()
		local core = model:WaitForChild("Core", 10)
		if not (core and core:IsA("BasePart")) or core:FindFirstChild("CoreGlow") then
			return
		end
		local light = Instance.new("PointLight")
		light.Name = "CoreGlow"
		light.Color = GLOW_COLOR
		light.Range = GLOW_MIN_RANGE
		light.Brightness = GLOW_MIN_BRIGHTNESS
		light.Parent = core
		glows[light] = model
	end)
end

local function watchEgg(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	local state = { LastLayers = model:GetAttribute("PatchLayer") }
	watched[model] = state
	model:GetAttributeChangedSignal("PatchLayer"):Connect(function()
		onLayersChanged(model, state)
	end)
	attachGlow(model)
end

---------------------------------------------------------------------
-- Ambient heartbeat and rumble, louder as the egg nears giving way
---------------------------------------------------------------------
local function makeLoop(name: string)
	local folder = ReplicatedStorage:FindFirstChild("GameSounds")
	local template = folder and folder:FindFirstChild(name)
	if not (template and template:IsA("Sound")) then
		print(string.format("[EggAtmosphere] GameSounds has no '%s' (that ambient loop stays off)", name))
		return nil
	end
	local sound = template:Clone()
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	return { Sound = sound, Base = template.Volume }
end

local function updateAmbient()
	local eggs = Workspace:FindFirstChild("Eggs")
	local best, bestDist = nil, HEAR_DISTANCE
	if eggs then
		for _, model in eggs:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("MaxDurability") and not model:GetAttribute("Broken") then
				local dist = distanceTo(model:GetPivot().Position)
				if dist < bestDist then
					best, bestDist = model, dist
				end
			end
		end
	end

	local progress, near = 0, 0
	if best then
		progress = progressOf(best)
		near = 1 - bestDist / HEAR_DISTANCE
	end

	local heart = loops.Heartbeat
	if heart then
		heart.Sound.Volume = heart.Base * math.clamp((progress - 0.5) * 2, 0, 1) * near
		heart.Sound.PlaybackSpeed = 0.85 + 0.5 * progress
	end
	local rumble = loops.Rumble
	if rumble then
		rumble.Sound.Volume = rumble.Base * math.clamp((progress - 0.3) / 0.7, 0, 1) * 0.6 * near
	end
end

---------------------------------------------------------------------
function EggAtmosphere.Init()
	-- Break shake: wobbles the camera for a moment when an egg breaks nearby
	RunService:BindToRenderStep("EggAtmosphereShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now >= shakeUntil then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local m = SHAKE_MAGNITUDE * shakeScale * ((shakeUntil - now) / SHAKE_TIME)
		camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * 2 * m, (math.random() - 0.5) * 2 * m, 0)
	end)

	-- Core glow: brightness and reach follow the dig progress, with a slow pulse
	RunService.Heartbeat:Connect(function()
		local pulse = 1 + math.sin(os.clock() * 3) * 0.2
		for light, model in glows do
			if light.Parent and model.Parent then
				local p = progressOf(model)
				light.Brightness = (GLOW_MIN_BRIGHTNESS + (GLOW_MAX_BRIGHTNESS - GLOW_MIN_BRIGHTNESS) * p) * pulse
				light.Range = GLOW_MIN_RANGE + (GLOW_MAX_RANGE - GLOW_MIN_RANGE) * p
			else
				glows[light] = nil
			end
		end
	end)

	-- Everything that waits runs in its own thread so the other controllers start right away.
	task.spawn(function()
		Sounds = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Sounds"))
		Sounds.Init() -- safe to call twice

		loops.Heartbeat = makeLoop("Heartbeat")
		loops.Rumble = makeLoop("Rumble")

		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		remotes:WaitForChild("EggBroken").OnClientEvent:Connect(function(_, position)
			local scale = math.clamp(1 - distanceTo(position) / SHAKE_DISTANCE, 0, 1)
			if scale > 0 then
				shakeUntil = os.clock() + SHAKE_TIME
				shakeScale = scale
			end
		end)

		local eggs = Workspace:WaitForChild("Eggs")
		eggs.ChildAdded:Connect(watchEgg)
		eggs.ChildRemoved:Connect(function(model)
			watched[model] = nil
		end)
		for _, model in eggs:GetChildren() do
			watchEgg(model)
		end

		print("[EggAtmosphere] Init OK")
		while true do
			task.wait(0.25)
			updateAmbient()
		end
	end)
end

return EggAtmosphere