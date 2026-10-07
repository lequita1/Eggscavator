-- DinoLife (client, StarterPlayerScripts): animates every rigged dinosaur in the world, on each player's own screen.
--   Mother ("Idle")      breathing, looking around, a swaying tail
--   carried hatchling    thrashing in the player's arms
--   field hatchling      restless on the egg, waiting to be picked up
-- A model opts in with the tag "DinoAnim" plus the attributes DinoProfile ("Mother" / "Hatchling") and DinoMode
-- ("Idle" / "Carried" / "Field"). A cutscene that drives a model itself sets the attribute Manual = true on it.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DinoAnimator = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DinoAnimator"))

local TAG = "DinoAnim"
local RANGE = 450 -- studs from the camera: dinosaurs farther away are not animated

local entries = {} -- [model] = false (being built) or { Animator, Seed }

local function build(model)
	if entries[model] ~= nil or not model:IsA("Model") then
		return
	end
	entries[model] = false
	task.spawn(function()
		-- the mesh and its bones can arrive a moment after the model (streaming)
		local ready = false
		for _ = 1, 100 do
			if not model.Parent then
				break
			end
			local mesh = model:FindFirstChildWhichIsA("MeshPart")
			if mesh and mesh:FindFirstChildWhichIsA("Bone", true) then
				ready = true
				break
			end
			task.wait(0.1)
		end
		if not ready then
			entries[model] = nil
			return
		end
		local ok, result = pcall(DinoAnimator.new, model, model:GetAttribute("DinoProfile") or "Hatchling")
		if ok then
			entries[model] = { Animator = result, Seed = math.random() * 100 }
		else
			entries[model] = nil
			warn("[DinoLife] " .. tostring(result))
		end
	end)
end

local function pose(model, e, t)
	local mode = model:GetAttribute("DinoMode")
	local L = e.Animator.Length
	local seed = e.Seed
	if mode == "Idle" then
		return {
			Speed = 0,
			LookYaw = math.sin(t * 0.35 + seed) * 0.5,
			LookPitch = math.sin(t * 0.23 + seed) * 0.1,
		}
	elseif mode == "Carried" then
		local fit = math.max(0, math.sin(t * 1.7 + seed)) ^ 3
		local snap = math.max(0, math.sin(t * 3.3)) ^ 8
		return {
			Speed = L * (0.45 + 0.5 * fit), -- the legs kick
			Tuck = 0.5 * math.max(0, math.sin(t * 2.3 + seed)),
			Excite = 1,
			Roar = 0.5 * snap,
			LookYaw = math.sin(t * 5 + seed) * 0.7 * (0.5 + fit),
		}
	elseif mode == "Field" then
		local hop = math.max(0, math.sin(t * 2.1)) ^ 4
		return {
			Speed = 0,
			Tuck = 0.6 * hop,
			Excite = 0.5 + 0.5 * math.sin(t * 1.3),
			LookYaw = math.sin(t * 0.8) * 0.8,
		}
	end
	return nil -- "Release" or anything else: a cutscene is driving it
end

RunService.Heartbeat:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local t = os.clock()
	for model, e in entries do
		if not model.Parent then
			entries[model] = nil
		elseif e and not model:GetAttribute("Manual") then
			if (model:GetPivot().Position - camera.CFrame.Position).Magnitude < RANGE then
				local p = pose(model, e, t)
				if p then
					e.Animator:Step(dt, p)
				end
			end
		end
	end
end)

for _, model in CollectionService:GetTagged(TAG) do
	build(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(build)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
	entries[model] = nil
end)

print("[DinoLife] Init OK")
