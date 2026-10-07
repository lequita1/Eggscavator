local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Shared = ReplicatedStorage.Shared
local Util = require(Shared.Util)
local GameConfig = require(Shared.GameConfig)
local ToolDefinitions = require(Shared.ToolDefinitions)

local UI = script.Parent
local Theme = require(UI.Theme)
local Store = require(UI.Store)
local Kit = require(UI.Kit)
local Effects = require(UI.Effects)

local e = React.createElement
local C = Theme.Colors
local player = Players.LocalPlayer

local W, H = 720, 744

local function corner(radius: number)
	return e("UICorner", { CornerRadius = UDim.new(0, radius) })
end

---------------------------------------------------------------------
-- Stat comparison (display only): Power = damage per second, Tier = tool power, Reach = studs
---------------------------------------------------------------------
local function statsFor(toolId: string)
	local d = ToolDefinitions[toolId]
	return { Power = d.Damage / d.AttackInterval, Haul = d.Power, Reach = d.Range }
end

local MAX_STAT = { Power = 1, Haul = 1, Reach = 1 }
for toolId in ToolDefinitions do
	for key, value in statsFor(toolId) do
		MAX_STAT[key] = math.max(MAX_STAT[key], value)
	end
end

local function StatRow(props)
	return e("Frame", {
		Size = UDim2.fromOffset(156, 18),
		Position = UDim2.fromOffset(8, props.Y),
		BackgroundTransparency = 1,
	}, {
		Label = e(Kit.Text, {
			Text = props.Label,
			TextSize = 12,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(48, 18),
		}),
		Bar = e(Effects.ProgressBar, {
			Fraction = props.Value / props.Max,
			Color = props.Color,
			Size = UDim2.fromOffset(70, 10),
			Position = UDim2.fromOffset(50, 4),
			Radius = 5,
			Stroke = 2,
		}),
		Value = e(Kit.Text, {
			Text = props.Text,
			TextSize = 13,
			Color = C.Cream,
			Align = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(32, 18),
			Position = UDim2.fromOffset(124, 0),
		}),
	})
end

