-- MotherHider (client): Mother is invisible except while the Release scene sets Workspace.MotherShow.
-- MotherShow is set by this player's own ReleaseCutscene and is never replicated.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local lastApplied = nil
local accumulator = 0

local function apply()
	local mother = Workspace:FindFirstChild("Dino")
	if not mother then
		return
	end
	local value = if Workspace:GetAttribute("MotherShow") then 0 else 1
	for _, d in mother:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = value
		end
	end
	lastApplied = value
end

Workspace:GetAttributeChangedSignal("MotherShow"):Connect(apply)

-- Re-apply now and then, because Mother can stream in later or be rebuilt by the server
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator >= 0.5 then
		accumulator = 0
		apply()
	end
end)

apply()
print("[MotherHider] Init OK")
