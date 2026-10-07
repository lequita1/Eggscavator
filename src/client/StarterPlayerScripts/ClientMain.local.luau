local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------------------------------------------------------------
-- 1. WAIT FOR THE SERVER'S REMOTES
---------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
if not Remotes:GetAttribute("Ready") then
	Remotes:GetAttributeChangedSignal("Ready"):Wait()
end
print(string.format("[Client] Remotes ready (%d)", #Remotes:GetChildren()))

---------------------------------------------------------------------
-- 2. CONFIRM SHARED MODULES ARE READABLE FROM THE CLIENT
---------------------------------------------------------------------
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local ToolDefinitions = require(Shared:WaitForChild("ToolDefinitions"))
print("[Client] Shared config OK. Drill costs " .. Util.FormatCents(ToolDefinitions.Drill.Price))

---------------------------------------------------------------------
-- 3. START CONTROLLERS
---------------------------------------------------------------------
-- Each controller starts inside pcall, so one broken controller can never stop the others.
local controllersFolder = script.Parent:WaitForChild("Controllers")

local CONTROLLER_ORDER = {
	"EggView",
	"PickupController",
	"ToolController",
	"EggAtmosphere",
	"ReactController",
}

local failed = 0
for _, controllerName in CONTROLLER_ORDER do
	local ok, err = pcall(function()
		local controller = require(controllersFolder:WaitForChild(controllerName))
		controller.Init()
	end)
	if not ok then
		failed += 1
		warn(string.format("[Client] Controller '%s' failed to start: %s", controllerName, tostring(err)))
	end
end

if failed == 0 then
	print("[Client] Controllers started")
else
	warn(string.format("[Client] Controllers started with %d failure(s)", failed))
end