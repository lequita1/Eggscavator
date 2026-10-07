local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactLua.ReactRoblox)
local Label = require(script.Parent.Parent.Components.Label)

local e = React.createElement

local controls = {
	Text = "Chip the egg, sell your loot, upgrade your tools!",
	Style = "body", -- title, body, strong, or muted
}

return {
	summary = "Text label with title, body, strong and muted styles",
	react = React,
	reactRoblox = ReactRoblox,
	controls = controls,
	story = function(props)
		return e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(260, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Label = e(Label, {
				Text = props.controls.Text,
				Style = props.controls.Style,
			}),
		})
	end,
}