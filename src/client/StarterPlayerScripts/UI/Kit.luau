local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Util = require(ReplicatedStorage.Shared.Util)
local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)

local e = React.createElement
local C = Theme.Colors
local WHITE = Color3.new(1, 1, 1)

local Kit = {}

local function corner(radius: number)
	return e("UICorner", { CornerRadius = UDim.new(0, radius) })
end

---------------------------------------------------------------------
-- Motion: 0 -> 1 with ease-out over 0.2s (a binding, so it doesn't re-render children)
---------------------------------------------------------------------
function Kit.useAppear(duration)
	local alpha, setAlpha = React.useBinding(0)
	React.useEffect(function()
		local start = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.clamp((os.clock() - start) / (duration or 0.2), 0, 1)
			setAlpha(1 - (1 - t) ^ 3)
			if t >= 1 then
				connection:Disconnect()
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	return alpha
end

---------------------------------------------------------------------
-- Spring motion: a binding that chases `target` with overshoot.
-- initial (optional) is the starting value, so a spring can pop in from 0.
---------------------------------------------------------------------
function Kit.useSpring(target: number, stiffness: number?, damping: number?, initial: number?)
	local start = if initial ~= nil then initial else target
	local binding, setBinding = React.useBinding(start)
	local sim = React.useRef({ pos = start, vel = 0, goal = target, conn = nil })
	local k = stiffness or 260
	local c = damping or 18

	React.useEffect(function()
		local s = sim.current
		s.goal = target
		if not s.conn then
			s.conn = RunService.Heartbeat:Connect(function(dt)
				dt = math.min(dt, 1 / 30)
				local accel = (s.goal - s.pos) * k - s.vel * c
				s.vel += accel * dt
				s.pos += s.vel * dt
				setBinding(s.pos)
				if math.abs(s.goal - s.pos) < 0.0005 and math.abs(s.vel) < 0.0005 then
					s.pos = s.goal
					setBinding(s.pos)
					s.conn:Disconnect()
					s.conn = nil
				end
			end)
		end
		return nil
	end, { target })

	React.useEffect(function()
		return function()
			local s = sim.current
			if s.conn then
				s.conn:Disconnect()
				s.conn = nil
			end
		end
	end, {})

	return binding
end

-- Springs from 0 up to ~1.2 and settles at 1 (use like the old useAppear, but bouncier)
function Kit.useEntrance()
	return Kit.useSpring(1, 240, 14, 0)
end

-- Endless gentle wave from -1 to 1 (for idle bobbing)
function Kit.useWave(speed: number?)
	local wave, setWave = React.useBinding(0)
	React.useEffect(function()
		local connection = RunService.Heartbeat:Connect(function()
			setWave(math.sin(os.clock() * (speed or 2)))
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	return wave
end
---------------------------------------------------------------------
-- Plain text (body copy)
---------------------------------------------------------------------
function Kit.Text(props)
	return e("TextLabel", {
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Body,
		Text = props.Text,
		TextColor3 = props.Color or C.Cream,
		TextSize = props.TextSize or 16,
		TextWrapped = props.Wrapped,
		TextXAlignment = props.Align or Enum.TextXAlignment.Left,
		TextYAlignment = props.VAlign or Enum.TextYAlignment.Center,
		ZIndex = props.ZIndex,
	})
end

---------------------------------------------------------------------
-- Chunky outlined lettering with a drop shadow
---------------------------------------------------------------------
function Kit.ChunkText(props)
	local font = props.Font or Theme.Fonts.Display
	local thickness = props.Stroke or 3
	local strokeColor = props.StrokeColor or C.Ink

	local function layer(color: Color3, offset: UDim2, z: number)
		local kids = { Outline = e("UIStroke", { Thickness = thickness, Color = strokeColor }) }
		if props.Scaled then
			kids.Limit = e("UITextSizeConstraint", { MaxTextSize = props.TextSize or 24 })
		end
		return e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			Position = offset,
			BackgroundTransparency = 1,
			Font = font,
			Text = props.Text,
			TextColor3 = color,
			TextSize = props.TextSize or 24,
			TextScaled = props.Scaled,
			TextWrapped = props.Wrapped,
			TextXAlignment = props.Align or Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = z,
		}, kids)
	end

	return e("Frame", {
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex,
	}, {
		Shadow = layer(strokeColor, UDim2.fromOffset(0, props.Drop or 3), 1),
		Main = layer(props.Color or WHITE, UDim2.fromOffset(0, 0), 2),
	})
end

---------------------------------------------------------------------
-- Plate: shadow (ZIndex 1) behind body (ZIndex 2). Children go inside the body.
---------------------------------------------------------------------
function Kit.Plate(props)
	local radius = props.Radius or 14
	local body = {
		Corner = corner(radius),
		Edge = e("UIStroke", {
			Color = props.Edge or C.Ink,
			Thickness = props.EdgeThickness or 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Sheen = e("UIGradient", {
			Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 198, 196)),
			Rotation = 90,
		}),
		-- thin rim light along the top edge (ZIndex 0 so real children draw above it)
		Rim = e("Frame", {
			Size = UDim2.new(1, -radius * 2, 0, 2),
			Position = UDim2.fromOffset(radius, 4),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, { Corner = corner(2) }),
	}
	if props.children then
		for key, child in props.children do
			body[key] = child
		end
	end

	return e("Frame", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		BackgroundTransparency = 1,
	}, {
		Shadow = if props.Shadow == false
			then nil
			else e("Frame", {
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromOffset(0, 5),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				ZIndex = 1,
			}, { Corner = corner(radius) }),
		Body = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = props.Fill or C.Iron,
			BorderSizePixel = 0,
			Active = props.Active,
			ZIndex = 2,
		}, body),
	})