---------------------------------------------------------------------
-- One tool showcase card
---------------------------------------------------------------------
local function ToolCard(props)
	local tool = props.Tool
	local owned = tool.Owned
	local price = tool.Price or 0
	local money = props.Money
	local affordable = not owned and money >= price
	local wave = props.Wave
	local celebrate, setCelebrate = React.useState(0)

	-- Celebrate the moment this tool becomes owned
	local wasOwned = React.useRef(owned)
	React.useEffect(function()
		if owned and not wasOwned.current then
			setCelebrate(function(n)
				return n + 1
			end)
		end
		wasOwned.current = owned
		return nil
	end, { owned })

	local stats = statsFor(tool.Id)
	local image = Theme.Icons and Theme.Icons[tool.Id]

	local icon
	if image and image ~= "" then
		icon = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(84, 84),
			Position = if owned
				then UDim2.fromScale(0.5, 0.5)
				else wave:map(function(w: number)
					return UDim2.new(0.5, 0, 0.5, w * 3)
				end),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		})
	else
		icon = e(Kit.ChunkText, {
			Text = string.upper(string.sub(tool.Name, 1, 1)),
			TextSize = 52,
			ZIndex = 2,
		})
	end

	-- One status line per state: bar (can't afford yet), nothing (can buy), hint (owned)
	local status
	if owned then
		status = e(Kit.Text, {
			Text = "In your hotbar",
			TextSize = 13,
			Color = C.MoneyGreen,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(172, 18),
			Position = UDim2.fromOffset(14, 274),
		})
	elseif not affordable then
		status = e(Effects.ProgressBar, {
			Fraction = money / math.max(price, 1),
			Color = C.Amber,
			Text = Util.FormatCents(money) .. " / " .. Util.FormatCents(price),
			TextSize = 12,
			Size = UDim2.fromOffset(172, 18),
			Position = UDim2.fromOffset(14, 274),
			Radius = 9,
		})
	end

	local actionKids
	if owned then
		actionKids = {
			Button = e(Kit.BigButton, {
				Text = "UPGRADE",
				Variant = "iron",
				TextSize = 20,
				Size = UDim2.fromScale(1, 1),
				OnActivated = function()
					if props.OnUpgrade then
						props.OnUpgrade(tool.Id)
					end
				end,
			}),
		}
	else
		actionKids = {
			Button = e(Kit.BigButton, {
				Text = "BUY  " .. Util.FormatCents(price),
				Variant = "gold",
				Disabled = not affordable,
				TextSize = 20,
				Size = UDim2.fromScale(1, 1),
				OnActivated = function()
					Store.buyTool(tool.Id) -- intent only. The server checks money and distance.
				end,
			}),
		}
		if affordable then
			actionKids.Pulse = e("UIScale", {
				Scale = wave:map(function(w: number)
					return 1 + 0.035 * w
				end),
			})
		end
	end

	local cardKids = {
		Well = e("Frame", {
			Size = UDim2.fromOffset(172, 104),
			Position = UDim2.fromOffset(14, 14),
			BackgroundColor3 = C.IronDark,
			BorderSizePixel = 0,
		}, {
			Corner = corner(14),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 2.5 }),
			Icon = icon,
			Ribbon = if owned
				then e("Frame", {
					Size = UDim2.fromOffset(72, 20),
					Position = UDim2.fromOffset(8, 8),
					BackgroundColor3 = C.GreenDark,
					BorderSizePixel = 0,
					ZIndex = 4,
				}, {
					Corner = corner(6),
					Edge = e("UIStroke", { Color = C.Ink, Thickness = 2 }),
					Text = e(Kit.ChunkText, {
						Text = if price == 0 then "STARTER" else "OWNED",
						TextSize = 12,
						Stroke = 2,
						Drop = 1,
						ZIndex = 5,
					}),
				})
				else nil,
		}),
		Name = e(Kit.ChunkText, {
			Text = tool.Name,
			TextSize = 26,
			Size = UDim2.fromOffset(200, 30),
			Position = UDim2.fromOffset(0, 124),
		}),
		Desc = e(Kit.Text, {
			Text = tool.Description or "",
			TextSize = 13,
			Color = C.PaperDark,
			Wrapped = true,
			Align = Enum.TextXAlignment.Center,
			VAlign = Enum.TextYAlignment.Top,
			Size = UDim2.fromOffset(172, 36),
			Position = UDim2.fromOffset(14, 156),
		}),
		Stats = e("Frame", {
			Size = UDim2.fromOffset(172, 68),
			Position = UDim2.fromOffset(14, 198),
			BackgroundColor3 = C.IronDark,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, {
			Corner = corner(10),
			Power = e(StatRow, {
				Y = 5,
				Label = "POWER",
				Value = stats.Power,
				Max = MAX_STAT.Power,
				Color = C.Amber,
				Text = string.format("%d/s", math.floor(stats.Power + 0.5)),
			}),
			Haul = e(StatRow, {
				Y = 25,
				Label = "TIER",
				Value = stats.Haul,
				Max = MAX_STAT.Haul,
				Color = C.Clay,
				Text = string.format("%d", math.floor(stats.Haul + 0.5)),
			}),
			Reach = e(StatRow, {
				Y = 45,
				Label = "REACH",
				Value = stats.Reach,
				Max = MAX_STAT.Reach,
				Color = C.Slate,
				Text = string.format("%d", math.floor(stats.Reach + 0.5)),
			}),
		}),
		Status = status,
		Action = e("Frame", {
			Size = UDim2.fromOffset(172, 48),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(100, 324),
			BackgroundTransparency = 1,
		}, actionKids),
	}

	local kids = {
		Card = e(Kit.Plate, {
			Size = UDim2.fromScale(1, 1),
			Fill = if owned then C.Slate else C.Iron,
			Edge = if owned then C.GreenDark elseif affordable then C.Green else C.Ink,
			Radius = 16,
			EdgeThickness = 3,
		}, cardKids),
	}
	if celebrate > 0 then
		kids["Burst" .. celebrate] = e(Effects.Burst, {
			OriginX = 100,
			OriginY = 66,
			Count = 22,
			Colors = { C.Amber, C.Cream, C.MoneyGreen, C.Clay },
			ZIndex = 12,
		})
	end

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(200, 362),
		BackgroundTransparency = 1,
	}, kids)
