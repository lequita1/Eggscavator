local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Shared = ReplicatedStorage.Shared
local ToolDefinitions = require(Shared.ToolDefinitions)
local Util = require(Shared.Util)

local UI = script.Parent
local Theme = require(UI.Theme)
local Store = require(UI.Store)
local Kit = require(UI.Kit)
local Effects = require(UI.Effects)
local Sounds = require(UI.Sounds)

local e = React.createElement
local C = Theme.Colors

local W, H = 900, 560 -- design size (scaled to fit any screen below)
local TILE = 112 -- size of the upgrade tiles on the right page
local TILE_GAP = 12

local KIND_COLOR = { Hold = C.Green, Speed = C.Amber, Grip = C.Clay, Reach = C.Slate }
local KIND_GLYPH = { Hold = "↻", Speed = "»", Grip = "+", Reach = "↔" }

local function corner(radius: number)
	return e("UICorner", { CornerRadius = UDim.new(0, radius) })
end

-- Display-only preview of a level: a big value and a small unit. The SERVER computes the real stats.
local function parts(toolId: string, trackId: string, level: number): (string, string)
	local definition = ToolDefinitions[toolId]
	local track = definition.Upgrades[trackId]
	if track.Kind == "Hold" then
		if level > 0 then
			return "HOLD", "keep hitting"
		end
		return "CLICK", "one hit per click"
	elseif track.Kind == "Speed" then
		return string.format("%.2fs", definition.AttackInterval * (1 - track.PerLevel * level)), "between hits"
	elseif track.Kind == "Grip" then
		return tostring(definition.Damage + track.DamagePerLevel * level), "damage per hit"
	elseif track.Kind == "Reach" then
		return tostring(definition.Range + track.RangePerLevel * level), "studs of reach"
	end
	return "?", ""
end

-- Pill text on the left page: what the next level gives you
local function gain(toolId: string, trackId: string): string
	local track = ToolDefinitions[toolId].Upgrades[trackId]
	if track.Kind == "Hold" then
		return "UNLOCKS HOLDING"
	elseif track.Kind == "Speed" then
		return string.format("%d%% FASTER", math.floor(track.PerLevel * 100 + 0.5))
	elseif track.Kind == "Grip" then
		local n = track.ChipsPerLevel
		return string.format("+%d DAMAGE", track.DamagePerLevel)
	elseif track.Kind == "Reach" then
		return string.format("+%d STUDS", track.RangePerLevel)
	end
	return ""
end

-- Very short version for under each tile on the right page
local function short(toolId: string, trackId: string): string
	local track = ToolDefinitions[toolId].Upgrades[trackId]
	if track.Kind == "Hold" then
		return "Hold to hit"
	elseif track.Kind == "Speed" then
		return string.format("%d%% faster", math.floor(track.PerLevel * 100 + 0.5))
	elseif track.Kind == "Grip" then
		local n = track.ChipsPerLevel
		return string.format("+%d damage", track.DamagePerLevel)
	elseif track.Kind == "Reach" then
		return string.format("+%d studs", track.RangePerLevel)
	end
	return ""
end

local function anyAffordable(tool, money: number): boolean
	if not tool.Owned then
		return false
	end
	for _, t in tool.Tracks do
		if t.Price and money >= t.Price then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Icon tile: uploaded icon (or glyph), locked "?" state, optional pulsing glow
---------------------------------------------------------------------
local function TrackIcon(props)
	local color = KIND_COLOR[props.Kind] or C.IronLight
	local image = Theme.Icons and Theme.Icons[props.Kind]
	local content
	if props.Locked then
		content = e(Kit.ChunkText, { Text = "?", TextSize = props.GlyphSize or 40, Color = C.PaperDark, ZIndex = 3 })
	elseif image and image ~= "" then
		content = e("ImageLabel", {
			Size = UDim2.fromScale(0.82, 0.82),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		})
	else
		content = e(Kit.ChunkText, {
			Text = KIND_GLYPH[props.Kind] or "?",
			TextSize = props.GlyphSize or 44,
			ZIndex = 3,
		})
	end

	return e("Frame", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
	}, {
		Plate = e(Kit.Plate, {
			Size = UDim2.fromScale(1, 1),
			Fill = if props.Locked then C.IronDark else color,
			Edge = props.Edge,
			EdgeThickness = props.EdgeThickness,
			Radius = 12,
		}, { Content = content }),
		Glow = if props.Glow
			then e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 5,
			}, {
				Corner = corner(12),
				Ring = e("UIStroke", { Color = C.MoneyGreen, Thickness = 4, Transparency = props.Glow }),
			})
			else nil,
	})
