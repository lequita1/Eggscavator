local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolDefinitions = require(ReplicatedStorage.Shared.ToolDefinitions)
local EggView = require(script.Parent.EggView)
local PickupController = require(script.Parent.PickupController)

local player = Players.LocalPlayer
local ToolController = {}

local HitEgg: RemoteEvent
local hookedTools = setmetatable({}, { __mode = "k" })

local function hookTool(tool: Tool)
	if hookedTools[tool] then
		return
	end
	hookedTools[tool] = true

	local definition = ToolDefinitions[tool:GetAttribute("ToolId")]
	if not definition then
		return
	end

	-- The server puts the upgraded interval on the tool. Fall back to the base value.
	local function getInterval(): number
		return tool:GetAttribute("AttackInterval") or definition.AttackInterval
	end

	local holding = false
	local loopId = 0 -- prevents two loops running if you click again quickly
	local lastSent = 0

	-- Aims at a patch and sends one hit request (only INTENT: which egg, where, which patch).
	local function trySwing()
		local now = os.clock()
		if now - lastSent < getInterval() then
			return -- still cooling down, so don't spam the server
		end
		if PickupController.PieceUnderAim() then
			return -- a piece is under the aim: that click picks it up instead of hitting the egg
		end
		local eggId, position, patchIndex = EggView.GetAim()
		if eggId then
			lastSent = now
			HitEgg:FireServer(eggId, position, patchIndex)
		end
	end

	tool.Activated:Connect(function()
		-- Base behavior: one click = one hit.
		trySwing()

		-- Hold-to-hit only exists once unlocked (the Hold upgrade, or a continuous tool).
		if not tool:GetAttribute("HoldEnabled") then
			return
		end

		holding = true
		loopId += 1
		local myLoop = loopId
		while holding and loopId == myLoop and tool.Parent == player.Character do
			task.wait(getInterval())
			if holding and loopId == myLoop then
				trySwing()
			end
		end
	end)

	tool.Deactivated:Connect(function()
		holding = false
	end)
	tool.Unequipped:Connect(function()
		holding = false
	end)
end

local function onCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			hookTool(child)
		end
	end
end

function ToolController.Init()
	HitEgg = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("HitEgg")

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	print(string.format("[%s] Init OK", script.Name))
end

return ToolController