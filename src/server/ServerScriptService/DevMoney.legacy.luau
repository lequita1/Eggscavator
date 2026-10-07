-- TEMPORARY test helper: gives every player $50 shortly after joining. Delete before publishing.
local Players = game:GetService("Players")
local PDS = require(game:GetService("ServerScriptService").Services.PlayerDataService)
local function give(player)
	for _ = 1, 50 do
		if PDS.Get(player) then
			PDS.AddMoney(player, 9999999)
			return
		end
		task.wait(0.2)
	end
end
Players.PlayerAdded:Connect(function(p) task.spawn(give, p) end)
for _, p in Players:GetPlayers() do task.spawn(give, p) end
