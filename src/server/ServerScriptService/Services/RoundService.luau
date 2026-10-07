local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HatchlingProp = require(ReplicatedStorage.Shared.HatchlingProp)

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EggDefinitions = require(ReplicatedStorage.Shared.EggDefinitions)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local EggService = require(script.Parent.EggService)

local RoundService = {}

local CORE_COLOR = Color3.fromRGB(255, 170, 40)
local TELEPORT_DELAY = 0.5 -- the screen fades to black first, then players are moved
local CUTSCENE_TIME = 33 -- must stay at least 1.5s longer than CFG.Total in the client script (31)
local RELEASE_TIME = GameConfig.Mother.ReleaseCutsceneTime -- the Release scene's length

local Remotes: Folder
local deliveryPad: BasePart
local deliverPrompt: ProximityPrompt

-- Match flow:
-- "Playing"
--     ↓
-- "CoreReady"
--     ↓
-- "Carrying"
--     ↓
-- "Ended"
--     ↓
-- return players to Lobby
--
-- IMPORTANT:
-- There is NO second round inside this server anymore.
-- One server = one match.
local state = "Playing"
local corePart: BasePart? = nil
local matchEnded = false
local returningToLobby = false

local motherModel: Model? = nil
local motherFootsteps: Sound? = nil
local hatchlingTemplate: Model? = nil
local releaseStarted = false

---------------------------------------------------------------------
-- Round / Match State
---------------------------------------------------------------------

local function setState(newState: string)
	state = newState
	Workspace:SetAttribute("RoundState", newState)
end

local function getAliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end

	return root
end

---------------------------------------------------------------------
-- Mother: helpers used by both Escort (footsteps) and Release
---------------------------------------------------------------------

-- Tweens a Model's pivot (works on anchored models; uses the classic CFrameValue trick)
local function tweenPivot(model: Model, targetCFrame: CFrame, duration: number, style: Enum.EasingStyle?)
	local proxy = Instance.new("CFrameValue")
	proxy.Value = model:GetPivot()
	local connection
	connection = proxy:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:PivotTo(proxy.Value)
		end
	end)
	local tween = TweenService:Create(
		proxy,
		TweenInfo.new(duration, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Value = targetCFrame }
	)
	tween.Completed:Connect(function()
		connection:Disconnect()
		proxy:Destroy()
	end)
	tween:Play()
	return tween
end

-- Scales a model so its bounding-box height matches targetHeight, regardless of its current scale
local function scaleModelTo(model: Model, targetHeight: number)
	local _, size = model:GetBoundingBox()
	if size.Y > 0.01 then
		model:ScaleTo(model:GetScale() * (targetHeight / size.Y))
	end
end

-- Fades every part/decal in a model to a given transparency
local function fadeModel(model: Model, targetTransparency: number, duration: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, TweenInfo.new(duration), { Transparency = targetTransparency }):Play()
		end
	end
end

-- Finds and prepares Workspace.Dino as Mother: anchored, non-colliding, PrimaryPart set
local function findStaticMother(): Model?
	local dino = Workspace:FindFirstChild("Dino")
	if not dino or not dino:IsA("Model") then
		warn("[RoundService] Workspace.Dino not found. The Release scene will be skipped.")
		return nil
	end

	if not dino.PrimaryPart then
		local biggest, volume = nil, 0
		for _, d in dino:GetDescendants() do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > volume then
					biggest, volume = d, v
				end
			end
		end
		dino.PrimaryPart = biggest
	end

	for _, d in dino:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	dino:SetAttribute("HomeCFrame", dino:GetPivot())
	return dino
end

---------------------------------------------------------------------
-- Rigged Mother: replaces the rigid Workspace.Dino with a scaled copy of ReplicatedStorage.DinoRig
---------------------------------------------------------------------
local MOTHER_YAW = 0 -- extra turn if she faces the wrong way in the field (try math.pi)