end

---------------------------------------------------------------------
-- BigButton: Depth (ZIndex 1) behind Face (ZIndex 2). Face holds gloss + label.
---------------------------------------------------------------------
local VARIANTS = {
	clay = { C.Clay, C.ClayDark },
	green = { C.Green, C.GreenDark },
	gold = { C.Amber, C.AmberDark },
	red = { C.Red, C.RedDark },
	iron = { C.IronLight, C.IronDark },
	grey = { Color3.fromRGB(120, 120, 130), Color3.fromRGB(70, 70, 80) },
}

function Kit.BigButton(props)
	local hover, setHover = React.useState(false)
	local down, setDown = React.useState(false)

	local disabled = props.Disabled == true
	local pair = VARIANTS[if disabled then "grey" else (props.Variant or "clay")] or VARIANTS.clay
	local face = pair[1]
	if hover and not disabled then
		face = face:Lerp(WHITE, 0.15)
	end
	local lift = if down and not disabled then 4 else 0

	local scaleTarget = 1
	if not disabled then
		scaleTarget = if down then 0.94 elseif hover then 1.07 else 1
	end
	local scale = Kit.useSpring(scaleTarget, 420, 22)

	local label
	if props.Content then
		label = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, { Inner = props.Content })
	else
		label = e(Kit.ChunkText, {
			Text = props.Text,
			TextSize = props.TextSize or 22,
			Color = if disabled then Color3.fromRGB(210, 210, 215) else WHITE,
			ZIndex = 3,
		})
	end

	return e("Frame", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		BackgroundTransparency = 1,
	}, {
		Inner = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			Depth = e("Frame", {
				Size = UDim2.new(1, 0, 1, -4),
				Position = UDim2.fromOffset(0, 4),
				BackgroundColor3 = pair[2],
				BorderSizePixel = 0,
				ZIndex = 1,
			}, {
				Corner = corner(12),
				Edge = e("UIStroke", { Color = C.Ink, Thickness = 3 }),
			}),
			Face = e("TextButton", {
				Size = UDim2.new(1, 0, 1, -4),
				Position = UDim2.fromOffset(0, lift),
				BackgroundColor3 = face,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 2,
				[React.Event.Activated] = function()
					if not disabled and props.OnActivated then
						Sounds.Play("Click")
						props.OnActivated()
					end
				end,
				[React.Event.MouseEnter] = function()
					setHover(true)
					if not disabled then
						Sounds.Play("Hover")
					end
				end,
				[React.Event.MouseLeave] = function()
					setHover(false)
					setDown(false)
				end,
				[React.Event.MouseButton1Down] = function()
					setDown(true)
				end,
				[React.Event.MouseButton1Up] = function()
					setDown(false)
				end,
			}, {
				Corner = corner(12),
				Edge = e("UIStroke", { Color = C.Ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
				Sheen = e("UIGradient", {
					Color = ColorSequence.new(WHITE, Color3.fromRGB(205, 200, 198)),
					Rotation = 90,
				}),
				Gloss = e("Frame", {
					Size = UDim2.new(1, -24, 0, 3),
					Position = UDim2.fromOffset(12, 5),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = if disabled then 0.9 else 0.6,
					BorderSizePixel = 0,
					ZIndex = 2,
				}, { Corner = corner(2) }),
				Label = label,
			}),
		}),
	})
