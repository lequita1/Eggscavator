local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReactPackages = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactLua")
local React = require(ReactPackages:WaitForChild("React"))
local ReactRoblox = require(ReactPackages:WaitForChild("ReactRoblox"))

local App = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("App"))

local e = React.createElement
local player = Players.LocalPlayer

local ReactController = {}

local root

function ReactController.Init()
	local playerGui = player:WaitForChild("PlayerGui")

	local ok, err = pcall(function()
		root = ReactRoblox.createRoot(Instance.new("Folder"))
		root:render(ReactRoblox.createPortal(
			e("ScreenGui", {
				Name = "ReactUI",
				ResetOnSpawn = false, -- survives respawns, like MainUI
				IgnoreGuiInset = true, -- use the whole screen, including under the top bar
				DisplayOrder = 10, -- above the old MainUI while both exist
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, {
				App = e(App),
			}),
			playerGui
			))
	end)

	if ok then
		print(string.format("[%s] Init OK (React mounted)", script.Name))
	else
		warn(string.format("[%s] React failed to mount: %s", script.Name, tostring(err)))
	end
end

return ReactController