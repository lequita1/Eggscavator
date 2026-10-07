local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Theme = require(script.Parent.Parent.Theme)

local e = React.createElement

local STYLES = {
	title = { Font = Theme.Fonts.Bold, TextSize = Theme.TextSizes.Title, Color = Theme.Colors.Gold },
	body = { Font = Theme.Fonts.Regular, TextSize = Theme.TextSizes.Body, Color = Theme.Colors.Text },
	strong = { Font = Theme.Fonts.Bold, TextSize = Theme.TextSizes.Body, Color = Theme.Colors.Text },
	muted = { Font = Theme.Fonts.Regular, TextSize = Theme.TextSizes.Small, Color = Theme.Colors.TextMuted },
}

-- Props: Text, Style ("title" | "body" | "strong" | "muted"), TextXAlignment,
-- TextWrapped, Size, AutomaticSize, Position, AnchorPoint, LayoutOrder
-- With no Size given, it is full width and grows in height to fit its text.
local function Label(props)
	local style = STYLES[props.Style or "body"] or STYLES.body

	local size = props.Size or UDim2.fromScale(1, 0)
	local automaticSize = props.AutomaticSize
	if automaticSize == nil then
		automaticSize = if props.Size == nil then Enum.AutomaticSize.Y else Enum.AutomaticSize.None
	end

	local wrapped = true
	if props.TextWrapped ~= nil then
		wrapped = props.TextWrapped
	end

	return e("TextLabel", {
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = size,
		AutomaticSize = automaticSize,
		BackgroundTransparency = 1,
		Font = style.Font,
		TextSize = style.TextSize,
		TextColor3 = style.Color,
		TextWrapped = wrapped,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		Text = props.Text or "",
	})
end

return Label