local function buildRiggedMother(old: Model, template: Model): Model?
	local CollectionService = game:GetService("CollectionService")

	-- Where the old Dino stands, how long it is, and which way it faces
	local bbCF, bbSize = old:GetBoundingBox()
	local feet = Vector3.new(bbCF.X, bbCF.Y - bbSize.Y / 2, bbCF.Z)
	local length = math.max(bbSize.X, bbSize.Z)
	local look = old:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end

	-- Keep the old sounds (SoundIds you already pasted)
	local sounds = {}
	for _, d in old:GetDescendants() do
		if d:IsA("Sound") and (d.Name == "Mother_Step" or d.Name == "Mother_Roar") then
			table.insert(sounds, d:Clone())
		end
	end

	local model = template:Clone()
	model.Name = "Dino"
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	local mesh = model.PrimaryPart
	if not mesh or not mesh:IsA("BasePart") then
		mesh = model:FindFirstChildWhichIsA("MeshPart")
	end
	if not mesh then
		model:Destroy()
		return nil
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

	old.Name = "Dino_Static"
	model.Parent = Workspace
	model:ScaleTo(model:GetScale() * length / math.max(mesh.Size.Z, 0.05))

	-- Invisible pivot part at her FEET. Her front is its -Z, which is what the Release scene expects for Mother.
	local rotation = mesh.CFrame - mesh.Position
	local feetLocal = mesh.Position - mesh.CFrame.UpVector * (mesh.Size.Y / 2)
	local rig = Instance.new("Part")
	rig.Name = "Rig"
	rig.Size = Vector3.new(1, 1, 1)
	rig.Transparency = 1
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.Massless = true
	rig.CFrame = CFrame.new(feetLocal) * rotation
	rig.Parent = model
	model.PrimaryPart = rig

	model:PivotTo(CFrame.lookAt(feet, feet + look) * CFrame.Angles(0, MOTHER_YAW, 0))

	-- Sounds go on the rig (the code looks for them on her PrimaryPart)
	for _, s in sounds do
		s.Parent = rig
	end
	for _, name in { "Mother_Step", "Mother_Roar" } do
		if not rig:FindFirstChild(name) then
			local s = Instance.new("Sound")
			s.Name = name
			s.Looped = name == "Mother_Step"
			s.Volume = if name == "Mother_Step" then 0.6 else 1
			s.RollOffMinDistance = 15
			s.RollOffMaxDistance = 260
			s.Parent = rig
		end
	end

	model:SetAttribute("DinoProfile", "Mother")
	model:SetAttribute("DinoMode", "Idle")
	model:SetAttribute("HomeCFrame", model:GetPivot())
	CollectionService:AddTag(model, "DinoAnim")

	old:Destroy()
	return model
end

local function findMother(): Model?
	local old = Workspace:FindFirstChild("Dino")
	local template = ReplicatedStorage:FindFirstChild("DinoRig")
	if old and old:IsA("Model") and template and template:IsA("Model") then
		local ok, result = pcall(buildRiggedMother, old, template)
		if ok and result then
			print("[RoundService] Mother is now the rigged dinosaur.")
			return result
		end
		warn("[RoundService] Could not build the rigged Mother, using the old model: " .. tostring(result))
		if not Workspace:FindFirstChild("Dino") and old.Parent then
			old.Name = "Dino"
		end
	end
	return findStaticMother()
end

-- Fades in Mother's footstep rumble (silent until you paste a SoundId; see the setup script)
local function startMotherFootsteps()
	if not motherModel or not motherModel.PrimaryPart then
		return
	end
	local sound = motherModel.PrimaryPart:FindFirstChild("Mother_Step")
	if not sound or not sound:IsA("Sound") or sound.SoundId == "" then
		return
	end
	motherFootsteps = sound
	local target = sound:GetAttribute("BaseVolume")
	if not target then
		target = sound.Volume
		sound:SetAttribute("BaseVolume", target)
	end
	sound.Volume = 0
	sound.Looped = true
	sound.Playing = true
	TweenService:Create(sound, TweenInfo.new(GameConfig.Mother.FootstepFadeInTime), { Volume = target }):Play()
end

local function stopMotherFootsteps(fadeSeconds: number?)
	if not motherFootsteps then
		return
	end
	local sound = motherFootsteps
	motherFootsteps = nil
	local s = fadeSeconds or 1
	TweenService:Create(sound, TweenInfo.new(s), { Volume = 0 }):Play()
	task.delay(s + 0.1, function()
		sound.Playing = false
	end)
end

---------------------------------------------------------------------
-- Return players to Lobby
---------------------------------------------------------------------