end

---------------------------------------------------------------------
-- Right page: one upgrade tile
-- The pips and the icon lift TOGETHER, so the selected border never covers the pips.
---------------------------------------------------------------------
local function Tile(props)
	local tool, track = props.Tool, props.Track
	local kind = ToolDefinitions[tool.Id].Upgrades[track.Id].Kind
	local locked = not tool.Owned
	local maxed = track.Price == nil
	local affordable = not locked and not maxed and props.Money >= track.Price
	local size = TILE

	local hover, setHover = React.useState(false)
	local lift = Kit.useSpring(if props.Selected then -4 elseif hover and not locked then -3 else 0, 380, 20)

	local priceText, priceColor
	if locked then
		priceText, priceColor = "", C.PaperDark
	elseif maxed then
		priceText, priceColor = "MAX", C.Amber
	elseif affordable then
		priceText, priceColor = Util.FormatCents(track.Price), C.MoneyGreen
	else
		priceText, priceColor = Util.FormatCents(track.Price), Color3.fromRGB(255, 132, 112)
	end

	local benefitText = if locked or maxed then "" else short(tool.Id, track.Id)

	-- Pips fill the tile's full width, so all three tiles line up
	local pipWidth = math.max(6, math.floor((size - 3 * (track.MaxLevel - 1)) / track.MaxLevel))

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(size, 230),
		BackgroundTransparency = 1,
	}, {
		Stack = e("Frame", {
			Size = UDim2.fromOffset(size, size + 26),
			Position = lift:map(function(y: number)
				return UDim2.fromOffset(0, y)
			end),
			BackgroundTransparency = 1,
		}, {
			Pips = e(Kit.Pips, {
				Level = track.Level,
				Max = track.MaxLevel,
				PipWidth = pipWidth,
				PipHeight = 10,
				Size = UDim2.new(1, 0, 0, 14),
			}),
			Icon = e(TrackIcon, {
				Kind = kind,
				Locked = locked,
				Size = UDim2.fromOffset(size, size),
				Position = UDim2.fromOffset(0, 26),
				Edge = if props.Selected then C.Cream elseif maxed and not locked then C.Amber else nil,
				EdgeThickness = if props.Selected then 5 else 3,
				Glow = if affordable
					then props.Wave:map(function(w: number)
						return 0.45 + 0.3 * w
					end)
					else nil,
			}),
		}),
		Hit = e("TextButton", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(0, 26),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 8,
			[React.Event.MouseEnter] = function()
				setHover(true)
			end,
			[React.Event.MouseLeave] = function()
				setHover(false)
			end,
			[React.Event.Activated] = function()
				Sounds.Play("Click")
				props.OnSelect()
			end,
		}),
		Name = e(Kit.ChunkText, {
			Text = if locked then "???" else track.Name,
			Scaled = true,
			TextSize = 22,
			Stroke = 2,
			Drop = 2,
			Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.fromOffset(0, size + 34),
		}),
		Benefit = e(Kit.Text, {
			Text = benefitText,
			TextSize = 15,
			Color = C.BlueInk,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, size + 62),
		}),
		Price = e(Kit.ChunkText, {
			Text = priceText,
			Color = priceColor,
			TextSize = 24,
			Stroke = 2.5,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, size + 86),
		}),
	})
end

