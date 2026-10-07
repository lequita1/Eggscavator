-- ShopTags v2: swinging wooden name tags over the Tool Shop items (keeps looking until all tags are found)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- tune by eye ------------------------------------------------------
local NEAR = 24 -- studs: how close you must be for a tag to show
local LOOK_ANGLE = 32 -- degrees: how near the middle of the screen the item must be
local KEEP_BONUS = 7 -- bigger = the shown tag sticks longer before switching
local SWING_DEG = 3.5 -- how far the tag swings
local SWING_SPEED = 1.7 -- swing speed
local BOB_PX = 2 -- up/down float in pixels
local FADE_SPEED = 9 -- pop in/out speed
local SHINE_EVERY = 3.6 -- seconds between shine sweeps
local EXPECTED_TAGS = 8
----------------------------------------------------------------------

local Util, GameConfig, ToolDefinitions
pcall(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	Util = require(shared:WaitForChild("Util"))
end)
pcall(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	GameConfig = require(shared:WaitForChild("GameConfig"))
end)
pcall(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	ToolDefinitions = require(shared:WaitForChild("ToolDefinitions"))
end)

local function formatPrice(cents)
	if Util and Util.FormatCents then
		return Util.FormatCents(cents)
	end
	return "$" .. tostring(math.floor(cents / 100 + 0.5))
end

local function priceFor(name)
	local cents = nil
	pcall(function()
		local td = ToolDefinitions and ToolDefinitions[name]
		if td and type(td.Price) == "number" and td.Price > 0 then
			cents = td.Price
			return
		end
		for _, up in GameConfig.Pickup.Upgrades do
			if up.Id == name or up.Name == name then
				local src = GameConfig.Pickup[up.Id]
				cents = up.Price or (type(src) == "table" and src.Price) or nil
				return
			end
		end
		for _, up in GameConfig.Inventory.CapacityUpgrades do
			if up.Name == name then
				cents = up.Price
				return
			end
		end
	end)
	return cents
end

local tags = {}
local known = {}

local function register(d)
	if known[d] then
		return
	end
	local part = d.Parent
	local swing = d:FindFirstChild("Swing")
	local plank = swing and swing:FindFirstChild("Plank")
	if not (part and part:IsA("BasePart") and swing and plank) then
		return
	end
	known[d] = true
	local name = part.Name:sub(9)
	local pill = plank:FindFirstChild("Pill")
	local priceText = pill and pill:FindFirstChild("PriceText")
	local nameText = plank:FindFirstChild("NameText")
	local cents = priceFor(name)
	if cents and priceText then
		priceText.Text = formatPrice(cents)
	else
		if pill then
			pill.Visible = false
		end
		if nameText then
			nameText.Position = UDim2.fromOffset(18, 18)
			nameText.Size = UDim2.fromOffset(154, 44)
		end
	end
	swing.Visible = false
	table.insert(tags, {
		part = part,
		swing = swing,
		scale = swing:FindFirstChild("Scale"),
		shine = plank:FindFirstChild("Shine"),
		alpha = 0,
		phase = math.random() * 6.28,
		shineT = 0,
	})
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local shop = map and map:FindFirstChild("ToolShop")
	local tent = shop and shop:FindFirstChild("Tent")
	if not tent then
		return
	end
	for _, d in tent:GetDescendants() do
		if d:IsA("BillboardGui") and d.Name == "Label" and d:GetAttribute("ShopTag") then
			register(d)
		end
	end
end

task.spawn(function()
	local lastCount = -1
	while true do
		local ok, err = pcall(scan)
		if not ok then
			warn("[ShopTags] scan failed: " .. tostring(err))
		end
		if #tags ~= lastCount then
			lastCount = #tags
			print("[ShopTags] controlling " .. #tags .. " tag(s)")
		end
		if #tags >= EXPECTED_TAGS then
			break
		end
		task.wait(1)
	end
end)

local current = nil
local warned = false

local function step(dt)
	if #tags == 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	local cf = camera.CFrame
	local look = cf.LookVector
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local refPos = if root then root.Position else cf.Position

	local best, bestScore, currentScore = nil, nil, nil
	for _, tag in tags do
		local pos = tag.part.Position
		local toPart = pos - cf.Position
		local dist = toPart.Magnitude
		if dist > 0.1 and (pos - refPos).Magnitude <= NEAR then
			local angle = math.deg(math.acos(math.clamp(look:Dot(toPart.Unit), -1, 1)))
			if angle <= LOOK_ANGLE then
				local score = angle + dist * 0.4
				if tag == current then
					currentScore = score
				end
				if not bestScore or score < bestScore then
					best, bestScore = tag, score
				end
			end
		end
	end
	if current and currentScore and best ~= current and currentScore <= bestScore + KEEP_BONUS then
		best = current
	end
	current = best

	local t = os.clock()
	local k = math.min(1, dt * FADE_SPEED)
	for _, tag in tags do
		local target = if tag == current then 1 else 0
		tag.alpha += (target - tag.alpha) * k
		if target == 0 and tag.alpha < 0.01 then
			tag.alpha = 0
		end
		local a = tag.alpha
		tag.swing.Visible = a > 0
		if a > 0 then
			tag.swing.GroupTransparency = 1 - a * a * (3 - 2 * a)
			local s = a - 1
			local ease = 1 + 2.70158 * s ^ 3 + 1.70158 * s ^ 2
			if tag.scale then
				tag.scale.Scale = 0.6 + 0.4 * ease
			end
			tag.swing.Rotation = math.sin(t * SWING_SPEED + tag.phase) * SWING_DEG * (0.5 + 0.5 * a)
			tag.swing.Position = UDim2.new(0.5, 0, 0, 4 + math.sin(t * 2.1 + tag.phase) * BOB_PX)
			if tag.shine then
				if a > 0.8 then
					tag.shineT += dt
					local p = (tag.shineT % SHINE_EVERY) / 1.0
					if p <= 1 then
						tag.shine.Position = UDim2.fromOffset(-30 + p * 250, 40)
					else
						tag.shine.Position = UDim2.fromOffset(-100, 40)
					end
				else
					tag.shineT = 0
					tag.shine.Position = UDim2.fromOffset(-100, 40)
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(step, dt)
	if not ok and not warned then
		warned = true
		warn("[ShopTags] step failed: " .. tostring(err))
	end
end)

print("[ShopTags] Init OK (v2)")
