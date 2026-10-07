local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Theme = require(script.Parent.Parent.Theme)
local Label = require(script.Parent.Label)

local e = React.createElement

-- Props: Title (optional), Size, Position, AnchorPoint, LayoutOrder
-- Children: pass them as a table, e.g. e(Panel, props, { A = e(...), B = e(...) }).
-- Children are stacked vertically in order of their LayoutOrder.
local function Panel(props)
	-- The content area stacks its children vertically.
	local content = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}
	if props.children then
		for key, child in props.children do
			content[key] = child
		end
	end

	local frameChildren = {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
		Stroke = e("UIStroke", {
			Color = Theme.Colors.Secondary,
			Thickness = 1,
			Transparency = 0.5,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		Content = e("Frame", {
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, content),
	}

	if props.Title then
		frameChildren.Title = e(Label, {
			LayoutOrder = 0,
			Text = props.Title,
			Style = "title",
		})
	end

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(230, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, frameChildren)
end

return Panel