---------------------------------------------------------------------
-- Right page: tool tab (name stays on one line)
---------------------------------------------------------------------
local function Tab(props)
	local tool = props.Tool
	local owned = tool.Owned
	local selected = props.Selected
	local hover, setHover = React.useState(false)
	local lift = Kit.useSpring(if selected then -3 elseif hover then -2 else 0, 380, 20)
	local image = Theme.Icons and Theme.Icons[tool.Id]
	local width = props.Width

	local icon
	if not owned then
		icon = e(Kit.ChunkText, {
			Text = "?",
			TextSize = 26,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(7, 11),
			ZIndex = 3,
		})
	elseif image and image ~= "" then
		icon = e("ImageLabel", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(7, 11),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		})
	else
		icon = e(Kit.ChunkText, {
			Text = string.upper(string.sub(tool.Name, 1, 1)),
			TextSize = 24,
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(7, 11),
			ZIndex = 3,
		})
	end

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(width, 52),
		BackgroundTransparency = 1,
	}, {
		Inner = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = lift:map(function(y: number)
				return UDim2.fromOffset(0, y)
			end),
			BackgroundTransparency = 1,
		}, {
			Plate = e(Kit.Plate, {
				Size = UDim2.fromScale(1, 1),
				Fill = if selected then C.Iron elseif owned then C.PaperDark else C.IronDark,
				Edge = if selected then C.Amber elseif owned then C.PaperLine else C.Ink,
				EdgeThickness = if selected then 3.5 else 2.5,
				Radius = 12,
				Shadow = selected,
			}, {
				Icon = icon,
				Name = e(Kit.ChunkText, {
					Text = if owned then tool.Name else "???",
					TextSize = 18,
					Stroke = 2,
					Drop = 2,
					Align = Enum.TextXAlignment.Left,
					Size = UDim2.fromOffset(width - 44, 52),
					Position = UDim2.fromOffset(42, 0),
				}),
				Dot = if props.Ready
					then e("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(16, 16),
						Position = UDim2.fromOffset(width - 10, 8),
						BackgroundColor3 = C.MoneyGreen,
						BorderSizePixel = 0,
						ZIndex = 6,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
						Edge = e("UIStroke", { Color = C.Ink, Thickness = 2 }),
						Pulse = e("UIScale", {
							Scale = props.Wave:map(function(w: number)
								return 1 + 0.18 * w
							end),
						}),
					})
					else nil,
			}),
		}),
		Hit = e("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 8,
			[React.Event.MouseEnter] = function()
				setHover(true)
			end,
			[React.Event.MouseLeave] = function()
				setHover(false)
			end,
			[React.Event.Activated] = function()
				Sounds.Play("Click")
				props.OnSelect()
			end,
		}),
	})
end

---------------------------------------------------------------------
-- Left page: detail of the selected upgrade
---------------------------------------------------------------------
-- A NOW / NEXT box: big value on top, small unit underneath
local function ValueBox(props)
	return e(Kit.Plate, {
		Size = UDim2.fromOffset(144, 90),
		Position = props.Position,
		Fill = C.IronDark,
		Edge = props.Edge,
		Radius = 12,
		EdgeThickness = 2.5,
		Shadow = false,
	}, {
		Caption = e(Kit.Text, {
			Text = props.Caption,
			TextSize = 14,
			Color = C.PaperDark,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 7),
		}),
		Value = e(Kit.ChunkText, {
			Text = props.Value,
			Scaled = true,
			TextSize = 34,
			Stroke = 2.5,
			Color = props.Color,
			Size = UDim2.new(1, -16, 0, 40),
			Position = UDim2.fromOffset(8, 25),
		}),
		Unit = e(Kit.Text, {
			Text = props.Unit,
			TextSize = 15,
			Color = C.Cream,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 0, 18),
			Position = UDim2.fromOffset(4, 67),
		}),
	})
end

local function LevelUpText()
	local p = Kit.useAppear(1.0)
	local fade = p:map(function(a: number)
		return math.clamp((a - 0.5) / 0.5, 0, 1)
	end)
	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(220, 32),
		Position = p:map(function(a: number)
			return UDim2.fromOffset(60, 58 - 60 * a)
		end),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Display,
		Text = "LEVEL UP!",
		TextSize = 30,
		TextColor3 = C.Amber,
		TextTransparency = fade,
		ZIndex = 12,
	}, {
		Stroke = e("UIStroke", { Thickness = 3, Color = C.Ink, Transparency = fade }),
	})
end

