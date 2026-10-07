local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EggDefinitions = require(ReplicatedStorage.Shared.EggDefinitions)

local EGG_TYPE = "Stonehatch" -- which egg every pad spawns (for now)
local PAD_NAME_PATTERN = "^EggPad_(%d+)$"
local POWER_BONUS_PER_STEP = 0.25 -- damage multiplier: 1 + 0.25 * (toolPower - hardness), max 1.75
local POWER_BONUS_MAX = 1.75

local EggService = {}

-- eggStates[eggId] = see createState
local eggStates = {}
local eggsFolder: Folder -- Workspace.Eggs, assigned in Init
local testFolder: Folder? -- Workspace.EggTests (simulator eggs), made on demand
local Remotes: Folder -- assigned in Init
local brokenHandlers = {} -- functions called when an egg has broken and its Core is exposed
local patchCache = {} -- [eggType] = { Count, Patches = { [index] = { Rel, Dir, Radius } }, LayerStep }

---------------------------------------------------------------------
-- Patch geometry (read once from ReplicatedStorage.EggPatches.<eggType>)
---------------------------------------------------------------------
local function loadPatches(eggType: string)
	local cached = patchCache[eggType]
	if cached then
		return cached
	end

	local root = ReplicatedStorage:FindFirstChild("EggPatches")
	local folder = root and root:FindFirstChild(eggType)
	if not folder then
		warn("[EggService] Missing ReplicatedStorage.EggPatches." .. eggType)
		return nil
	end
	local shellCFrame = folder:GetAttribute("ShellCFrame")
	if typeof(shellCFrame) ~= "CFrame" then
		warn("[EggService] EggPatches." .. eggType .. " has no ShellCFrame attribute (re-run the Phase 3 builder)")
		return nil
	end

	local patches, count = {}, 0
	for _, part in folder:GetChildren() do
		local index = part:GetAttribute("Index")
		if part:IsA("BasePart") and type(index) == "number" then
			local rel = part:GetAttribute("SurfaceRel") or shellCFrame:PointToObjectSpace(part.Position) -- offset from the Shell center, in Shell space
			patches[index] = {
				Rel = rel,
				Dir = if rel.Magnitude > 0.001 then rel.Unit else Vector3.yAxis,
				Radius = part:GetAttribute("SurfaceRadius") or part.Size.Magnitude / 2, Band = part:GetAttribute("Band"),
			}
			count += 1
		end
	end

	local expected = folder:GetAttribute("PatchCount")
	if count == 0 or (type(expected) == "number" and expected ~= count) then
		warn(string.format("[EggService] EggPatches.%s: found %d patches, folder says %s", eggType, count, tostring(expected)))
		return nil
	end
	for i = 1, count do
		if not patches[i] then
			warn(string.format("[EggService] EggPatches.%s is missing patch Index %d", eggType, i))
			return nil
		end
	end

	cached = { Count = count, Patches = patches, LayerStep = folder:GetAttribute("LayerStep") or 0.05 }
	patchCache[eggType] = cached
	return cached
end

local function layerScale(state, layer: number): number
	return 1 - (math.min(layer, state.LayerCount) - 1) * state.LayerStep
end

---------------------------------------------------------------------
-- Derived values
---------------------------------------------------------------------

-- Stage 0 = untouched. Stage N starts when durability fraction <= StageThresholds[N].
local function computeStage(definition, durability: number): number
	local fraction = durability / definition.MaxDurability
	local stage = 0
	for index, threshold in definition.StageThresholds do
		if fraction <= threshold then
			stage = index
		end
	end
	return stage
end

-- 0..1: how close the egg is to giving way. Average progress of the OpenTarget most-advanced
-- patches, so it is exactly 1 when OpenTarget patches are fully open, and never goes down.
local function computeProgress(state): number
	if state.OpenCount >= state.OpenTarget then
		return 1
	end
	local count = state.PatchSet.Count
	local layers = state.Definition.Layers
	local values = table.create(count)
	for i = 1, count do
		local layer = state.Layer[i]
		if layer > state.LayerCount then
			values[i] = 1
		else
			local done = state.Cum[layer - 1] + (layers[layer].HP - state.HP[i])
			values[i] = done / state.TotalHP
		end
	end
	table.sort(values, function(a, b)
		return a > b
	end)
	local sum = 0
	for i = 1, state.OpenTarget do
		sum += values[i]
	end
	return math.min(sum / state.OpenTarget, 0.9999)
end

