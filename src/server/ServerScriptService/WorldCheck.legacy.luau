local ServerStorage = game:GetService("ServerStorage")

local problems = 0

local function find(root: Instance?, ...: string): Instance?
	local current = root
	for _, name in { ... } do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function check(label: string, instance: Instance?, className: string?): Instance?
	if instance and (not className or instance:IsA(className)) then
		print("[WorldCheck] OK      " .. label)
	else
		problems += 1
		warn("[WorldCheck] MISSING " .. label .. (if className then " (needs a " .. className .. ")" else ""))
	end
	return instance
end

local map = check("Workspace.Map", workspace:FindFirstChild("Map"))
check("Workspace.Eggs", workspace:FindFirstChild("Eggs"), "Folder")
check("Map.Spawn", find(map, "Spawn"), "SpawnLocation")
check("Map.EggField.EggPad_1", find(map, "EggField", "EggPad_1"), "BasePart")

-- Sell station and tool shop
for _, station in { "SellStation", "ToolShop" } do
	local promptName = if station == "SellStation" then "SellPrompt" else "ShopPrompt"
	local counter = check("Map." .. station .. ".Counter", find(map, station, "Counter"), "BasePart")
	local prompt = check(
		"Map." .. station .. ".Counter." .. promptName,
		find(map, station, "Counter", promptName),
		"ProximityPrompt"
	)
	local spot = check("Map." .. station .. ".TeleportSpot", find(map, station, "TeleportSpot"), "BasePart")

	-- Is the teleport spot close enough to use the prompt? (approximate, counter center to spot)
	if counter and prompt and spot and prompt:IsA("ProximityPrompt") then
		local distance = ((spot :: BasePart).Position - (counter :: BasePart).Position).Magnitude
		if distance > prompt.MaxActivationDistance + 4 then
			problems += 1
			warn(string.format(
				"[WorldCheck] %s.TeleportSpot is %.1f studs from the counter, but the prompt reaches %.1f. Move it closer.",
				station, distance, prompt.MaxActivationDistance
				))
		end
	end
end

-- Delivery
check("Map.DeliverySpot.Pad", find(map, "DeliverySpot", "Pad"), "BasePart")
check("Map.DeliverySpot.Pad.DeliverPrompt", find(map, "DeliverySpot", "Pad", "DeliverPrompt"), "ProximityPrompt")

-- Egg model
local egg = check("ServerStorage.Assets.Eggs.Stonehatch", find(ServerStorage, "Assets", "Eggs", "Stonehatch"), "Model")
if egg then
	local shell = check("Stonehatch.Shell", egg:FindFirstChild("Shell"), "BasePart")
	check("Stonehatch.Core", egg:FindFirstChild("Core"))
	if shell and (egg :: Model).PrimaryPart ~= shell then
		problems += 1
		warn("[WorldCheck] Stonehatch.PrimaryPart must be the Shell.")
	end
end

-- Tools
for _, toolName in { "IcePick", "Pickaxe", "Drill" } do
	local tool = check("ServerStorage.Assets.Tools." .. toolName, find(ServerStorage, "Assets", "Tools", toolName), "Tool")
	if tool then
		check(toolName .. ".Handle", tool:FindFirstChild("Handle"), "BasePart")
	end
end

if problems == 0 then
	print("[WorldCheck] All world objects found.")
else
	warn(string.format("[WorldCheck] %d problem(s) found. Fix the MISSING lines above.", problems))
end