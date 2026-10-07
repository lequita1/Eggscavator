-- EggProgress (client): the main progress bar, "Layer N cleared" banners, and a pulse on the last patches.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggDefinitions = require(Shared:WaitForChild("EggDefinitions"))

local EGG_TYPE = "Stonehatch"
local PULSE_AT = 10 -- the last this-many closed patches pulse (Roblox allows 31 Highlights)
local BAR_WIDTH = 420
local BANNER_HOLD = 3 -- seconds the "layer cleared" banner stays up
local GOLD = Color3.fromRGB(255, 200, 90)

local definition = EggDefinitions[EGG_TYPE]
local layers = definition.Layers
local layerCount = #layers

-- Where each layer sits on the bar, sized by its HP (the same weights the server uses for progress)
local totalHP = 0
for _, layer in layers do
	totalHP += layer.HP
end
local segStart, segEnd = {}, {}
do
	local acc = 0
	for k, layer in layers do
		segStart[k] = acc / totalHP
		acc += layer.HP
		segEnd[k] = acc / totalHP
	end
end

---------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "EggProgress"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Enabled = false
gui.Parent = playerGui

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, 10)
root.Size = UDim2.fromOffset(BAR_WIDTH, 58)
root.BackgroundTransparency = 1
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function label(parent, y, h, size, font, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = align
	l.TextStrokeTransparency = 0.5
	l.Text = ""
	l.Parent = parent
	return l
end
local title = label(root, 0, 16, 14, Enum.Font.GothamBlack, Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
local chapter = label(root, 0, 16, 13, Enum.Font.GothamBold, Color3.fromRGB(255, 220, 150), Enum.TextXAlignment.Right)
local hint = label(root, 40, 16, 13, Enum.Font.GothamBold, GOLD, Enum.TextXAlignment.Center)

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(0, 19)
track.Size = UDim2.new(1, 0, 0, 18)
track.BackgroundColor3 = Color3.fromRGB(24, 18, 12)
track.BorderSizePixel = 0
track.ClipsDescendants = true
track.Parent = root
Instance.new("UICorner", track).CornerRadius = UDim.new(0, 9)
local trackStroke = Instance.new("UIStroke", track)
trackStroke.Color = Color3.fromRGB(10, 8, 6)
trackStroke.Thickness = 2.5

local fills = {}
for k, layer in layers do
	local seg = Instance.new("Frame")
	seg.Position = UDim2.fromScale(segStart[k], 0)
	seg.Size = UDim2.fromScale(segEnd[k] - segStart[k], 1)
	seg.BackgroundColor3 = layer.Color:Lerp(Color3.new(0, 0, 0), 0.65)
	seg.BorderSizePixel = 0
	seg.Parent = track

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = layer.Color:Lerp(Color3.new(1, 1, 1), 0.15)
	fill.BorderSizePixel = 0
	fill.Parent = seg
	fills[k] = fill

	if k < layerCount then
		local tick = Instance.new("Frame")
		tick.Position = UDim2.new(segEnd[k], -1, 0, 0)
		tick.Size = UDim2.new(0, 2, 1, 0)
		tick.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
		tick.BorderSizePixel = 0
		tick.ZIndex = 3
		tick.Parent = track
	end
end

---------------------------------------------------------------------
-- "Layer N cleared" banner
---------------------------------------------------------------------
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.2, 0)
banner.Size = UDim2.fromOffset(620, 90)
banner.BackgroundTransparency = 1
banner.Parent = gui
local bannerTitle = label(banner, 0, 46, 38, Enum.Font.GothamBlack, GOLD, Enum.TextXAlignment.Center)
local bannerSub = label(banner, 46, 30, 20, Enum.Font.GothamBold, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
bannerTitle.TextStrokeTransparency = 1
bannerSub.TextStrokeTransparency = 1
bannerTitle.TextTransparency = 1
bannerSub.TextTransparency = 1

local Sounds
task.spawn(function()
	local ui = script.Parent:WaitForChild("UI", 15)
	local module = ui and ui:FindFirstChild("Sounds")
	if module then
		local ok, result = pcall(require, module)
		if ok then
			Sounds = result
			pcall(function()
				Sounds.Init() -- safe to call twice
			end)
		end
	end
end)

local bannerToken = 0
local function showBanner(titleText: string, subText: string)
	bannerToken += 1
	local mine = bannerToken
	bannerTitle.Text = titleText
	bannerSub.Text = subText
	for _, l in { bannerTitle, bannerSub } do
		l.TextTransparency = 1
		l.TextStrokeTransparency = 1
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
	end
	if Sounds then
		pcall(Sounds.Play, "Milestone", 1)
	end
	task.delay(BANNER_HOLD, function()
		if mine ~= bannerToken then
			return -- a newer banner replaced this one
		end
		for _, l in { bannerTitle, bannerSub } do
			TweenService:Create(l, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------------
-- The last closed patches pulse (shown through the egg, so you can find them)
---------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "EggProgressFX"
fxFolder.Parent = Workspace
local pulses = {} -- [patch index] = Highlight
local lastLeftKey = ""

local function clearPulses()
	for index, highlight in pulses do
		highlight:Destroy()
		pulses[index] = nil
	end
end

local function updatePulses(egg: Model, layerString: string)
	local want = {}
	for i = 1, #layerString do
		if (tonumber(string.sub(layerString, i, i)) or 1) <= layerCount then
			want[i] = true
		end
	end

	-- EggView keeps the visible patch parts in Workspace.EggView.<egg name>
	local view = Workspace:FindFirstChild("EggView")
	local folder = view and view:FindFirstChild(egg.Name)
	if not folder then
		return
	end
	local parts = {}
	for _, part in folder:GetChildren() do
		local index = part:GetAttribute("Index")
		if type(index) == "number" and want[index] and part:IsA("BasePart") and part.CanQuery then
			parts[index] = part
		end
	end

	local names = {}
	for index in want do
		local part = parts[index]
		local highlight = pulses[index]
		if part then
			if not highlight then
				highlight = Instance.new("Highlight")
				highlight.FillColor = GOLD
				highlight.OutlineColor = Color3.new(1, 1, 1)
				highlight.FillTransparency = 0.6
				highlight.OutlineTransparency = 0
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Parent = fxFolder
				pulses[index] = highlight
			end
			highlight.Adornee = part
			table.insert(names, part.Name)
		elseif highlight then
			highlight.Adornee = nil -- the part was swapped for the next layer; found again next refresh
		end
	end
	for index, highlight in pulses do
		if not want[index] then
			highlight:Destroy()
			pulses[index] = nil
		end
	end

	-- Prints which patches are left, so any you cannot reach can be reported
	table.sort(names)
	local key = table.concat(names, ", ")
	if key ~= lastLeftKey and #names > 0 and #names <= 6 then
		print("[EggProgress] Left to open: " .. key)
	end
	lastLeftKey = key
end

---------------------------------------------------------------------
-- Refresh (5 times a second) and smooth drawing (every frame)
---------------------------------------------------------------------
local target, shown = 0, 0
local cleared = nil -- layers cleared the last time we looked (nil = not seen yet, so no banner for late joiners)

local function findEgg(): Model?
	local eggs = Workspace:FindFirstChild("Eggs")
	if not eggs then
		return nil
	end
	for _, model in eggs:GetChildren() do
		if model:IsA("Model") and type(model:GetAttribute("PatchLayer")) == "string" then
			return model
		end
	end
	return nil
end

local function refresh()
	local camera = Workspace.CurrentCamera
	if camera then
		uiScale.Scale = math.clamp(camera.ViewportSize.X / 620, 0.55, 1)
	end

	local egg = findEgg()
	if not egg or egg:GetAttribute("Broken") then
		gui.Enabled = false
		clearPulses()
		return
	end
	local layerString = egg:GetAttribute("PatchLayer")

	local maxDurability = egg:GetAttribute("MaxDurability") or 1
	local durability = egg:GetAttribute("Durability") or maxDurability
	target = math.clamp(1 - durability / maxDurability, 0, 1)
	if not gui.Enabled then
		shown = target -- first look: no sweep from zero
		gui.Enabled = true
	end

	-- Layers everyone has finished = the lowest layer any patch is still on, minus one
	local lowest, open = layerCount + 1, 0
	for i = 1, #layerString do
		local digit = tonumber(string.sub(layerString, i, i)) or 1
		lowest = math.min(lowest, digit)
		if digit > layerCount then
			open += 1
		end
	end
	local clearedNow = math.clamp(lowest - 1, 0, layerCount)
	if cleared ~= nil and clearedNow > cleared and clearedNow < layerCount then
		local nextLayer = layers[clearedNow + 1]
		showBanner(string.format("LAYER %d CLEARED", clearedNow), nextLayer.Message or nextLayer.Name)
	end
	cleared = clearedNow

	local current = math.min(clearedNow + 1, layerCount)
	chapter.Text = string.format("Layer %d of %d  -  %s", current, layerCount, layers[current].Name)

	local remaining = #layerString - open
	if remaining > 0 and remaining <= PULSE_AT then
		hint.Text = if remaining == 1 then "1 patch left to open!" else string.format("%d patches left to open!", remaining)
		updatePulses(egg, layerString)
	else
		hint.Text = ""
		clearPulses()
	end
end

local sinceRefresh = 1
local failedOnce = false
RunService.RenderStepped:Connect(function(dt)
	shown += (target - shown) * math.min(1, dt * 6)
	title.Text = string.format("THE EGG  %d%%", math.floor(shown * 100))
	for k, fill in fills do
		fill.Size = UDim2.fromScale(math.clamp((shown - segStart[k]) / (segEnd[k] - segStart[k]), 0, 1), 1)
	end
	local fade = 0.55 + 0.3 * math.sin(os.clock() * 5)
	for _, highlight in pulses do
		highlight.FillTransparency = fade
	end

	sinceRefresh += dt
	if sinceRefresh >= 0.2 then
		sinceRefresh = 0
		local ok, err = pcall(refresh)
		if not ok and not failedOnce then
			failedOnce = true
			warn("[EggProgress] refresh failed: " .. tostring(err))
		end
	end
end)

print("[EggProgress] Init OK")