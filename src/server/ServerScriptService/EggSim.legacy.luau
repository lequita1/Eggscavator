-- EggSim: Phase 4 simulator. Drives EggService with fake hits (no client). Disable after use.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
repeat task.wait() until Remotes:GetAttribute("Ready")
task.wait(3) -- let Main finish starting every service

local EggService = require(ServerScriptService.Services.EggService)
local ToolDefinitions = require(ReplicatedStorage.Shared.ToolDefinitions)

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		warn("  FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or ""))
	end
end

local toolByPower = {}
for _, tool in ToolDefinitions do
	toolByPower[tool.Power] = tool
end

local brokenCalls = { SimEgg_1 = 0, SimEgg_2 = 0 }
local function onBroken(eggId)
	brokenCalls[eggId] += 1
end

print("==== EggSim start ====")

-- 1. Spawn and initial attributes
local egg1 = EggService.SpawnTestEgg("SimEgg_1", Vector3.new(0, 4000, 0), onBroken)
check("test egg spawns", egg1 ~= nil)
if not egg1 then
	warn("EggSim stopped: no test egg (read the [EggService] warning above)")
	return
end
local count = egg1:GetAttribute("PatchCount")
local layerStr, hpStr = egg1:GetAttribute("PatchLayer"), egg1:GetAttribute("PatchHP")
check("PatchLayer has one char per patch", #layerStr == count, #layerStr)
check("PatchHP has one char per patch", #hpStr == count, #hpStr)
check("all patches start at layer 1, HP digit 9", select(2, string.gsub(layerStr, "[17]", "")) == count and select(2, string.gsub(hpStr, "[90]", "")) == count)
check("Durability starts near max", egg1:GetAttribute("Durability") >= egg1:GetAttribute("MaxDurability") * 0.98)

-- 2. Bad input is refused
check("patch 0 refused", EggService.ApplyPatchDamage("SimEgg_1", 0, 5, 3) == nil)
check("patch count+1 refused", EggService.ApplyPatchDamage("SimEgg_1", count + 1, 5, 3) == nil)
check("fractional patch refused", EggService.ApplyPatchDamage("SimEgg_1", 1.5, 5, 3) == nil)
check("negative damage refused", EggService.ApplyPatchDamage("SimEgg_1", 1, -5, 3) == nil)
check("nan damage refused", EggService.ApplyPatchDamage("SimEgg_1", 1, 0 / 0, 3) == nil)
check("unknown egg refused", EggService.ApplyPatchDamage("Nope", 1, 5, 3) == nil)

-- 3. Damage multiplier: power 3 on hardness 1 = x1.5, power 2 = x1.25
local r = EggService.ApplyPatchDamage("SimEgg_1", 2, 6, 3)
check("power 3 on layer 1 applies 9", r and math.abs(r.Applied - 9) < 1e-6, r and r.Applied)
r = EggService.ApplyPatchDamage("SimEgg_1", 3, 6, 2)
check("power 2 on layer 1 applies 7.5", r and math.abs(r.Applied - 7.5) < 1e-6, r and r.Applied)

-- 4. Tool gate: Ice Pick (power 1) digs patch 1 down to layer 3, then is refused
local ice = toolByPower[1]
local result
for _ = 1, 200 do
	result = EggService.ApplyPatchDamage("SimEgg_1", 1, ice.Damage, ice.Power)
	if not result or result.TooHard then
		break
	end
end
check("Ice Pick is refused at layer 3 (Amber Resin)", result and result.TooHard and result.Required == 2 and result.Layer == 3)
local info = EggService.GetPatchInfo("SimEgg_1", 1)
check("refused hit did not change the patch", info and info.Layer == 3 and info.HP == info.MaxHP)
local pick = toolByPower[2]
for _ = 1, 200 do
	result = EggService.ApplyPatchDamage("SimEgg_1", 1, pick.Damage, pick.Power)
	if not result or result.TooHard then
		break
	end
end
check("Pickaxe is refused at layer 5 (Crystal Lining)", result and result.TooHard and result.Required == 3 and result.Layer == 5)
check("PatchLayer shows patch 1 at layer 5", string.sub(egg1:GetAttribute("PatchLayer"), 1, 1) == "5")
EggService.RemoveEgg("SimEgg_1")

-- 5. Full dig with the intended tool progression (virtual time, no walking, no tool swaps)
local egg2 = EggService.SpawnTestEgg("SimEgg_2", Vector3.new(200, 4000, 0), onBroken)
local target = math.ceil(1.00 * egg2:GetAttribute("PatchCount") - 1e-6)
local hits, seconds, cpu, calls = 0, 0, 0, 0
local lastDurability, monotonic = egg2:GetAttribute("Durability"), true
local brokenResults = 0

for index = 1, egg2:GetAttribute("PatchCount") do
	local done = false
	while not done do
		local patch = EggService.GetPatchInfo("SimEgg_2", index)
		if not patch or patch.Open then
			break
		end
		local tool = toolByPower[patch.Hardness]
		local t0 = os.clock()
		local res = EggService.ApplyPatchDamage("SimEgg_2", index, tool.Damage, tool.Power)
		cpu += os.clock() - t0
		calls += 1
		if not res then
			break
		end
		hits += 1
		seconds += tool.AttackInterval
		local d = egg2:GetAttribute("Durability")
		if d > lastDurability + 1e-9 then
			monotonic = false
		end
		lastDurability = d
		if res.Broken then
			brokenResults += 1
			done = true
		end
	end
	if brokenResults > 0 then
		break
	end
end

check("egg broke exactly once", brokenResults == 1, brokenResults)
check("Durability never went up", monotonic)
check("Durability is 0 at the break", egg2:GetAttribute("Durability") == 0, egg2:GetAttribute("Durability"))
check("OpenCount equals the target", egg2:GetAttribute("OpenCount") == target, egg2:GetAttribute("OpenCount"))
local opens = select(2, string.gsub(egg2:GetAttribute("PatchLayer"), "7", ""))
check("PatchLayer shows the same number of open patches", opens == target, opens)
check("a hit after the break is ignored", EggService.ApplyPatchDamage("SimEgg_2", 100, 5, 3) == nil)
check("GetEggModel is nil after the break", EggService.GetEggModel("SimEgg_2") == nil)
task.wait(1.5)
check("OnEggBroken-style callback fired exactly once", brokenCalls.SimEgg_2 == 1, brokenCalls.SimEgg_2)
check("Shell removed and Core revealed", egg2:FindFirstChild("Shell") == nil and egg2:GetAttribute("Revealed") == true)

print(string.format("Dig report: %d patches opened, %d hits", target, hits))
print(string.format("  Virtual time (no walking): solo %.0f s (%.1f min), 3 players %.0f s (%.1f min)",
	seconds, seconds / 60, seconds / 3, seconds / 180))
print(string.format("  Server cost: %.1f microseconds per hit", cpu / math.max(calls, 1) * 1e6))
EggService.RemoveEgg("SimEgg_2")

-- 6. The real eggs were not touched
local untouched = true
for _, e in Workspace.Eggs:GetChildren() do
	if e:GetAttribute("OpenCount") ~= select(2, string.gsub(layerStr, "7", "")) then
		untouched = false
	end
end
check("real eggs untouched", untouched)

print(string.format("==== EggSim done: %d passed, %d failed ====", passed, failed))