end

---------------------------------------------------------------------
-- Icons: an uploaded image if Theme.Icons has one, otherwise a symbol tile
---------------------------------------------------------------------
local KIND_STYLE = {
	Hold = { Color = C.Green, Glyph = "↻" },
	Speed = { Color = C.Amber, Glyph = "»" },
	Grip = { Color = C.Clay, Glyph = "+" },
	Reach = { Color = C.Slate, Glyph = "↔" },
}

function Kit.Icon(props)
	local style = KIND_STYLE[props.Kind] or { Color = C.IronLight, Glyph = "?" }
	local image = Theme.Icons and Theme.Icons[props.Kind] or ""
	local content

	if props.Locked then
		content = e(Kit.ChunkText, { Text = "?", TextSize = props.GlyphSize or 40, Color = C.PaperDark })
	elseif image ~= "" then
		content = e("ImageLabel", {
			Size = UDim2.fromScale(0.82, 0.82),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		content = e(Kit.ChunkText, { Text = style.Glyph, TextSize = props.GlyphSize or 44, Color = WHITE })
	end

	return e(Kit.Plate, {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Fill = if props.Locked then C.IronDark else style.Color,
		Edge = props.Edge,
		EdgeThickness = props.EdgeThickness,
		Radius = 12,
	}, { Content = content })
end

---------------------------------------------------------------------
-- Level pips
---------------------------------------------------------------------
function Kit.Pips(props)
	local kids = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = props.Align or Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for level = 1, props.Max do
		kids["Pip" .. level] = e("Frame", {
			LayoutOrder = level,
			Size = UDim2.fromOffset(props.PipWidth or 14, props.PipHeight or 9),
			BackgroundColor3 = if level <= props.Level then C.Amber else C.IronDark,
			BorderSizePixel = 0,
		}, {
			Corner = corner(3),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 1.5 }),
		})
	end
	return e("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 12),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
	}, kids)
end

---------------------------------------------------------------------
-- UpgradeTile: pips above, icon tile, price below.
---------------------------------------------------------------------
function Kit.UpgradeTile(props)
	local track = props.Track
	local size = props.TileSize or 84
	local locked = not props.Owned
	local maxed = track.Price == nil

	local priceText, priceColor
	if locked then
		priceText, priceColor = "???", C.PaperDark
	elseif maxed then
		priceText, priceColor = "MAX", C.Amber
	elseif props.Money >= track.Price then
		priceText, priceColor = Util.FormatCents(track.Price), C.MoneyGreen
	else
		priceText, priceColor = Util.FormatCents(track.Price), Color3.fromRGB(255, 120, 110)
	end

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(size, size + 44),
		BackgroundTransparency = 1,
	}, {
		Pips = e(Kit.Pips, {
			Level = track.Level,
			Max = track.MaxLevel,
			PipWidth = math.max(6, math.floor((size - 4 * track.MaxLevel) / track.MaxLevel)),
			PipHeight = 8,
			Size = UDim2.new(1, 0, 0, 12),
		}),
		Icon = e(Kit.Icon, {
			Kind = props.Kind,
			Locked = locked,
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(0, 16),
			Edge = if props.Selected then C.Amber else C.Ink,
			EdgeThickness = if props.Selected then 5 else 3,
		}),
		Hit = e("TextButton", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(0, 16),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
			[React.Event.Activated] = props.OnSelect,
		}),
		Price = e(Kit.ChunkText, {
			Text = priceText,
			Color = priceColor,
			TextSize = 18,
			Stroke = 2.5,
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, size + 18),
		}),
	})
end

return Kit