local function cleanupCarriedCore(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local carriedCore = character:FindFirstChild("CarriedCore")
	if carriedCore then
		carriedCore:Destroy()
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = GameConfig.Core.BaseWalkSpeed
	end
end

local function cleanupAllCarriedCores()
	for _, player in Players:GetPlayers() do
		cleanupCarriedCore(player)
	end
end

local function returnPlayersToLobby()
	if returningToLobby then
		return
	end

	returningToLobby = true

	local players = Players:GetPlayers()

	if #players == 0 then
		print("[RoundService] No players remaining. Match server can shut down.")
		return
	end

	local placeIds = GameConfig.PlaceIds

	if not placeIds then
		warn("[RoundService] GameConfig.PlaceIds is missing.")
		returningToLobby = false
		return
	end

	local lobbyPlaceId = placeIds.Lobby

	if type(lobbyPlaceId) ~= "number" or lobbyPlaceId <= 0 then
		warn("[RoundService] Invalid Lobby PlaceId:", lobbyPlaceId)
		returningToLobby = false
		return
	end

	-- Clean up the temporary carried Core before leaving.
	cleanupAllCarriedCores()

	-- TeleportService cannot be tested normally inside Roblox Studio.
	-- Instead, print what would happen.
	if RunService:IsStudio() then
		print("[RoundService] STUDIO TEST: would teleport players to Lobby")
		print("[RoundService] Lobby PlaceId:", lobbyPlaceId)

		returningToLobby = false
		return
	end

	print(string.format(
		"[RoundService] Returning %d player(s) to Lobby (PlaceId %d)",
		#players,
		lobbyPlaceId
		))

	PlayerDataService.SaveAll() -- save everyone before they leave this server

	local success, result = pcall(function()
		return TeleportService:TeleportAsync(lobbyPlaceId, players)
	end)

	if success then
		print("[RoundService] Lobby teleport initiated successfully.")
	else
		warn("[RoundService] Failed to teleport players to Lobby:", result)

		-- Allow another attempt if this server is still alive.
		returningToLobby = false

		Remotes.Notify:FireAllClients(
			"Unable to return to the lobby. Please try again.",
			"error"
		)
	end
end

---------------------------------------------------------------------
-- Carrying the Core
--
-- One player grabs the Core.
-- Everyone in the match carries a visual Core.
---------------------------------------------------------------------

local function attachCarriedCore(character: Model)
	if character:FindFirstChild("CarriedCore") then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	local carried = HatchlingProp.AttachToCarrier(character, GameConfig.Mother.EscortHeight)
	if not carried then
		warn("[RoundService] Could not build the hatchling (no HatchStage.Hatchling?). Falling back to the glowing orb.")
		local orb = Instance.new("Part")
		orb.Name = "CarriedCore"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(3, 3, 3)
		orb.Material = Enum.Material.Neon
		orb.Color = CORE_COLOR
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.Massless = true
		orb.CFrame = root.CFrame * CFrame.new(0, 5, 0)

		local light = Instance.new("PointLight")
		light.Color = CORE_COLOR
		light.Range = 18
		light.Brightness = 2
		light.Parent = orb

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = orb
		weld.Parent = orb
		orb.Parent = character
	end

	humanoid.WalkSpeed = GameConfig.Core.BaseWalkSpeed * GameConfig.Core.CarrySpeedMultiplier
end

local function attachWhenReady(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:WaitForChild("Humanoid", 5)

	if root
		and humanoid
		and state == "Carrying"
		and character.Parent
	then
		attachCarriedCore(character)
	end
end

---------------------------------------------------------------------
-- Match start
---------------------------------------------------------------------

local function startMatch()
	corePart = nil
	matchEnded = false
	returningToLobby = false

	setState("Playing")

	Workspace:SetAttribute(
		"RoundStart",
		Workspace:GetServerTimeNow()
	)

	Workspace:SetAttribute("RoundEnd", nil)

	deliverPrompt.Enabled = false

	print("[RoundService] Match started.")
end

---------------------------------------------------------------------
-- Match end
---------------------------------------------------------------------


local function endRound(deliverer: Player)
	-- Prevent duplicate delivery calls from ending the same match twice.
	if matchEnded then
		return
	end

	matchEnded = true

	setState("Ended")
	deliverPrompt.Enabled = false

	local now = Workspace:GetServerTimeNow()
	Workspace:SetAttribute("RoundEnd", now)

	local startTime =
		Workspace:GetAttribute("RoundStart")
		or now

	-------------------------------------------------------------
	-- Determine player contributions
	-------------------------------------------------------------

	local contributions = EggService.GetContributions()

	local totalDamage = 0

	for _, damage in contributions do
		totalDamage += damage
	end

	local rows = {}

	for userId, damage in contributions do
		local contributor = Players:GetPlayerByUserId(userId)

		if contributor and totalDamage > 0 then
			table.insert(rows, {
				Name = contributor.DisplayName,

				Percent = math.floor(
					damage / totalDamage * 100 + 0.5
				),

				Damage = damage,
			})
		end
	end

	table.sort(rows, function(a, b)
		return a.Damage > b.Damage
	end)

	-------------------------------------------------------------
	-- Send results to players
	-------------------------------------------------------------

	local matchTime = math.max(
		0,
		now - startTime
	)

	Remotes.RoundResults:FireAllClients({
		Seconds = matchTime,

		Deliverer = deliverer.DisplayName,

		Rows = rows,

		-- Keep this name for compatibility with
		-- your existing RoundController for now.
		RestartIn = GameConfig.Round.ResultsTime,
	})

	print(string.format(
		"[RoundService] Match over. Delivered by %s in %.0fs",
		deliverer.Name,
		matchTime
		))

	-------------------------------------------------------------
	-- IMPORTANT
	--
	-- There is NO:
	-- EggService.ResetAll()
	-- PlayerDataService.Reset()
	-- player:LoadCharacter()
	-- startRound()
	--
	-- The match is finished.
	--
	-- After the results screen, leave this server.
	-------------------------------------------------------------

	task.delay(GameConfig.Round.ResultsTime, returnPlayersToLobby)
end

---------------------------------------------------------------------
-- Release: the hatchling runs to Mother, then the match ends
---------------------------------------------------------------------

-- Detaches the deliverer's carried hatchling so it can run on its own. Returns nil if they
-- were carrying the fallback orb instead (no hatchlingTemplate was found).
-- Detaches the deliverer's hatchling so the cutscene can use it. nil if they carried the fallback orb.
local function releaseHatchlingFor(player: Player): Model?
	local character = player.Character
	local clone = character and character:FindFirstChild("CarriedCore")
	if not clone or not clone:IsA("Model") then
		return nil
	end

	clone.Name = "ReleaseHatchling" -- this also stops the carry animation
	clone:SetAttribute("DinoMode", "Release")
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	clone.Parent = Workspace
	return clone
end

local function playReleaseCutscene(player: Player)
	if releaseStarted or matchEnded then
		return
	end
	releaseStarted = true
	deliverPrompt.Enabled = false

	-- Only one hatchling stars in the scene. Everyone else's copy vanishes.
	for _, other in Players:GetPlayers() do
		if other ~= player then
			cleanupCarriedCore(other)
		end
	end

	local runner = releaseHatchlingFor(player)
	if runner then
		scaleModelTo(runner, GameConfig.Mother.ReleaseHeight)
	end

	-- The clients animate Mother and the hatchling themselves (smooth, no network jitter)
	local home = motherModel and (motherModel:GetAttribute("HomeCFrame") or motherModel:GetPivot())
	if home then
		Workspace:SetAttribute("MotherHome", home)
	end
	Workspace:SetAttribute("ReleasePadPosition", deliveryPad.Position)
	Workspace:SetAttribute("ReleaseDelivererUserId", player.UserId)
	Workspace:SetAttribute("Cutscene", "Release")
	Workspace:SetAttribute("CutsceneId", (Workspace:GetAttribute("CutsceneId") or 0) + 1)

	task.delay(RELEASE_TIME - 1.2, function()
		stopMotherFootsteps(1.2)
	end)
	task.delay(RELEASE_TIME, function()
		if runner and runner.Parent then
			runner:Destroy()
		end
		endRound(player)
	end)
end

---------------------------------------------------------------------
-- Core pickup
---------------------------------------------------------------------

local function onCorePickup(player: Player)
	if state ~= "CoreReady" then
		return
	end

	if not corePart then
		return
	end

	local root = getAliveRoot(player)

	if not root then
		return
	end

	local distance =
		(root.Position - corePart.Position).Magnitude

	if distance > GameConfig.Core.PickupRange then
		return
	end

	-------------------------------------------------------------
	-- Change state
	-------------------------------------------------------------

	setState("Carrying")
	startMotherFootsteps()

	-------------------------------------------------------------
	-- Remove the real Core from the egg
	-------------------------------------------------------------

	corePart:Destroy()
	corePart = nil

	-------------------------------------------------------------
	-- Enable delivery
	-------------------------------------------------------------

	deliverPrompt.Enabled = true

	-------------------------------------------------------------
	-- Everyone carries a visual Core
	-------------------------------------------------------------

	for _, other in Players:GetPlayers() do
		if other.Character then
			task.spawn(
				attachWhenReady,
				other.Character
			)
		end
	end

	-------------------------------------------------------------
	-- Notify everyone
	-------------------------------------------------------------

	Remotes.Notify:FireAllClients(
		player.DisplayName
			.. " grabbed the Core! Everyone is carrying it.",
		"success"
	)

	print(
		"[RoundService]",
		player.Name,
		"picked up the Core."
	)
end

---------------------------------------------------------------------
-- Core delivery
---------------------------------------------------------------------

local function onDeliver(player: Player)
	if state ~= "Carrying" then
		return
	end

	if matchEnded or releaseStarted then
		return
	end

	local root = getAliveRoot(player)

	if not root then
		return
	end

	local distance =
		(root.Position - deliveryPad.Position).Magnitude

	if distance > GameConfig.Core.DeliverRange then
		return
	end

	playReleaseCutscene(player)
end

---------------------------------------------------------------------
-- Egg broken
---------------------------------------------------------------------
-- Tells every client to play the hatch cutscene (the client reads these attributes).
---------------------------------------------------------------------
-- Hatch cutscene: players are moved to Workspace.HatchStage, then returned
---------------------------------------------------------------------
local participants = {} -- [Player] = { Character, CFrame }
local finishCurrent: (() -> ())? = nil

local function returnPlayer(player: Player)
	local saved = participants[player]
	if not saved then
		return
	end
	participants[player] = nil

	local character = player.Character
	if character and character == saved.Character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			character:PivotTo(saved.CFrame + Vector3.new(0, 2, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = false
		end
	end
end

local function startHatchCutscene(eggModel: Model, prompt: ProximityPrompt)
	local definition = EggDefinitions[eggModel:GetAttribute("EggType")]
	local hatchling = definition and definition.Hatchling

	local function finish()
		if finishCurrent == nil then
			return
		end
		finishCurrent = nil

		for player in participants do
			returnPlayer(player)
		end
		Workspace:SetAttribute("CutsceneActive", false)

		if state == "CoreReady" and prompt.Parent then
			prompt.Enabled = true
			Remotes.Notify:FireAllClients("The hatchling is free! Pick it up!", "success")
		end
	end
	finishCurrent = finish

	local stage = Workspace:FindFirstChild("HatchStage")
	local spotsFolder = stage and stage:FindFirstChild("Spots")
	local eggCenter = stage and stage:FindFirstChild("EggCenter")
	if not spotsFolder or not eggCenter or #spotsFolder:GetChildren() == 0 then
		warn("[RoundService] Workspace.HatchStage is missing or incomplete. Skipping the hatch cutscene.")
		finish()
		return
	end

	Workspace:SetAttribute("HatchSpecies", if hatchling then hatchling.Species else "Hatchling")
	Workspace:SetAttribute("HatchRarity", if hatchling then hatchling.Rarity else "Common")
	Workspace:SetAttribute("HatchStagePosition", eggCenter.Position)
	Workspace:SetAttribute("CutsceneActive", true)
	Workspace:SetAttribute("Cutscene", "Hatch")
	-- The id changes last, so clients always see the other values first
	Workspace:SetAttribute("CutsceneId", (Workspace:GetAttribute("CutsceneId") or 0) + 1)

	-- Clients fade to black first, then everyone is moved onto the stage
	task.delay(TELEPORT_DELAY, function()
		if finishCurrent ~= finish then
			return
		end
		local spots = spotsFolder:GetChildren()
		table.sort(spots, function(a, b)
			return a.Name < b.Name
		end)

		local index = 0
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = getAliveRoot(player)
			if character and root then
				index += 1
				local spot = spots[(index - 1) % #spots + 1]
				participants[player] = { Character = character, CFrame = character:GetPivot() }
				root.Anchored = true
				character:PivotTo(spot.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end)

	task.delay(CUTSCENE_TIME, finish)
end

-- A player skipped: they go back now. If everyone skipped, the cutscene ends early.
local function onHatchSkip(player: Player)
	if not participants[player] then
		return
	end
	returnPlayer(player)
	if next(participants) == nil and finishCurrent then
		finishCurrent()
	end
end

local function onPlayerLeft(player: Player)
	local wasIn = participants[player] ~= nil
	participants[player] = nil
	if wasIn and next(participants) == nil and finishCurrent then
		finishCurrent()
	end
end
-- Called by EggService once the egg shell is gone
-- and the Core is exposed.
local function onEggBroken(
	_eggId: string,
	eggModel: Model
)
	if state ~= "Playing" then
		return
	end

	if matchEnded then
		return
	end

	local core =
		eggModel:FindFirstChild("Core")

	if not core or not core:IsA("BasePart") then
		warn(
			"[RoundService] The egg model has no part named 'Core'"
		)

		return
	end

	-------------------------------------------------------------
	-- Store the Core
	-------------------------------------------------------------

	corePart = core

	-------------------------------------------------------------
	-- Create pickup prompt
	-------------------------------------------------------------

	local prompt =
		Instance.new("ProximityPrompt")

	prompt.Name = "CorePickupPrompt"
	prompt.ActionText = "Pick up the hatchling"
	prompt.ObjectText = "Hatchling"

	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 30

	prompt.RequiresLineOfSight = false

	prompt.Enabled = false -- switched on after the hatch cutscene
	prompt.Parent = core

	prompt.Triggered:Connect(onCorePickup)

	-------------------------------------------------------------
	-- Update match state
	-------------------------------------------------------------

	setState("CoreReady")

	-------------------------------------------------------------
	-- Tell players
	-------------------------------------------------------------

	-- The glowing orb becomes a living hatchling
	pcall(HatchlingProp.DressFieldCore, core, GameConfig.Mother.FieldHeight)
	startHatchCutscene(eggModel, prompt)

	print(
		"[RoundService] Core revealed from egg:",
		_eggId
	)
end

---------------------------------------------------------------------
-- Player monitoring
---------------------------------------------------------------------

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)

		-- If the team is already carrying the Core,
		-- newly respawned players also receive a visual Core.
		if state == "Carrying" then
			task.spawn(
				attachWhenReady,
				character
			)
		end

	end)
end

---------------------------------------------------------------------
-- Initialize
---------------------------------------------------------------------

function RoundService.Init()
	Remotes =
		ReplicatedStorage:WaitForChild("Remotes")

	motherModel = findMother()

	local stage = Workspace:FindFirstChild("HatchStage")
	hatchlingTemplate = stage and stage:FindFirstChild("Hatchling", true)
	if not hatchlingTemplate then
		warn("[RoundService] HatchStage.Hatchling not found. Escort will fall back to the glowing orb.")
	end

	-------------------------------------------------------------
	-- Delivery setup
	-------------------------------------------------------------

	local spot =
		Workspace
		:WaitForChild("Map")
		:WaitForChild("DeliverySpot")

	deliveryPad =
		spot:WaitForChild("Pad")

	deliverPrompt =
		deliveryPad:WaitForChild("DeliverPrompt")

	deliverPrompt.Triggered:Connect(onDeliver)

	-- Hatch cutscene: skipping, and players leaving mid-cutscene
	local skipRemote = Instance.new("RemoteEvent")
	skipRemote.Name = "HatchSkip"
	skipRemote.Parent = Remotes
	skipRemote.OnServerEvent:Connect(onHatchSkip)
	Players.PlayerRemoving:Connect(onPlayerLeft)

	-------------------------------------------------------------
	-- Listen for egg completion
	-------------------------------------------------------------

	EggService.OnEggBroken(onEggBroken)

	-------------------------------------------------------------
	-- Watch players
	-------------------------------------------------------------

	Players.PlayerAdded:Connect(watchPlayer)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	-------------------------------------------------------------
	-- Start this match
	-------------------------------------------------------------

	startMatch()

	print(
		string.format(
			"[%s] Init OK - Match started",
			script.Name
		)
	)
end

return RoundService