end

---------------------------------------------------------------------
-- Gear strip: one row for a gear track (Storage or Pickup)
-- props: Position, Wave, Money, Kind, Name, Tier, Total, NextPrice (nil = maxed), Desc, Fill, OnBuy
---------------------------------------------------------------------
local function GearStrip(props)
	local affordable = props.NextPrice ~= nil and props.Money >= props.NextPrice

	local actionKids
	if props.NextPrice then
		actionKids = {
			Button = e(Kit.BigButton, {
				Text = "BUY  " .. Util.FormatCents(props.NextPrice),
				Variant = "gold",
				Disabled = not affordable,
				TextSize = 20,
				Size = UDim2.fromScale(1, 1),
				OnActivated = function()
					props.OnBuy() -- intent only. The server picks the tier and checks money.
				end,
			}),
		}
		if affordable then
			actionKids.Pulse = e("UIScale", {
				Scale = props.Wave:map(function(w: number)
					return 1 + 0.035 * w
				end),
			})
		end
	else
		actionKids = {
			Done = e(Kit.ChunkText, { Text = "MAXED!", TextSize = 28, Color = C.Amber }),
		}
	end

	return e(Kit.Plate, {
		Position = props.Position,
		Size = UDim2.fromOffset(640, 84),
		Fill = C.Iron,
		Edge = if affordable then C.Green else C.Ink,
		Radius = 16,
		EdgeThickness = 3,
	}, {
		Icon = e(Kit.Plate, {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(14, 12),
			Fill = props.Fill,
			Radius = 12,
			Shadow = false,
		}, { Sign = e(Kit.ChunkText, { Text = "+", TextSize = 42, ZIndex = 3 }) }),
		Name = e(Kit.ChunkText, {
			Text = props.Name,
			TextSize = 24,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(180, 28),
			Position = UDim2.fromOffset(90, 6),
		}),
		Tier = e(Kit.Text, {
			Text = string.format("%s %d/%d", props.Kind, props.Tier, props.Total),
			TextSize = 13,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(110, 28),
			Position = UDim2.fromOffset(280, 6),
		}),
		Desc = e(Kit.Text, {
			Text = props.Desc,
			TextSize = 14,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(330, 20),
			Position = UDim2.fromOffset(90, 34),
		}),
		Pips = e(Kit.Pips, {
			Level = props.Tier,
			Max = props.Total,
			Align = Enum.HorizontalAlignment.Left,
			PipWidth = 26,
			PipHeight = 9,
			Size = UDim2.fromOffset(300, 12),
			Position = UDim2.fromOffset(90, 60),
		}),
		Action = e("Frame", {
			Size = UDim2.fromOffset(190, 52),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -116, 0.5, 0),
			BackgroundTransparency = 1,
		}, actionKids),
	})
end

