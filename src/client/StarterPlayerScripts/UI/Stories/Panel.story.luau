local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactLua.ReactRoblox)
local Button = require(script.Parent.Parent.Components.Button)
local Label = require(script.Parent.Parent.Components.Label)
local Panel = require(script.Parent.Parent.Components.Panel)

local e = React.createElement

local controls = {
	Title = "Backpack",
	Subtitle = "12 / 20 items",
}

return {
	summary = "Container with a title that stacks its children",
	react = React,
	reactRoblox = ReactRoblox,
	controls = controls,
	story = function(props)
		return e(Panel, {
			Title = props.controls.Title,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(240, 0),
		}, {
			Info = e(Label, {
				LayoutOrder = 1,
				Text = props.controls.Subtitle,
				Style = "muted",
			}),
			Sell = e(Button, {
				LayoutOrder = 2,
				Text = "Sell Loot",
				OnActivated = function()
					print("Panel story: sell clicked")
				end,
			}),
			Upgrade = e(Button, {
				LayoutOrder = 3,
				Text = "Upgrades",
				Variant = "secondary",
			}),
		})
	end,
}