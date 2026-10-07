-- LayerHUD (client): shows the layer of the patch under your aim, its health, and whether your
-- held tool can break it. With nothing under the aim it shows how much of the egg is open.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggDefinitions = require(Shared:WaitForChild("EggDefinitions"))
local ToolDefinitions = require(Shared:WaitForChild("ToolDefinitions"))
local EggView = require(script.Parent:WaitForChild("Controllers"):WaitForChild("EggView"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local POSITION = UDim2.new(0, 14, 0.42, 0) -- move the panel here
local SHOW_RANGE = 200 -- studs from the camera to the egg (overview only)
local STICKY = 0.5 -- seconds the last aimed patch stays up after the aim leaves it
local GOLD = Color3.fromRGB(255, 200, 90)
local OK_COLOR = Color3.fromRGB(150, 235, 150)
local BAD_COLOR = Color3.fromRGB(255, 110, 110)
local NEUTRAL = Color3.fromRGB(220, 200, 170)

-- power -> tool name, for "Needs a Pickaxe or better"
local toolNameByPower = {}
do
	local ids = {}
	for id in ToolDefinitions do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return ToolDefinitions[a].ShopOrder < ToolDefinitions[b].ShopOrder
	end)
	for _, id in ids do
		local d = ToolDefinitions[id]
		if not toolNameByPower[d.Power] then
			toolNameByPower[d.Power] = d.DisplayName
		end
	end
end

---------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LayerHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(230, 90)
panel.Position = POSITION
panel.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
panel.BackgroundTransparency = 0.2
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", panel)
stroke.Thickness = 2
stroke.Color = GOLD

local function label(y, h, font, size, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 10, 0, y)
	l.Size = UDim2.new(1, -20, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = panel
	return l
end
local top = label(6, 14, Enum.Font.GothamBold, 12, Color3.fromRGB(255, 220, 150))
local name = label(21, 22, Enum.Font.GothamBlack, 19, Color3.new(1, 1, 1))
local hint = label(45, 16, Enum.Font.GothamBold, 12, NEUTRAL)

local barBack = Instance.new("Frame")
barBack.Position = UDim2.new(0, 10, 1, -16)
barBack.Size = UDim2.new(1, -20, 0, 8)
barBack.BackgroundColor3 = Color3.fromRGB(20, 14, 8)
barBack.Parent = panel
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(1, 1)
bar.BorderSizePixel = 0
bar.Parent = barBack
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

---------------------------------------------------------------------
-- What to show
---------------------------------------------------------------------
local function heldPower(): number?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("ToolId") then
		return tool:GetAttribute("Power") or 1
	end
	return nil
end

-- The patch under the aim: its layer, its health, and whether the held tool can break it.
local function aimedInfo()
	local eggId, _, patchIndex = EggView.GetAim()
	if not eggId then
		return nil
	end
	local eggs = Workspace:FindFirstChild("Eggs")
	local model = eggs and eggs:FindFirstChild(eggId)
	if not model then
		return nil
	end
	local layerString = model:GetAttribute("PatchLayer")
	local hpString = model:GetAttribute("PatchHP")
	if type(layerString) ~= "string" or type(hpString) ~= "string" then
		return nil
	end
	local definition = EggDefinitions[model:GetAttribute("EggType")]
	local layers = definition and definition.Layers
	local layer = tonumber(string.sub(layerString, patchIndex, patchIndex))
	local digit = tonumber(string.sub(hpString, patchIndex, patchIndex))
	local layerDef = layers and layer and layers[layer]
	if not layerDef then
		return nil
	end

	local power = heldPower()
	local hintText, hintColor
	if power == nil then
		hintText, hintColor = "Hold a tool to dig", NEUTRAL
	elseif power >= layerDef.Hardness then
		hintText, hintColor = "Your tool can break this", OK_COLOR
	else
		hintText = string.format("Needs a %s or better", toolNameByPower[layerDef.Hardness] or "stronger tool")
		hintColor = BAD_COLOR
	end

	return {
		Top = string.format("LAYER %d / %d", layer, #layers),
		Name = layerDef.Name,
		Hint = hintText,
		HintColor = hintColor,
		BarColor = layerDef.Color:Lerp(Color3.new(1, 1, 1), 0.3),
		Progress = math.clamp((digit or 9) / 9, 0, 1),
	}
end

-- Nothing under the aim: how open the nearest egg is.
local function overviewInfo()
	local camera = Workspace.CurrentCamera
	local eggs = Workspace:FindFirstChild("Eggs")
	if not camera or not eggs then
		return nil
	end
	local best, bestDist = nil, SHOW_RANGE
	for _, model in eggs:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("PatchCount") and not model:GetAttribute("Broken") then
			local dist = (model:GetPivot().Position - camera.CFrame.Position).Magnitude
			if dist < bestDist then
				best, bestDist = model, dist
			end
		end
	end
	local definition = best and EggDefinitions[best:GetAttribute("EggType")]
	if not best or not definition then
		return nil
	end
	local patchCount = best:GetAttribute("PatchCount")
	local target = math.max(1, math.ceil(definition.OpenToHatch * patchCount - 1e-6))
	local progress = math.clamp((best:GetAttribute("OpenCount") or 0) / target, 0, 1)
	return {
		Top = "THE EGG",
		Name = string.format("%d%% open", math.floor(progress * 100)),
		Hint = "Aim at a patch to see its layer",
		HintColor = NEUTRAL,
		BarColor = GOLD,
		Progress = progress,
	}
end

local lastAimed, lastAimedAt = nil, 0
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0

	local now = os.clock()
	local info = aimedInfo()
	if info then
		lastAimed, lastAimedAt = info, now
	elseif lastAimed and now - lastAimedAt < STICKY then
		info = lastAimed
	else
		info = nil 
	end

	if not info then
		gui.Enabled = false
		return
	end
	top.Text = info.Top
	name.Text = info.Name
	hint.Text = info.Hint
	hint.TextColor3 = info.HintColor
	bar.BackgroundColor3 = info.BarColor
	bar.Size = UDim2.fromScale(info.Progress, 1)
	gui.Enabled = true
end)

print("[LayerHUD] Init OK")