local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = {}

-- How much the pitch wobbles, so repeated hits don't sound identical
local PITCH_JITTER = { Hit = 0.12, Weak = 0.08, Click = 0.05, PlatePop = 0.1 }

local HEAR_DISTANCE = 90 -- other players' hits fade out over this many studs
local started = false
local templates: { [string]: Sound } = {}

function Sounds.Play(name: string, volumeScale: number?, speed: number?)
	local template = templates[name]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Volume = template.Volume * (volumeScale or 1)
	local baseName = string.match(name, "^(%a+)_") or name
	local jitter = PITCH_JITTER[baseName]
	if jitter then
		sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * jitter
	end
	if speed then
		sound.PlaybackSpeed = speed
	end
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 10)
end

-- The tool the local player is holding right now (by its ToolId attribute)
local function heldToolId(): string?
	local character = Players.LocalPlayer.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				local id = child:GetAttribute("ToolId")
				if id then
					return id
				end
			end
		end
	end
	return nil
end

-- Picks the most specific sound that exists: Weak_Tool, Weak, Hit_Tool, Hit
local function hitSoundName(toolId: string?, isWeakPoint: boolean): string
	if isWeakPoint then
		if toolId and templates["Weak_" .. toolId] then
			return "Weak_" .. toolId
		end
		if templates.Weak then
			return "Weak"
		end
	end
	if toolId and templates["Hit_" .. toolId] then
		return "Hit_" .. toolId
	end
	return "Hit"
end

local function distanceScale(position: any): number
	local camera = workspace.CurrentCamera
	if not camera or typeof(position) ~= "Vector3" then
		return 1
	end
	return math.clamp(1 - (camera.CFrame.Position - position).Magnitude / HEAR_DISTANCE, 0, 1)
end

-- Safe to call more than once. Never yields the caller.
function Sounds.Init()
	if started then
		return
	end
	started = true

	-- Load every Sound in ReplicatedStorage.GameSounds once
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("GameSounds", 10)
		if not folder then
			warn("[Sounds] ReplicatedStorage.GameSounds folder not found. Audio is off.")
			return
		end
		for _, child in folder:GetChildren() do
			if child:IsA("Sound") then
				local ok = pcall(ContentProvider.PreloadAsync, ContentProvider, { child })
				if ok and (child.IsLoaded or child.TimeLength > 0) then
					templates[child.Name] = child
				else
					warn(string.format("[Sounds] '%s' failed to load (%s). Replace that Sound.", child.Name, child.SoundId))
				end
			end
		end
	end)

	-- Game events
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		if not remotes then
			return
		end

		local eggHit = remotes:WaitForChild("EggHit", 5)
		if eggHit then
			eggHit.OnClientEvent:Connect(function(_, position, _, isWeakPoint, serverToolId)
				local scale = distanceScale(position)
				if scale <= 0 then
					return
				end
				-- Use the tool the server names, otherwise the one you are holding
				local toolId = if typeof(serverToolId) == "string" then serverToolId else heldToolId()
				Sounds.Play(hitSoundName(toolId, isWeakPoint == true), scale)
			end)
		end

		local eggBroken = remotes:WaitForChild("EggBroken", 5)
		if eggBroken then
			eggBroken.OnClientEvent:Connect(function()
				Sounds.Play("Break")
			end)
		end

		local sellResult = remotes:WaitForChild("SellResult", 5)
		if sellResult then
			sellResult.OnClientEvent:Connect(function()
				Sounds.Play("Sell")
			end)
		end

		local notify = remotes:WaitForChild("Notify", 5)
		if notify then
			notify.OnClientEvent:Connect(function(_, kind)
				if string.lower(tostring(kind or "")) == "success" then
					Sounds.Play("Buy")
				else
					Sounds.Play("Error")
				end
			end)
		end
	end)
end

return Sounds