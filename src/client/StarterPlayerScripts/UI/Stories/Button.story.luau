local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactLua.ReactRoblox)
local Button = require(script.Parent.Parent.Components.Button)

local e = React.createElement

local controls = {
	Text = "Sell Loot",
	Variant = "primary", -- primary, secondary, or danger
	Disabled = false,
}

return {
	summary = "Reusable Button with hover, variants and a disabled state",
	react = React,
	reactRoblox = ReactRoblox,
	controls = controls,
	story = function(props)
		return e(Button, {
			Text = props.controls.Text,
			Variant = props.controls.Variant,
			Disabled = props.controls.Disabled,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(220, 44),
			OnActivated = function()
				print("Button story clicked")
			end,
		})
	end,
}