-- PatchLayer: one digit per patch (1..LayerCount, LayerCount+1 = open).
-- PatchHP: one digit per patch (1..9 = HP fraction of the current layer rounded up, 0 = open).
local function encodePatches(state)
	local count = state.PatchSet.Count
	local layerDigits, hpDigits = table.create(count), table.create(count)
	local layers = state.Definition.Layers
	for i = 1, count do
		local layer = state.Layer[i]
		layerDigits[i] = tostring(layer)
		if layer > state.LayerCount then
			hpDigits[i] = "0"
		else
			local fraction = state.HP[i] / layers[layer].HP
			hpDigits[i] = tostring(math.clamp(math.ceil(fraction * 9), 1, 9))
		end
	end
	return table.concat(layerDigits), table.concat(hpDigits)
end

local function refreshAttributes(state)
	local model = state.Model
	local definition = state.Definition
	local progress = computeProgress(state)
	state.Durability = definition.MaxDurability * (1 - progress)

	local layerString, hpString = encodePatches(state)
	model:SetAttribute("Durability", state.Durability)
	model:SetAttribute("Stage", computeStage(definition, state.Durability))
	model:SetAttribute("OpenCount", state.OpenCount)
	model:SetAttribute("PatchLayer", layerString)
	model:SetAttribute("PatchHP", hpString)
end

---------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------
-- Layer sweep: when LayerSweep of all patches are past layer k, the stragglers break through to k + 1.
-- Returns k if a sweep happened, otherwise nil. Runs at most once per layer.
local function sweepLayer(state, k: number): number?
	local sweep = state.Definition.LayerSweep
	if not sweep or state.SweptUpTo >= k then
		return nil
	end
	local count = state.PatchSet.Count
	local past = 0
	for i = 1, count do
		if state.Layer[i] > k then
			past += 1
		end
	end
	if past / count < sweep - 1e-9 then
		return nil
	end
	state.SweptUpTo = k
	local nextLayer = k + 1
	for i = 1, count do
		if state.Layer[i] <= k then
			state.Layer[i] = nextLayer
			if nextLayer > state.LayerCount then
				state.HP[i] = 0
				state.OpenCount += 1
			else
				state.HP[i] = state.Definition.Layers[nextLayer].HP
			end
		end
	end
	return k
end

local function spawnEgg(pad: BasePart?, eggId: string, eggType: string, testCenter: Vector3?, onBroken)
	local definition = EggDefinitions[eggType]
	local template = ServerStorage.Assets.Eggs:FindFirstChild(eggType)
	local patchSet = loadPatches(eggType)
	if not definition or not template or not patchSet or not definition.Layers then
		warn(string.format("[EggService] Cannot spawn '%s': missing definition, Layers, template or patches", eggType))
		return nil
	end

	local model = template:Clone()
	model.Name = eggId

	-- Attributes replicate automatically, so clients can read them for cracks and UI.
	model:SetAttribute("EggId", eggId)
	model:SetAttribute("EggType", eggType)
	model:SetAttribute("MaxDurability", definition.MaxDurability)
	model:SetAttribute("Durability", definition.MaxDurability)
	model:SetAttribute("Stage", 0)
	model:SetAttribute("PatchCount", patchSet.Count)

	-- Place the egg by its visual center, even if the model's pivot is off-center.
	local boxCFrame, boundsSize = model:GetBoundingBox()
	local pivotOffset = model:GetPivot().Position - boxCFrame.Position
	local desiredCenter
	if testCenter then
		desiredCenter = testCenter
	else
		desiredCenter = (pad :: BasePart).Position + Vector3.new(0, (pad :: BasePart).Size.Y / 2 + boundsSize.Y / 2, 0)
	end
	model:PivotTo(CFrame.new(desiredCenter + pivotOffset))

	local shell = model:FindFirstChild("Shell")
	if not (shell and shell:IsA("BasePart")) then
		warn("[EggService] Template has no Shell part")
		model:Destroy()
		return nil
	end

	local layerCount = #definition.Layers
	local state = {
		Model = model,
		Definition = definition,
		Pad = pad,
		EggId = eggId,
		EggType = eggType,
		Test = testCenter ~= nil,
		OnBroken = onBroken,
		PatchSet = patchSet,
		ShellCFrame = shell.CFrame, -- the egg never moves, so this is the layer-scaling frame
		LayerStep = patchSet.LayerStep,
		LayerCount = layerCount,
		Layer = table.create(patchSet.Count, 1), -- [patch] = current layer (LayerCount + 1 = open)
		HP = table.create(patchSet.Count, definition.Layers[1].HP),
		OpenCount = 0,
		OpenTarget = math.max(1, math.ceil(definition.OpenToHatch * patchSet.Count - 1e-6)),
		Cum = { [0] = 0 }, -- Cum[k] = total HP of layers 1..k (for progress)
		TotalHP = 0,
		Durability = definition.MaxDurability,
		Contributions = {}, -- [userId] = total damage dealt
		SweptUpTo = 0, -- highest layer already swept
		Broken = false,
	}
	-- Bands nobody can reach start already open and count towards OpenCount
	for i, patch in patchSet.Patches do
		if definition.SkipBands and table.find(definition.SkipBands, patch.Band) then
			state.Layer[i] = layerCount + 1
			state.HP[i] = 0
			state.OpenCount += 1
		end
	end
	for k, layer in definition.Layers do
		state.TotalHP += layer.HP
		state.Cum[k] = state.TotalHP
	end

	if testCenter then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		if not testFolder then
			testFolder = Instance.new("Folder")
			testFolder.Name = "EggTests"
			testFolder.Parent = Workspace
		end
		model.Parent = testFolder
	else
		model.Parent = eggsFolder
	end

	eggStates[eggId] = state
	refreshAttributes(state)
	return state
