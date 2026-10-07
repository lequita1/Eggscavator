local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StationTeleportService = {}

local COOLDOWN = 1.5
local STATIONS = {
	Sell = "SellStation",
	Shop = "ToolShop",
}

local lastUse: { [Player]: number } = {}

function StationTeleportService.Init()
	local remotes = ReplicatedStorage.Remotes
	local request = remotes.TeleportRequest
	local notify = remotes.Notify

	request.OnServerEvent:Connect(function(player: Player, stationKey: any)
		if typeof(stationKey) ~= "string" then
			return
		end
		local stationName = STATIONS[stationKey]
		if not stationName then
			return
		end

		local now = os.clock()
		if lastUse[player] and now - lastUse[player] < COOLDOWN then
			return
		end
		lastUse[player] = now

		-- No teleporting once the Core is being carried, or after the round ends
		local roundState = workspace:GetAttribute("RoundState")
		if roundState == "Carrying" or roundState == "Ended" then
			notify:FireClient(player, "You can't teleport right now.", "error")
			return
		end

		local map = workspace:FindFirstChild("Map")
		local station = map and map:FindFirstChild(stationName)
		local spot = station and station:FindFirstChild("TeleportSpot")
		if not spot or not spot:IsA("BasePart") then
			warn("[StationTeleportService] Missing Map." .. stationName .. ".TeleportSpot")
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or not root then
			return
		end

		local target = spot.Position + Vector3.new(0, 3, 0)
		local counter = station:FindFirstChild("Counter")
		local lookAt = if counter and counter:IsA("BasePart")
			then Vector3.new(counter.Position.X, target.Y, counter.Position.Z)
			else target + spot.CFrame.LookVector

		character:PivotTo(CFrame.lookAt(target, lookAt))
		root.AssemblyLinearVelocity = Vector3.zero
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)

	print("[StationTeleportService] Init OK")
end

return StationTeleportService