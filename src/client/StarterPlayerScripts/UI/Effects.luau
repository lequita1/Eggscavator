local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)

local UI = script.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local e = React.createElement
local C = Theme.Colors

local Effects = {}

local function corner(radius: number)
	return e("UICorner", { CornerRadius = UDim.new(0, radius) })
end

---------------------------------------------------------------------
-- Burst: confetti that fans upward from a point, falls, and fades. One-shot.
-- props: OriginX, OriginY (pixels inside the parent), Count, Colors, Duration, ZIndex
---------------------------------------------------------------------
function Effects.Burst(props)
	local count = props.Count or 16
	local p = Kit.useAppear(props.Duration or 0.95)
	local palette = props.Colors or { C.Amber, C.Cream, C.MoneyGreen, C.Clay }

	local seeds = React.useState(function()
		local list = {}
		for i = 1, count do
			list[i] = {
				Angle = math.rad(math.random(-165, -15)),
				Speed = math.random(70, 190),
				Size = math.random(7, 13),
				Color = palette[(i % #palette) + 1],
				Round = i % 2 == 0,
				Spin = math.random(-300, 300),
			}
		end
		return list
	end)

	local fade = p:map(function(a: number)
		return math.clamp((a - 0.55) / 0.45, 0, 1)
	end)
	local ox, oy = props.OriginX or 0, props.OriginY or 0

	local kids = {}
	for i, seed in seeds do
		kids["Bit" .. i] = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(seed.Size, seed.Size),
			Position = p:map(function(a: number)
				local x = ox + math.cos(seed.Angle) * seed.Speed * a
				local y = oy + math.sin(seed.Angle) * seed.Speed * a + 240 * a * a
				return UDim2.fromOffset(x, y)
			end),
			Rotation = p:map(function(a: number)
				return seed.Spin * a
			end),
			BackgroundColor3 = seed.Color,
			BackgroundTransparency = fade,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = if seed.Round then UDim.new(1, 0) else UDim.new(0, 2) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 1.5, Transparency = fade }),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 10,
	}, kids)
end

---------------------------------------------------------------------
-- ProgressBar: springy fill with optional centered text
-- props: Fraction (0-1), Color, Text, TextSize, Size, Position, AnchorPoint, LayoutOrder, Radius, Stroke
---------------------------------------------------------------------
function Effects.ProgressBar(props)
	local target = math.clamp(props.Fraction or 0, 0, 1)
	local fill = Kit.useSpring(target, 180, 22, target)
	local radius = props.Radius or 8
	local color = props.Color or C.Amber

	return e("Frame", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = C.IronDark,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		Corner = corner(radius),
		Edge = e("UIStroke", { Color = C.Ink, Thickness = props.Stroke or 2.5 }),
		Fill = e("Frame", {
			Size = fill:map(function(a: number)
				return UDim2.fromScale(math.clamp(a, 0, 1), 1)
			end),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, {
			Corner = corner(radius),
			Sheen = e("UIGradient", {
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 186, 184)),
				Rotation = 90,
			}),
		}),
		Label = if props.Text
			then e(Kit.ChunkText, {
				Text = props.Text,
				TextSize = props.TextSize or 13,
				Stroke = 2,
				Drop = 1,
				ZIndex = 3,
			})
			else nil,
	})
end

return Effects