local function Detail(props)
	local tool, track = props.Tool, props.Track
	local trackDef = ToolDefinitions[tool.Id].Upgrades[track.Id]
	local locked = not tool.Owned
	local maxed = track.Price == nil

	local nowValue, nowUnit = "???", ""
	local nextValue, nextUnit = "???", ""
	if not locked then
		nowValue, nowUnit = parts(tool.Id, track.Id, track.Level)
		if maxed then
			nextValue, nextUnit = "MAX", "fully upgraded"
		else
			nextValue, nextUnit = parts(tool.Id, track.Id, track.Level + 1)
		end
	end

	local pipWidth = if track.MaxLevel <= 3 then 40 else 28

	local kids = {
		-- HEADER: icon, name, tool + level, pips
		Icon = e(TrackIcon, {
			Kind = trackDef.Kind,
			Locked = locked,
			Size = UDim2.fromOffset(84, 84),
			Position = UDim2.fromOffset(18, 16),
			GlyphSize = 50,
			Edge = if maxed and not locked then C.Amber else nil,
		}),
		Name = e(Kit.ChunkText, {
			Text = if locked then "???" else track.Name,
			Scaled = true,
			Size = UDim2.fromOffset(240, 40),
			Position = UDim2.fromOffset(116, 14),
			Align = Enum.TextXAlignment.Left,
			TextSize = 36,
			Color = C.Cream,
		}),
		Sub = e(Kit.Text, {
			Text = if locked
				then "Locked"
				else string.format("%s  -  Level %d of %d", tool.Name, track.Level, track.MaxLevel),
			TextSize = 17,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(240, 22),
			Position = UDim2.fromOffset(116, 56),
		}),
		Pips = e(Kit.Pips, {
			Level = track.Level,
			Max = track.MaxLevel,
			Align = Enum.HorizontalAlignment.Left,
			PipWidth = pipWidth,
			PipHeight = 12,
			Size = UDim2.fromOffset(240, 16),
			Position = UDim2.fromOffset(116, 82),
		}),

		-- DIVIDER
		Divider = e("Frame", {
			Size = UDim2.fromOffset(340, 2),
			Position = UDim2.fromOffset(18, 114),
			BackgroundColor3 = C.IronDark,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}),

		-- DESCRIPTION
		Desc = e(Kit.Text, {
			Text = if locked
				then "Buy the " .. tool.Name .. " at the Tool Shop to reveal its upgrades."
				else track.Description,
			TextSize = 18,
			Color = C.Cream,
			Wrapped = true,
			VAlign = Enum.TextYAlignment.Top,
			Size = UDim2.fromOffset(340, 44),
			Position = UDim2.fromOffset(18, 122),
		}),

		-- NOW -> NEXT
		Now = e(ValueBox, {
			Caption = "NOW",
			Value = nowValue,
			Unit = nowUnit,
			Color = C.Cream,
			Position = UDim2.fromOffset(18, 172),
		}),
		Arrow = e(Kit.ChunkText, {
			Text = "→",
			TextSize = 38,
			Color = C.Amber,
			Size = UDim2.fromOffset(52, 90),
			Position = UDim2.fromOffset(162, 172),
		}),
		Next = e(ValueBox, {
			Caption = "NEXT",
			Value = nextValue,
			Unit = nextUnit,
			Color = if maxed then C.Amber else C.MoneyGreen,
			Edge = if locked then nil elseif maxed then C.Amber else C.Green,
			Position = UDim2.fromOffset(214, 172),
		}),
	}

	-- What you gain: its own row, with clear space above and below (never overlaps other text)
	if not locked and not maxed then
		kids.Gain = e(Kit.Plate, {
			Size = UDim2.fromOffset(190, 28),
			Position = UDim2.fromOffset(188, 286),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Fill = C.GreenDark,
			Edge = C.Green,
			Radius = 14,
			EdgeThickness = 2,
			Shadow = false,
		}, {
			Text = e(Kit.ChunkText, { Text = gain(tool.Id, track.Id), TextSize = 16, Stroke = 2, Drop = 1 }),
		})
	end

	if props.Celebrate > 0 then
		kids["Burst" .. props.Celebrate] = e(Effects.Burst, {
			OriginX = 60,
			OriginY = 58,
			Count = 18,
			Colors = { C.Amber, C.Cream, C.MoneyGreen },
			ZIndex = 11,
		})
		kids["LevelUp" .. props.Celebrate] = e(LevelUpText)
	end

	return e(Kit.Plate, {
		Size = UDim2.fromOffset(376, 316),
		Position = UDim2.fromOffset(0, 54),
		Fill = C.Slate,
		Edge = C.IronDark,
		Radius = 16,
	}, kids)