-- Storage: pick any bag size you can afford (sizes come from GameConfig + BagTier)
local function StorageStrip(props)
	local state = Store.useStore()
	local upgrades = GameConfig.Inventory.CapacityUpgrades
	local tier = state.BagTier
	local current = if tier > 0 then upgrades[tier] else nil
	local capacity = if current then current.Capacity else GameConfig.Inventory.StartingCapacity
	local name = if current then current.Name else GameConfig.Inventory.StartingName

	local anyAffordable = false
	for index = tier + 1, #upgrades do
		if state.Money >= upgrades[index].Price then
			anyAffordable = true
		end
	end

	local kids = {
		Icon = e(Kit.Plate, {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(14, 12),
			Fill = C.Clay,
			Radius = 12,
			Shadow = false,
		}, { Sign = e(Kit.ChunkText, { Text = string.upper(string.sub(name, 1, 1)), TextSize = 38, ZIndex = 3 }) }),
		Name = e(Kit.ChunkText, {
			Text = name,
			TextSize = 18,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(124, 28),
			Position = UDim2.fromOffset(82, 12),
		}),
		Carry = e(Kit.Text, {
			Text = string.format("Carries %d", capacity),
			TextSize = 14,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(124, 20),
			Position = UDim2.fromOffset(82, 44),
		}),
	}

	for index, upgrade in upgrades do
		local yours = index == tier
		local owned = index <= tier
		local affordable = index > tier and state.Money >= upgrade.Price
		local priceText = if yours then "YOURS" elseif owned then "SMALLER" else Util.FormatCents(upgrade.Price)
		kids["Bag" .. index] = e(Kit.Plate, {
			Size = UDim2.fromOffset(100, 68),
			Position = UDim2.fromOffset(208 + (index - 1) * 106, 8),
			Fill = if yours then C.Amber elseif affordable then C.Clay else C.IronDark,
			Edge = if affordable then C.Green else C.Ink,
			EdgeThickness = 3,
			Radius = 12,
			Shadow = false,
		}, {
			BagName = e(Kit.ChunkText, {
				Text = upgrade.Name,
				TextSize = 14,
				Stroke = 2,
				Drop = 2,
				Size = UDim2.fromOffset(100, 22),
				Position = UDim2.fromOffset(0, 4),
				ZIndex = 3,
			}),
			BagCarry = e(Kit.ChunkText, {
				Text = "carry " .. upgrade.Capacity,
				TextSize = 13,
				Stroke = 2,
				Drop = 2,
				Color = C.Cream,
				Size = UDim2.fromOffset(100, 20),
				Position = UDim2.fromOffset(0, 26),
				ZIndex = 3,
			}),
			BagPrice = e(Kit.ChunkText, {
				Text = priceText,
				TextSize = 16,
				Stroke = 2,
				Drop = 2,
				Color = if affordable then C.MoneyGreen elseif owned then C.Cream else C.PaperDark,
				Size = UDim2.fromOffset(100, 22),
				Position = UDim2.fromOffset(0, 44),
				ZIndex = 3,
			}),
			Hit = e("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = 6,
				[React.Event.Activated] = function()
					if index > tier then
						Store.buyBagTier(index) -- intent only. The server checks the size and the money.
					end
				end,
			}),
		})
	end

	return e(Kit.Plate, {
		Position = props.Position,
		Size = UDim2.fromOffset(640, 84),
		Fill = C.Iron,
		Edge = if anyAffordable then C.Green else C.Ink,
		Radius = 16,
		EdgeThickness = 3,
	}, kids)
end

-- Climb Rig: the rig, then ladder levels 2 to 5 (tiers come from GameConfig.Climb + ClimbTier)
local function ClimbStrip(props)
	local state = Store.useStore()
	local tiers = GameConfig.Climb.Tiers
	local tier = state.ClimbTier or 0
	local nextTier = tiers[tier + 1]
	local current = if tier > 0 then tiers[tier] else nil

	return e(GearStrip, {
		Position = props.Position,
		Wave = props.Wave,
		Money = state.Money,
		Kind = "Ladder",
		Name = if current then current.Name else "No Ladder yet",
		Tier = tier,
		Total = #tiers,
		NextPrice = if nextTier then nextTier.Price else nil,
		Desc = if nextTier
			then string.format("%s: %s", nextTier.Name, nextTier.Description)
			else "Your ladder is built as high as it goes.",
		Fill = C.Clay,
		OnBuy = Store.buyClimbUpgrade,
	})
end

