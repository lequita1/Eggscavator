local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Theme = require(script.Parent.Parent.Theme)

local e = React.createElement

local VARIANTS = {
	primary = Theme.Colors.Primary,
	secondary = Theme.Colors.Secondary,
	danger = Theme.Colors.Danger,
}

-- Props: Text, Variant ("primary" | "secondary" | "danger"), Disabled,
-- OnActivated, Size, Position, AnchorPoint, LayoutOrder, TextSize
local function Button(props)
	local hovered, setHovered = React.useState(false)

	local base = VARIANTS[props.Variant or "primary"] or Theme.Colors.Primary
	local color = base
	if props.Disabled then
		color = Theme.Colors.Disabled
	elseif hovered then
		color = base:Lerp(Color3.new(1, 1, 1), 0.15)
	end

	return e("TextButton", {
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Bold,
		TextSize = props.TextSize or 16,
		TextColor3 = props.Disabled and Theme.Colors.TextMuted or Theme.Colors.Text,
		Text = props.Text or "Button",
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if not props.Disabled and props.OnActivated then
				props.OnActivated()
			end
		end,
	}, {
		Corner = e("UICorner", { CornerRadius = Theme.Radius }),
	})
end

return Button