end

local function breakEgg(state)
	state.Broken = true
	local model = state.Model
	model:SetAttribute("Broken", true)

	-- Clients play the shake and burst (test eggs stay silent)
	if not state.Test then
		Remotes.EggBroken:FireAllClients(state.EggId, model:GetPivot().Position)
	end

	-- After the shake, the shell is removed and the Core is left standing
	task.delay(state.Definition.BreakShakeDuration, function()
		if not model.Parent then
			return -- the egg was reset before the shake finished
		end
		local shell = model:FindFirstChild("Shell")
		if shell then
			shell:Destroy()
		end
		model:SetAttribute("Revealed", true)
		if state.Test then
			if state.OnBroken then
				task.spawn(state.OnBroken, state.EggId, model)
			end
		else
			for _, handler in brokenHandlers do
				task.spawn(handler, state.EggId, model)
			end
		end
	end)

	print(string.format("[EggService] %s broke.", state.EggId))
end

---------------------------------------------------------------------
-- Public API (Section 7 contract)
---------------------------------------------------------------------

-- Register a function(eggId, eggModel) to run when a broken egg's Core is exposed.
function EggService.OnEggBroken(handler)
	table.insert(brokenHandlers, handler)
end

-- Returns the egg's Model if the egg exists and is not broken, otherwise nil.
function EggService.GetEggModel(eggId: string): Model?
	local state = eggStates[eggId]
	if not state or state.Broken then
		return nil
	end
	return state.Model
end

-- Total damage dealt per player across all real eggs: { [userId] = damage }
function EggService.GetContributions()
	local totals = {}
	for _, state in eggStates do
		if not state.Test then
			for userId, damage in state.Contributions do
				totals[userId] = (totals[userId] or 0) + damage
			end
		end
	end
	return totals
end

-- Removes every real egg (and any leftover Core) and spawns fresh ones. Used between rounds.
function EggService.ResetAll()
	local toRespawn = {}
	for eggId, state in eggStates do
		if not state.Test then
			table.insert(toRespawn, { Pad = state.Pad, EggId = eggId, EggType = state.EggType })
			if state.Model.Parent then
				state.Model:Destroy()
			end
			eggStates[eggId] = nil
		end
	end
	for _, info in toRespawn do
		spawnEgg(info.Pad, info.EggId, info.EggType)
	end
end

-- What ToolService needs to validate a hit on one patch. Nil if the egg is missing or broken.
-- Center and Radius are world values for the patch's CURRENT layer.
function EggService.GetPatchInfo(eggId: string, patchIndex: number)
	local state = eggStates[eggId]
	if not state or state.Broken then
		return nil
	end
	local patch = state.PatchSet.Patches[patchIndex]
	if not patch then
		return nil
	end
	local layer = state.Layer[patchIndex]
	local scale = layerScale(state, layer)
	local info = {
		Index = patchIndex,
		Layer = layer,
		Open = layer > state.LayerCount,
		Center = state.ShellCFrame:PointToWorldSpace(patch.Rel * scale),
		Radius = patch.Radius * scale,
	}
	if not info.Open then
		local def = state.Definition.Layers[layer]
		info.Hardness = def.Hardness
		info.LayerName = def.Name
		info.HP = state.HP[patchIndex]
		info.MaxHP = def.HP
	end
	return info
