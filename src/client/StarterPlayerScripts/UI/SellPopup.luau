local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Shared = ReplicatedStorage.Shared
local Util = require(Shared.Util)
local GameConfig = require(Shared.GameConfig)
local ItemDefinitions = require(Shared.ItemDefinitions)

local UI = script.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local e = React.createElement
local C = Theme.Colors

local SellResult = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellResult", 5)

local SHOW_SECONDS = 3.2
local EXIT_SECONDS = 0.4
local MAX_CHIPS = 5
local WIDTH = 380
local TOP_Y = 112
local COINS = 12
local COIN_X, COIN_Y = 35, 43 -- where the coin burst starts (inside the card)

---------------------------------------------------------------------
-- Coin burst: small gold discs fan upward, then fall and fade
---------------------------------------------------------------------
local function Burst()
	local p = Kit.useAppear(0.95)
	local seeds = React.useMemo(function()
		local list = {}
		for i = 1, COINS do
			local base = -150 + (i - 1) / (COINS - 1) * 120
			list[i] = {
				Angle = math.rad(base + math.random(-8, 8)),
				Speed = math.random(80, 170),
				Size = math.random(9, 15),
			}
		end
		return list
	end, {})

	local fade = p:map(function(a: number)
		return math.clamp((a - 0.5) / 0.5, 0, 1)
	end)

	local kids = {}
	for i, seed in seeds do
		kids["Coin" .. i] = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(seed.Size, seed.Size),
			Position = p:map(function(a: number)
				local x = COIN_X + math.cos(seed.Angle) * seed.Speed * a
				local y = COIN_Y + math.sin(seed.Angle) * seed.Speed * a + 150 * a * a
				return UDim2.fromOffset(x, y)
			end),
			BackgroundColor3 = C.Amber,
			BackgroundTransparency = fade,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 2, Transparency = fade }),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, kids)
end

---------------------------------------------------------------------
-- One item chip that pops in after a short delay
---------------------------------------------------------------------
local function Chip(props)
	local goal, setGoal = React.useState(0)
	React.useEffect(function()
		local thread = task.delay(props.Delay, function()
			setGoal(1)
		end)
		return function()
			pcall(task.cancel, thread)
		end
	end, {})
	local pop = Kit.useSpring(goal, 360, 15, 0)

	local width = math.max(56, #props.Text * 8 + 24)

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(width, 30),
		BackgroundTransparency = 1,
	}, {
		Body = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.Iron,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Body,
			Text = props.Text,
			TextColor3 = C.Cream,
			TextSize = 14,
		}, {
			Scale = e("UIScale", {
				Scale = pop:map(function(a: number)
					return math.max(a, 0.01)
				end),
			}),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Edge = e("UIStroke", { Color = props.Color, Thickness = 2 }),
		}),
	})
end

