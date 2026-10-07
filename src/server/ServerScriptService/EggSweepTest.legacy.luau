-- EggSweepTest v2: checks the layer sweep on a detached test egg. Disable after use.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
repeat task.wait() until Remotes:GetAttribute("Ready")
task.wait(3)

local EggService = require(ServerScriptService.Services.EggService)
local def = require(ReplicatedStorage.Shared.EggDefinitions).Stonehatch

local passed, failed = 0, 0
local function check(name, ok, detail)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		warn("  FAIL  " .. name .. (detail ~= nil and (" -> " .. tostring(detail)) or ""))
	end
end

local sweep = def.LayerSweep
check("LayerSweep is set", type(sweep) == "number" and sweep > 0 and sweep <= 1, sweep)
if type(sweep) ~= "number" then
	return
end

local egg = EggService.SpawnTestEgg("SweepEgg", Vector3.new(400, 4000, 0))
if not egg then
	warn("EggSweepTest stopped: no test egg")
	return
end
local count = egg:GetAttribute("PatchCount")
local target = math.ceil(sweep * count - 1e-9) -- patches that must be past a layer to trigger the sweep
local layers = #def.Layers
print(string.format("%d patches, sweep needs %d past a layer (OpenToHatch %s)", count, target, tostring(def.OpenToHatch)))

local lastDurability, monotonic = egg:GetAttribute("Durability"), true
local function hit(i)
	local r = EggService.ApplyPatchDamage("SweepEgg", i, 1e6, 3)
	local d = egg:GetAttribute("Durability")
	if d > lastDurability + 1e-9 then
		monotonic = false
	end
	lastDurability = d
	return r
end

local finished = false
for k = 1, layers do
	local sweptAt, sweepCount, early, late = nil, 0, nil, false
	while true do
		-- read the live state: how many patches are past layer k, and the first patch still on layer k
		local str = egg:GetAttribute("PatchLayer")
		local past, nextIndex = 0, nil
		for i = 1, count do
			local d = tonumber(string.sub(str, i, i))
			if d > k then
				past += 1
			elseif d == k and not nextIndex then
				nextIndex = i
			end
		end
		if not nextIndex then
			break
		end
		local r = hit(nextIndex)
		if not r then
			break
		end
		local shouldSweep = past + 1 >= target
		if r.LayerSwept then
			sweepCount += 1
			sweptAt = r.LayerSwept
			if not shouldSweep then
				early = past + 1
			end
		elseif shouldSweep then
			late = true
		end
		if r.Broken then
			finished = true
			print(string.format("  note: the egg broke during layer %d (%d patches were past it)", k, past + 1))
			break
		end
		if sweptAt then
			break
		end
	end
	check(string.format("layer %d: no sweep before the threshold", k), early == nil, early)
	check(string.format("layer %d: no missed sweep", k), not late)
	if finished and sweptAt == nil then
		print("  note: finished by OpenToHatch before the last-layer sweep")
		break
	end
	check(string.format("layer %d: sweep fired exactly once", k), sweepCount == 1 and sweptAt == k, sweepCount)

	local str, hp = egg:GetAttribute("PatchLayer"), egg:GetAttribute("PatchHP")
	local minLayer, badHP = 99, 0
	for i = 1, count do
		local d = tonumber(string.sub(str, i, i))
		minLayer = math.min(minLayer, d)
		if d <= layers and string.sub(hp, i, i) ~= "9" then
			badHP += 1
		end
	end
	check(string.format("layer %d: every patch moved past it", k), minLayer > k, minLayer)
	check(string.format("layer %d: no closed patch is below full HP", k), badHP == 0, badHP)
	if finished then
		break
	end
end

check("egg broke", egg:GetAttribute("Broken") == true)
check("Durability never went up", monotonic)
EggService.RemoveEgg("SweepEgg")
print(string.format("==== EggSweepTest done: %d passed, %d failed ====", passed, failed))