end


-- The ONLY way egg progress changes. Server code calls this, never the client.
--   amount = the tool's raw damage (after upgrades), power = the tool's Power.
-- Returns nil for a bad/closed patch or a missing/broken egg.
-- Returns { TooHard = true, Required, LayerName, Layer } if the tool is too weak for the layer.
-- Otherwise { Applied, PatchIndex, LayerBefore, LayerAfter, HPFraction, PatchBroken, PatchOpen,
--             Durability, Stage, Broken }.
function EggService.ApplyPatchDamage(eggId: string, patchIndex: any, amount: any, power: any, player: Player?)
	local state = eggStates[eggId]
	if not state or state.Broken then
		return nil
	end
	if type(patchIndex) ~= "number" or patchIndex % 1 ~= 0 or patchIndex < 1 or patchIndex > state.PatchSet.Count then
		return nil
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return nil
	end
	if type(power) ~= "number" or power ~= power then
		return nil
	end

	local layer = state.Layer[patchIndex]
	if layer > state.LayerCount then
		return nil -- already open
	end
	local layerDef = state.Definition.Layers[layer]
	if power < layerDef.Hardness then
		return { TooHard = true, Required = layerDef.Hardness, LayerName = layerDef.Name, Layer = layer }
	end

	local multiplier = math.min(1 + POWER_BONUS_PER_STEP * (power - layerDef.Hardness), POWER_BONUS_MAX)
	local applied = math.min(amount * multiplier, state.HP[patchIndex])
	state.HP[patchIndex] -= applied

	if player then
		local userId = player.UserId
		state.Contributions[userId] = (state.Contributions[userId] or 0) + applied
	end

	local patchBroken = false
	if state.HP[patchIndex] <= 1e-6 then
		patchBroken = true
		local nextLayer = layer + 1
		state.Layer[patchIndex] = nextLayer
		if nextLayer > state.LayerCount then
			state.HP[patchIndex] = 0
			state.OpenCount += 1
		else
			state.HP[patchIndex] = state.Definition.Layers[nextLayer].HP
		end
	end

	refreshAttributes(state)

	local sweptLayer = nil
	if patchBroken then
		sweptLayer = sweepLayer(state, layer)
		if sweptLayer then
			refreshAttributes(state) -- the sweep changed many patches
		end
	end

	local layerAfter = state.Layer[patchIndex]
	local patchOpen = layerAfter > state.LayerCount
	local hpFraction = 0
	if not patchOpen then
		hpFraction = state.HP[patchIndex] / state.Definition.Layers[layerAfter].HP
	end

	local broken = false
	if state.OpenCount >= state.OpenTarget then
		broken = true
		breakEgg(state)
	end

	return {
		Applied = applied,
		PatchIndex = patchIndex,
		LayerBefore = layer,
		LayerAfter = layerAfter,
		HPFraction = hpFraction,
		PatchBroken = patchBroken,
		PatchOpen = patchOpen,
		LayerSwept = sweptLayer,
		Durability = state.Durability,
		Stage = state.Model:GetAttribute("Stage"),
		Broken = broken,
	}
end

---------------------------------------------------------------------
-- Test support (used by the EggSim script; real eggs never use these)
---------------------------------------------------------------------
function EggService.SpawnTestEgg(eggId: string, position: Vector3, onBroken)
	if eggStates[eggId] then
		warn("[EggService] Test egg already exists: " .. eggId)
		return nil
	end
	local state = spawnEgg(nil, eggId, EGG_TYPE, position, onBroken)
	return state and state.Model
end

function EggService.RemoveEgg(eggId: string)
	local state = eggStates[eggId]
	if state then
		if state.Model.Parent then
			state.Model:Destroy()
		end
		eggStates[eggId] = nil
	end
end

function EggService.Init()
	Remotes = ReplicatedStorage:WaitForChild("Remotes")
	eggsFolder = Workspace:WaitForChild("Eggs")
	local eggField = Workspace:WaitForChild("Map"):WaitForChild("EggField")

	local spawned = 0
	for _, child in eggField:GetChildren() do
		local padNumber = child.Name:match(PAD_NAME_PATTERN)
		if padNumber and child:IsA("BasePart") then
			if spawnEgg(child, "Egg_" .. padNumber, EGG_TYPE) then
				spawned += 1
			end
		end
	end

	print(string.format("[EggService] Init OK (%d egg(s) spawned)", spawned))
end

return EggService