---------------------------------------------------------------------
-- The card
---------------------------------------------------------------------
local function Popup(props)
	local enter = Kit.useSpring(if props.Leaving then 0 else 1, 280, 15, 0)
	local count = Kit.useAppear(0.8)
	local wave = Kit.useWave(5)
	local lines = props.Lines

	local totalItems = 0
	for _, line in lines do
		totalItems += line.Count
	end

	-- Spinning coin (its width flips like a real coin)
	local coinImage = Theme.Icons and Theme.Icons.Coin
	local coinFace
	if coinImage and coinImage ~= "" then
		coinFace = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = coinImage,
			ScaleType = Enum.ScaleType.Stretch,
		})
	else
		coinFace = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.Amber,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 3 }),
			Sign = e(Kit.ChunkText, { Text = "$", TextSize = 26, Color = C.Cream, Stroke = 2 }),
		})
	end

	local chips = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local shown = math.min(#lines, MAX_CHIPS)
	for index = 1, shown do
		local line = lines[index]
		local item = ItemDefinitions[line.ItemId]
		local rarity = item and GameConfig.Rarities[item.Rarity]
		chips["Chip" .. index] = e(Chip, {
			LayoutOrder = index,
			Delay = 0.25 + index * 0.09,
			Text = string.format("%dx %s", line.Count, if item then item.DisplayName else tostring(line.ItemId)),
			Color = if rarity then rarity.Color else C.Ink,
		})
	end
	if #lines > MAX_CHIPS then
		chips.More = e(Chip, {
			LayoutOrder = MAX_CHIPS + 1,
			Delay = 0.25 + (MAX_CHIPS + 1) * 0.09,
			Text = string.format("+%d more", #lines - MAX_CHIPS),
			Color = C.PaperDark,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = enter:map(function(a: number)
			return UDim2.new(0.5, 0, 0, TOP_Y - 70 * (1 - a))
		end),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Pop = e("UIScale", {
			Scale = enter:map(function(a: number)
				return math.max(0.8 + 0.2 * a, 0.5)
			end),
		}),
		Body = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.IronDark,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 18) }),
			Edge = e("UIStroke", { Color = C.Amber, Thickness = 3.5 }),
			Sheen = e("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(120, 130, 175), Color3.fromRGB(70, 74, 100)),
				Rotation = 90,
			}),
			Pad = e("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 14),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 14),
			}),
			Layout = e("UIListLayout", {
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Header = e("Frame", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 62),
				BackgroundTransparency = 1,
			}, {
				CoinSlot = e("Frame", {
					Size = UDim2.fromOffset(46, 46),
					Position = UDim2.fromOffset(0, 8),
					BackgroundTransparency = 1,
				}, {
					Spinner = e("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = wave:map(function(w: number)
							return UDim2.fromOffset(math.max(8, 46 * math.abs(w)), 46)
						end),
						BackgroundTransparency = 1,
					}, { Face = coinFace }),
				}),
				Label = e(Kit.ChunkText, {
					Text = "SOLD!",
					TextSize = 18,
					Color = C.Cream,
					Align = Enum.TextXAlignment.Left,
					Size = UDim2.fromOffset(120, 22),
					Position = UDim2.fromOffset(62, 2),
				}),
				Total = e(Kit.ChunkText, {
					Text = count:map(function(a: number)
						return "+" .. Util.FormatCents(math.floor(props.Total * a + 0.5))
					end),
					TextSize = 40,
					Color = C.MoneyGreen,
					Align = Enum.TextXAlignment.Left,
					Size = UDim2.fromOffset(220, 42),
					Position = UDim2.fromOffset(62, 20),
				}),
				Items = e(Kit.Text, {
					Text = string.format("%d items", totalItems),
					TextSize = 15,
					Color = C.PaperDark,
					Align = Enum.TextXAlignment.Right,
					Size = UDim2.fromOffset(90, 20),
					Position = UDim2.new(1, -90, 0, 6),
				}),
			}),
			Chips = e("Frame", {
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, chips),
		}),
		Burst = e(Burst),
	})
end

local function SellPopup()
	local current, setCurrent = React.useState(nil)

	React.useEffect(function()
		if not SellResult then
			return nil
		end
		local counter = 0
		local connection = SellResult.OnClientEvent:Connect(function(summary)
			if typeof(summary) ~= "table" then
				return
			end
			counter += 1
			local id = counter
			setCurrent({
				Id = id,
				Lines = summary.Lines or {},
				Total = summary.TotalCents or 0,
				Leaving = false,
			})
			task.delay(SHOW_SECONDS, function()
				setCurrent(function(old)
					if old and old.Id == id then
						return { Id = id, Lines = old.Lines, Total = old.Total, Leaving = true }
					end
					return old
				end)
			end)
			task.delay(SHOW_SECONDS + EXIT_SECONDS, function()
				setCurrent(function(old)
					if old and old.Id == id then
						return nil
					end
					return old
				end)
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local kids = {}
	if current then
		kids["Popup" .. current.Id] = e(Popup, {
			Lines = current.Lines,
			Total = current.Total,
			Leaving = current.Leaving,
		})
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, kids)
end

return SellPopup