end

---------------------------------------------------------------------
-- The journal
---------------------------------------------------------------------
local function Journal(props)
	local state = Store.useStore()
	local sel, setSel = React.useState(function()
		for _, candidate in state.Tools do
			if candidate.Id == props.InitialTool then
				return { Tool = candidate.Id, Track = candidate.Tracks[1].Id }
			end
		end
		local first = state.Tools[1]
		return { Tool = first.Id, Track = first.Tracks[1].Id }
	end)
	local avail, setAvail = React.useState(workspace.CurrentCamera.ViewportSize)
	local appear = Kit.useEntrance()
	local wave = Kit.useWave(4)
	local celebrate, setCelebrate = React.useState(0)

	React.useEffect(function()
		local camera = workspace.CurrentCamera
		setAvail(camera.ViewportSize)
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setAvail(camera.ViewportSize)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local rootScale = props.RootScale or 1
	local fit = math.clamp(math.min(avail.X / rootScale / (W + 110), avail.Y / rootScale / (H + 110)), 0.35, 1.25)

	-- Find the selected tool and track
	local tool, track
	for _, candidate in state.Tools do
		if candidate.Id == sel.Tool then
			tool = candidate
			for _, t in candidate.Tracks do
				if t.Id == sel.Track then
					track = t
				end
			end
		end
	end
	if not tool or not track then
		tool = state.Tools[1]
		track = tool.Tracks[1]
	end

	-- LEVEL UP celebration: the selected upgrade's level went up
	local lastSeen = React.useRef({ Key = "", Level = -1 })
	React.useEffect(function()
		local key = tool.Id .. "/" .. track.Id
		local seen = lastSeen.current
		if seen.Key == key and track.Level > seen.Level then
			setCelebrate(function(n)
				return n + 1
			end)
		end
		lastSeen.current = { Key = key, Level = track.Level }
		return nil
	end, { tool.Id, track.Id, track.Level })

	local locked = not tool.Owned
	local maxed = track.Price == nil
	local affordable = not locked and not maxed and state.Money >= track.Price

	-- The cheapest upgrade among tools you own (used by the NEXT UPGRADE button)
	local goal
	for _, candidate in state.Tools do
		if candidate.Owned then
			for _, t in candidate.Tracks do
				if t.Price and (not goal or t.Price < goal.Track.Price) then
					goal = { Tool = candidate, Track = t }
				end
			end
		end
	end

	local function onSelect(toolId: string, trackId: string)
		setSel({ Tool = toolId, Track = trackId })
	end

	-- Tabs
	local toolCount = #state.Tools
	local tabWidth = math.floor((380 - 10 * (toolCount - 1)) / toolCount)
	local tabs = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, candidate in state.Tools do
		tabs["Tab" .. candidate.Id] = e(Tab, {
			LayoutOrder = index,
			Tool = candidate,
			Width = tabWidth,
			Selected = candidate.Id == tool.Id,
			Ready = candidate.Id ~= tool.Id and anyAffordable(candidate, state.Money),
			Wave = wave,
			OnSelect = function()
				if candidate.Id ~= sel.Tool then
					setSel({ Tool = candidate.Id, Track = candidate.Tracks[1].Id })
				end
			end,
		})
	end

	-- Tiles for the selected tool
	local levels, maxLevels = 0, 0
	for _, t in tool.Tracks do
		levels += t.Level
		maxLevels += t.MaxLevel
	end
	local tiles = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, TILE_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, t in tool.Tracks do
		tiles["Tile" .. t.Id] = e(Tile, {
			LayoutOrder = index,
			Tool = tool,
			Track = t,
			Money = state.Money,
			Wave = wave,
			Selected = t.Id == track.Id,
			OnSelect = function()
				onSelect(tool.Id, t.Id)
			end,
		})
	end

	-- Left page: the line under the detail card (always gives NEW information)
	local status
	if locked then
		status = e(Kit.Text, {
			Text = "Unlock the " .. tool.Name .. " at the Tool Shop",
			TextSize = 18,
			Color = C.BlueInk,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(376, 28),
			Position = UDim2.fromOffset(0, 376),
		})
	elseif maxed then
		status = e(Kit.Text, {
			Text = if goal then "Pick another upgrade to keep going" else "Everything is maxed. Nice!",
			TextSize = 18,
			Color = C.BlueInk,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(376, 28),
			Position = UDim2.fromOffset(0, 376),
		})
	elseif affordable then
		status = e(Kit.Text, {
			Text = "You'll have " .. Util.FormatCents(state.Money - track.Price) .. " left",
			TextSize = 18,
			Color = C.BlueInk,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(376, 28),
			Position = UDim2.fromOffset(0, 376),
		})
	else
		status = e(Effects.ProgressBar, {
			Fraction = state.Money / track.Price,
			Color = C.Amber,
			Text = "Need " .. Util.FormatCents(track.Price - state.Money) .. " more",
			TextSize = 17,
			Size = UDim2.fromOffset(376, 28),
			Position = UDim2.fromOffset(0, 376),
		})
	end

	-- Left page: the big button
	local buyKids
	if locked then
		buyKids = {
			Button = e(Kit.BigButton, {
				Text = "LOCKED",
				Variant = "gold",
				Disabled = true,
				TextSize = 24,
				Size = UDim2.fromScale(1, 1),
			}),
		}
	elseif maxed then
		if goal then
			buyKids = {
				Button = e(Kit.BigButton, {
					Text = "NEXT UPGRADE",
					Variant = "gold",
					TextSize = 26,
					Size = UDim2.fromScale(1, 1),
					OnActivated = function()
						onSelect(goal.Tool.Id, goal.Track.Id)
					end,
				}),
			}
		else
			buyKids = {
				Done = e(Kit.Plate, {
					Size = UDim2.fromScale(1, 1),
					Fill = C.AmberDark,
					Edge = C.Amber,
					Radius = 14,
				}, { Text = e(Kit.ChunkText, { Text = "ALL MAXED!", TextSize = 30, Color = C.Amber }) }),
			}
		end
	else
		buyKids = {
			Button = e(Kit.BigButton, {
				Text = "BUY  " .. Util.FormatCents(track.Price),
				Variant = "gold",
				Disabled = not affordable,
				TextSize = 28,
				Size = UDim2.fromScale(1, 1),
				OnActivated = function()
					Store.buyTrack(tool.Id, track.Id) -- intent only. The server decides.
				end,
			}),
		}
		if affordable then
			buyKids.Pulse = e("UIScale", {
				Scale = wave:map(function(w: number)
					return 1 + 0.035 * w
				end),
			})
		end
	end

	-- Little rivets in the iron frame's corners
	local rivets = {}
	for index, position in
		{ UDim2.fromOffset(8, 8), UDim2.fromOffset(W - 22, 8), UDim2.fromOffset(8, H - 22), UDim2.fromOffset(W - 22, H - 22) }
	do
		rivets["Rivet" .. index] = e("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = position,
			BackgroundColor3 = C.IronLight,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 1.5 }),
		})
	end

	local frameKids = {
		Scale = e("UIScale", {
			Scale = appear:map(function(a: number)
				return fit * (0.9 + 0.1 * a)
			end),
		}),
		Iron = e(Kit.Plate, {
			Size = UDim2.fromScale(1, 1),
			Fill = C.Iron,
			Radius = 22,
			EdgeThickness = 4,
		}),
		Paper = e(Kit.Plate, {
			Size = UDim2.fromOffset(860, 520),
			Position = UDim2.fromOffset(20, 20),
			Fill = C.Paper,
			Edge = C.IronDark,
			Radius = 12,
			Shadow = false,
			ZIndex = 2,
		}, {
			Spine = e("Frame", {
				Size = UDim2.new(0, 4, 1, -48),
				Position = UDim2.new(0.5, -2, 0, 24),
				BackgroundColor3 = C.PaperLine,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
			}),

			-- LEFT PAGE
			Left = e("Frame", {
				Size = UDim2.fromOffset(376, 472),
				Position = UDim2.fromOffset(28, 24),
				BackgroundTransparency = 1,
			}, {
				Title = e(Kit.ChunkText, {
					Text = "UPGRADES",
					Size = UDim2.fromOffset(376, 48),
					Align = Enum.TextXAlignment.Left,
					TextSize = 44,
					Color = C.Amber,
				}),
				Detail = e(Detail, {
					Tool = tool,
					Track = track,
					Celebrate = celebrate,
				}),
				Status = status,
				Buy = e("Frame", {
					Size = UDim2.fromOffset(340, 64),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(188, 440),
					BackgroundTransparency = 1,
				}, buyKids),
			}),

			-- RIGHT PAGE
			Right = e("Frame", {
				Size = UDim2.fromOffset(380, 472),
				Position = UDim2.fromOffset(452, 24),
				BackgroundTransparency = 1,
			}, {
				Tabs = e("Frame", {
					Size = UDim2.fromOffset(380, 52),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
				}, tabs),
				Well = e("Frame", {
					Size = UDim2.fromOffset(380, 340),
					Position = UDim2.fromOffset(0, 64),
					BackgroundColor3 = C.PaperDark,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
				}, {
					Corner = corner(16),
					Edge = e("UIStroke", { Color = C.PaperLine, Thickness = 2.5, Transparency = 0.3 }),
					Name = e(Kit.ChunkText, {
						Text = if tool.Owned then tool.Name else "???",
						Size = UDim2.fromOffset(250, 34),
						Position = UDim2.fromOffset(18, 10),
						Align = Enum.TextXAlignment.Left,
						TextSize = 28,
						Color = C.BlueInk,
						StrokeColor = C.Cream,
						Drop = 2,
						Stroke = 2.5,
					}),
					Count = e(Kit.Text, {
						Text = if tool.Owned then string.format("%d / %d", levels, maxLevels) else "LOCKED",
						TextSize = 18,
						Color = C.BlueInk,
						Align = Enum.TextXAlignment.Right,
						Size = UDim2.fromOffset(96, 34),
						Position = UDim2.fromOffset(266, 10),
					}),
					Bar = if tool.Owned
						then e(Effects.ProgressBar, {
							Fraction = levels / math.max(maxLevels, 1),
							Color = C.Amber,
							Radius = 6,
							Stroke = 2,
							Size = UDim2.fromOffset(344, 14),
							Position = UDim2.fromOffset(18, 52),
						})
						else nil,
					Tiles = e("Frame", {
						Size = UDim2.fromOffset(380, 250),
						Position = UDim2.fromOffset(0, 80),
						BackgroundTransparency = 1,
					}, tiles),
					Hint = if tool.Owned
						then nil
						else e(Kit.Text, {
							Text = "Buy the " .. tool.Name .. " at the Tool Shop to unlock",
							TextSize = 16,
							Color = C.BlueInk,
							Align = Enum.TextXAlignment.Center,
							Size = UDim2.fromOffset(380, 26),
							Position = UDim2.fromOffset(0, 308),
						}),
				}),
				Money = e(Kit.Plate, {
					Size = UDim2.fromOffset(380, 58),
					Position = UDim2.fromOffset(0, 414),
					Fill = C.IronDark,
					Radius = 14,
					EdgeThickness = 3,
					Shadow = false,
				}, {
					Caption = e(Kit.ChunkText, {
						Text = "your money:",
						Align = Enum.TextXAlignment.Left,
						TextSize = 22,
						Color = C.Cream,
						Size = UDim2.fromOffset(170, 58),
						Position = UDim2.fromOffset(16, 0),
					}),
					Amount = e(Kit.ChunkText, {
						Text = state.MoneyText,
						Align = Enum.TextXAlignment.Right,
						TextSize = 28,
						Color = C.MoneyGreen,
						Size = UDim2.fromOffset(186, 58),
						Position = UDim2.fromOffset(180, 0),
					}),
				}),
			}),
		}),

		Close = e(Kit.BigButton, {
			Text = "X",
			Variant = "red",
			ZIndex = 6,
			TextSize = 34,
			Size = UDim2.fromOffset(64, 64),
			Position = UDim2.fromOffset(W - 44, -28),
			OnActivated = props.OnClose,
		}),
	}
	for key, rivet in rivets do
		frameKids[key] = rivet
	end

	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		[React.Event.Activated] = props.OnClose, -- click outside to close
	}, {
		Frame = e("Frame", {
			Size = UDim2.fromOffset(W, H),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Active = true, -- clicks inside the journal don't close it
		}, frameKids),
	})
end

return Journal