-- Pickup gear: Bare Hands, Brush, Vacuum (tiers come from GameConfig + PickupTier)
local function PickupStrip(props)
	local state = Store.useStore()
	local upgrades = GameConfig.Pickup.Upgrades
	local tier = state.PickupTier
	local nextUpgrade = upgrades[tier + 1]
	local current = if tier > 0 then upgrades[tier] else nil

	return e(GearStrip, {
		Position = props.Position,
		Wave = props.Wave,
		Money = state.Money,
		Kind = "Pickup",
		Name = if current then current.Name else GameConfig.Pickup.Start.Name,
		Tier = tier,
		Total = #upgrades,
		NextPrice = if nextUpgrade then nextUpgrade.Price else nil,
		Desc = if nextUpgrade
			then string.format("%s: %s", nextUpgrade.Name, nextUpgrade.Description)
			else "Your pickup gear is as good as it gets.",
		Fill = C.Slate,
		OnBuy = Store.buyPickupUpgrade,
	})
end

---------------------------------------------------------------------
-- The shop
---------------------------------------------------------------------
local function ShopPanel(props)
	local state = Store.useStore()
	local appear = Kit.useEntrance()
	local wave = Kit.useWave(3)
	local avail, setAvail = React.useState(workspace.CurrentCamera.ViewportSize)

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

	local cards = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 20),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, tool in state.Tools do
		cards["Tool" .. tool.Id] = e(ToolCard, {
			LayoutOrder = index,
			Tool = tool,
			Money = state.Money,
			Wave = wave,
			OnUpgrade = props.OnUpgrade,
		})
	end

	local coinImage = Theme.Icons and Theme.Icons.Coin

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
			Active = true, -- clicks inside don't close it
		}, {
			Scale = e("UIScale", {
				Scale = appear:map(function(a: number)
					return fit * (0.9 + 0.1 * a)
				end),
			}),
			Body = e(Kit.Plate, {
				Size = UDim2.fromScale(1, 1),
				Fill = C.IronDark,
				Radius = 22,
				EdgeThickness = 4,
			}, {
				Title = e(Kit.ChunkText, {
					Text = "TOOL SHOP",
					TextSize = 38,
					Color = C.Amber,
					Align = Enum.TextXAlignment.Left,
					Size = UDim2.fromOffset(300, 48),
					Position = UDim2.fromOffset(40, 12),
				}),
				MoneyPill = e(Kit.Plate, {
					Size = UDim2.fromOffset(200, 42),
					Position = UDim2.fromOffset(W - 260, 16),
					Fill = C.Iron,
					Radius = 12,
					EdgeThickness = 3,
					Shadow = false,
				}, {
					Coin = if coinImage and coinImage ~= ""
						then e("ImageLabel", {
							Size = UDim2.fromOffset(30, 30),
							Position = UDim2.fromOffset(8, 6),
							BackgroundTransparency = 1,
							Image = coinImage,
							ScaleType = Enum.ScaleType.Fit,
							ZIndex = 3,
						})
						else nil,
					Amount = e(Kit.ChunkText, {
						Text = state.MoneyText,
						TextSize = 24,
						Color = C.MoneyGreen,
						Align = Enum.TextXAlignment.Right,
						Size = UDim2.fromOffset(148, 42),
						Position = UDim2.fromOffset(44, 0),
					}),
				}),
				Divider = e("Frame", {
					Size = UDim2.fromOffset(W - 80, 2),
					Position = UDim2.fromOffset(40, 66),
					BackgroundColor3 = C.IronLight,
					BackgroundTransparency = 0.55,
					BorderSizePixel = 0,
				}),
				Cards = e("Frame", {
					Size = UDim2.fromOffset(W - 80, 362),
					Position = UDim2.fromOffset(40, 74),
					BackgroundTransparency = 1,
				}, cards),
				Storage = e(StorageStrip, { Position = UDim2.fromOffset(40, 450), Wave = wave }),
				Pickup = e(PickupStrip, { Position = UDim2.fromOffset(40, 544), Wave = wave }),
				Climb = e(ClimbStrip, { Position = UDim2.fromOffset(40, 638), Wave = wave }),
			}),
			Close = e(Kit.BigButton, {
				Text = "X",
				Variant = "red",
				TextSize = 34,
				ZIndex = 6,
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.fromOffset(W - 44, -28),
				OnActivated = props.OnClose,
			}),
		}),
	})
end

return ShopPanel