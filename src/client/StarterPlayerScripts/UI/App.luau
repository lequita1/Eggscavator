local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Util = require(ReplicatedStorage.Shared.Util)

local UI = script.Parent
local Theme = require(UI.Theme)
local Store = require(UI.Store)
local Kit = require(UI.Kit)
local Journal = require(UI.Journal)
local Hotbar = require(UI.Hotbar)
local ShopPanel = require(UI.ShopPanel)
local okStage, ShopStage = pcall(function()
	return require(UI.ShopStage)
end)
local ShopView = if okStage then ShopStage else ShopPanel
if not okStage then
	warn("[UI.App] ShopStage failed, using the old shop panel: " .. tostring(ShopStage))
end
local SellPopup = require(UI.SellPopup)
local Notifications = require(UI.Notifications)
local Results = require(script.Parent.Results)
local LootFeed = require(script.Parent.LootFeed)
local Announcer = require(script.Parent.Announcer)
local Sounds = require(script.Parent.Sounds)

local e = React.createElement
local C = Theme.Colors

local TOP = 14
local SHOP_CLOSE_DISTANCE = 30 -- studs from the shop counter
local TeleportRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TeleportRequest", 5)

local OBJECTIVES = {
	Playing = "Crack the egg, collect the pieces, sell them, upgrade your tools!",
	CoreReady = "The Core is revealed! Grab it!",
	Carrying = "Everyone is carrying the Core. Deliver it to the golden pillar!",
	Ended = "Round complete!",
}

local function formatTime(totalSeconds: number): string
	local seconds = math.floor(math.max(totalSeconds, 0))
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

-- An uploaded icon id from Theme.Icons, or nil if that slot is still empty
local function iconImage(kind: string): string?
	local id = Theme.Icons and Theme.Icons[kind]
	if id and id ~= "" then
		return id
	end
	return nil
end

local function useViewportScale()
	local camera = workspace.CurrentCamera
	local scale, setScale = React.useState(function()
		return math.clamp(camera.ViewportSize.Y / 720, 0.7, 1.5)
	end)
	React.useEffect(function()
		local function update()
			setScale(math.clamp(camera.ViewportSize.Y / 720, 0.7, 1.5))
		end
		update()
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		return function()
			connection:Disconnect()
		end
	end, {})
	return scale
end

-- 0 -> 1 -> 0 over 0.3s every time `trigger` changes (skips the first render)
local function usePulse(trigger: any)
	local alpha, setAlpha = React.useBinding(0)
	local skip = React.useRef(true)
	React.useEffect(function()
		if skip.current then
			skip.current = false
			return nil
		end
		local start = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.clamp((os.clock() - start) / 0.3, 0, 1)
			setAlpha(math.sin(t * math.pi))
			if t >= 1 then
				connection:Disconnect()
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { trigger })
	return alpha
end

---------------------------------------------------------------------
-- Bottom-left: timer, money, bag
---------------------------------------------------------------------
local function Timer(props)
	local round = Store.useRound()
	local text, setText = React.useState("00:00:00")

	React.useEffect(function()
		local alive = true
		task.spawn(function()
			while alive do
				if round.Start then
					setText(formatTime((round.End or workspace:GetServerTimeNow()) - round.Start))
				else
					setText("00:00:00")
				end
				task.wait(0.25)
			end
		end)
		return function()
			alive = false
		end
	end, { round.Start, round.End })

	return e(Kit.Plate, {
		Size = UDim2.fromOffset(116, 40),
		LayoutOrder = props.LayoutOrder,
		Fill = C.IronDark,
		Radius = 12,
		EdgeThickness = 3,
		Shadow = false,
	}, {
		Text = e(Kit.ChunkText, { Text = text, TextSize = 19, Stroke = 2, Drop = 2 }),
	})
end

local function GainFloat(props)
	local p = Kit.useAppear(1.1)
	local fade = p:map(function(a: number)
		return math.clamp((a - 0.55) / 0.45, 0, 1)
	end)
	return e("TextLabel", {
		Size = UDim2.fromOffset(200, 30),
		Position = p:map(function(a: number)
			return UDim2.new(0, 66, 0, -8 - 34 * a)
		end),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Display,
		Text = props.Text,
		TextSize = 26,
		TextColor3 = C.MoneyGreen,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = fade,
		ZIndex = 10,
	}, {
		Stroke = e("UIStroke", { Thickness = 2.5, Color = C.Ink, Transparency = fade }),
	})
end

local function MoneyCard(props)
	local state = Store.useStore()
	local pulse = usePulse(state.Money)
	local coinImage = iconImage("Coin")

	local floats, setFloats = React.useState({})
	local lastMoney = React.useRef(state.Money)
	local floatId = React.useRef(0)
	local mountTime = React.useRef(os.clock())

	React.useEffect(function()
		local delta = state.Money - lastMoney.current
		lastMoney.current = state.Money
		-- ignore the initial data load in the first seconds
		if delta > 0 and os.clock() - mountTime.current > 3 then
			floatId.current += 1
			local id = floatId.current
			setFloats(function(old)
				local new = table.clone(old)
				new["Gain" .. id] = "+" .. Util.FormatCents(delta)
				return new
			end)
			task.delay(1.2, function()
				setFloats(function(old)
					local new = table.clone(old)
					new["Gain" .. id] = nil
					return new
				end)
			end)
		end
	end, { state.Money })

	local coin
	if coinImage then
		coin = e("ImageLabel", {
			Size = UDim2.fromOffset(46, 46),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Image = coinImage,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		coin = e("Frame", {
			Size = UDim2.fromOffset(42, 42),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = C.Amber,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 3 }),
			Inner = e("Frame", {
				Size = UDim2.new(1, -12, 1, -12),
				Position = UDim2.fromOffset(6, 6),
				BackgroundColor3 = C.AmberDark,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
			}, { Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
			Sign = e(Kit.ChunkText, { Text = "$", TextSize = 26, Color = C.Cream, Stroke = 2 }),
		})
	end

	local kids = {
		Coin = coin,
		Amount = e("Frame", {
			Size = UDim2.new(1, -78, 0, 44),
			Position = UDim2.new(0, 64, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
		}, {
			Pop = e("UIScale", {
				Scale = pulse:map(function(a: number)
					return 1 + 0.12 * a
				end),
			}),
			Text = e(Kit.ChunkText, {
				Text = state.MoneyText,
				Color = C.MoneyGreen,
				Scaled = true,
				TextSize = 36,
				Align = Enum.TextXAlignment.Left,
			}),
		}),
	}
	for key, text in floats do
		kids[key] = e(GainFloat, { Text = text })
	end

	return e(Kit.Plate, {
		Size = UDim2.fromOffset(280, 66),
		LayoutOrder = props.LayoutOrder,
		Fill = C.Iron,
	}, kids)
end

local function BagCard(props)
	local state = Store.useStore()
	local capacity = math.max(state.Capacity, 1)
	local fraction = math.clamp(state.Carried / capacity, 0, 1)
	local full = state.Carried >= capacity
	local barColor = if full then C.Red elseif fraction >= 0.75 then C.Amber else C.Green
	local fillSpring = Kit.useSpring(fraction, 200, 20, fraction)

	return e(Kit.Plate, {
		Size = UDim2.fromOffset(280, 66),
		LayoutOrder = props.LayoutOrder,
		Fill = C.Iron,
	}, {
		Badge = e(Kit.Plate, {
			Size = UDim2.fromOffset(78, 38),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Fill = C.Slate,
			Radius = 10,
			EdgeThickness = 2.5,
			Shadow = false,
		}, {
			Text = e(Kit.ChunkText, { Text = "MAX " .. capacity, TextSize = 16, Stroke = 2, Drop = 2 }),
		}),
		Track = e("Frame", {
			Size = UDim2.new(1, -112, 0, 34),
			Position = UDim2.new(0, 98, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = C.IronDark,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
			Edge = e("UIStroke", { Color = if full then C.Red else C.Ink, Thickness = 3 }),
			Fill = e("Frame", {
				Size = fillSpring:map(function(a: number)
					return UDim2.fromScale(math.clamp(a, 0, 1), 1)
				end),
				BackgroundColor3 = barColor,
				BorderSizePixel = 0,
			}, {
				Sheen = e("UIGradient", {
					Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 160)),
					Rotation = 90,
				}),
			}),
			Text = e(Kit.ChunkText, {
				Text = if full then "FULL" else (state.Carried .. " / " .. capacity),
				TextSize = 18,
				Stroke = 2,
				Drop = 2,
				ZIndex = 3,
			}),
		}),
	})
end

---------------------------------------------------------------------
-- Top center: teleport buttons + objective
---------------------------------------------------------------------
local function ButtonContent(text: string, image: string?)
	if not image then
		return nil
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Icon = e("ImageLabel", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(32, 32),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Label = e(Kit.ChunkText, {
			LayoutOrder = 2,
			Text = text,
			TextSize = 20,
			Size = UDim2.fromOffset(90, 40),
		}),
	})
end

local function TopButtons()
	local round = Store.useRound()
	local cooling, setCooling = React.useState(false)
	local blocked = round.State == "Carrying" or round.State == "Ended"

	local function go(station: string)
		if cooling or blocked then
			return
		end
		if TeleportRequest then
			TeleportRequest:FireServer(station) -- intent only. The server moves you.
		end
		setCooling(true)
		task.delay(1.5, function()
			setCooling(false)
		end)
	end

	local off = cooling or blocked

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP),
		Size = UDim2.fromOffset(316, 52),
		BackgroundTransparency = 1,
	}, {
		Sell = e(Kit.BigButton, {
			Text = "Sell Loot",
			Content = ButtonContent("Sell Loot", iconImage("Sell")),
			Variant = "green",
			Disabled = off,
			Size = UDim2.fromOffset(154, 52),
			Position = UDim2.fromOffset(0, 0),
			OnActivated = function()
				go("Sell")
			end,
		}),
		Tools = e(Kit.BigButton, {
			Text = "Tools",
			Content = ButtonContent("Tools", iconImage("Shop")),
			Variant = "iron",
			Disabled = off,
			Size = UDim2.fromOffset(154, 52),
			Position = UDim2.fromOffset(162, 0),
			OnActivated = function()
				go("Shop")
			end,
		}),
	})
end

local function Objective()
	local round = Store.useRound()
	return e(Kit.ChunkText, {
		Text = OBJECTIVES[round.State] or "",
		Color = C.Amber,
		Scaled = true,
		TextSize = 20,
		Stroke = 2.5,
		Drop = 2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP + 62),
		Size = UDim2.new(0.7, 0, 0, 30),
	})
end

---------------------------------------------------------------------
-- Right: upgrades button
---------------------------------------------------------------------
local function UpgradeButton(props)
	local state = Store.useStore()
	local image = iconImage("Upgrades")
	local bob = Kit.useWave(2.6)

	-- Can the player buy any upgrade right now? (display only; the server still checks)
	local ready = false
	for _, tool in state.Tools do
		if tool.Owned then
			for _, track in tool.Tracks do
				if track.Price and state.Money >= track.Price then
					ready = true
				end
			end
		end
	end

	local symbol
	if image then
		symbol = e("ImageLabel", {
			Size = UDim2.fromOffset(52, 52),
			Position = bob:map(function(w: number)
				return UDim2.new(0.5, 0, 0, 8 + w * 3)
			end),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		symbol = e(Kit.ChunkText, {
			Text = "▲",
			TextSize = 44,
			Size = UDim2.new(1, 0, 0, 60),
			Position = bob:map(function(w: number)
				return UDim2.fromOffset(0, 8 + w * 3)
			end),
		})
	end

	return e(Kit.BigButton, {
		Variant = "gold",
		Size = UDim2.fromOffset(100, 100),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		OnActivated = props.OnActivated,
		Content = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Symbol = symbol,
			Name = e(Kit.ChunkText, {
				Text = "UPGRADES",
				TextSize = 15,
				Stroke = 2.5,
				Drop = 2,
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.new(0, 0, 1, -30),
			}),
			Badge = if ready
				then e("Frame", {
					Size = UDim2.fromOffset(30, 30),
					Position = UDim2.new(1, -4, 0, 6),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = C.Red,
					BorderSizePixel = 0,
					ZIndex = 8,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Edge = e("UIStroke", { Color = C.Ink, Thickness = 3 }),
					Pulse = e("UIScale", {
						Scale = bob:map(function(w: number)
							return 1 + 0.14 * w
						end),
					}),
					Mark = e(Kit.ChunkText, { Text = "!", TextSize = 22, Stroke = 2, Drop = 1, ZIndex = 9 }),
				})
				else nil,
		}),
	})
end

---------------------------------------------------------------------
-- App
---------------------------------------------------------------------
local function App()
	local scale = useViewportScale()
	local journalOpen, setJournalOpen = React.useState(false)
	local shopOpen, setShopOpen = React.useState(false)
	local journalTool, setJournalTool = React.useState(nil)
	React.useEffect(function()
		Players.LocalPlayer:SetAttribute("UiOpen", shopOpen or journalOpen)
		return nil
	end, { shopOpen, journalOpen })
	-- Tab opens and closes the upgrade panel (the Roblox player list is hidden so Tab is free).
	React.useEffect(function()
		local uis = game:GetService("UserInputService")
		task.spawn(function()
			for _ = 1, 10 do
				local done = pcall(function()
					game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
				end)
				if done then
					return
				end
				task.wait(0.5)
			end
		end)
		local connection = uis.InputBegan:Connect(function(input)
			if input.KeyCode ~= Enum.KeyCode.Tab or uis:GetFocusedTextBox() then
				return
			end
			setJournalTool(nil)
			setJournalOpen(function(open)
				return not open
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	React.useEffect(function()
		Sounds.Init()
		return nil
	end, {})

	-- ShopPrompt toggles the shop. Walking away from the counter closes it.
	React.useEffect(function()
		local alive = true
		local connection
		task.spawn(function()
			local map = workspace:WaitForChild("Map", 10)
			local shop = map and map:WaitForChild("ToolShop", 10)
			local counter = shop and shop:WaitForChild("Counter", 10)
			local prompt = counter and counter:WaitForChild("ShopPrompt", 10)
			if not counter or not prompt or not alive then
				return
			end

			connection = prompt.Triggered:Connect(function()
				setShopOpen(function(open)
					return not open
				end)
			end)

			while alive do
				task.wait(0.5)
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - counter.Position).Magnitude > SHOP_CLOSE_DISTANCE then
					setShopOpen(false)
				end
			end
		end)
		return function()
			alive = false
			if connection then
				connection:Disconnect()
			end
		end
	end, {})

	return e("Frame", {
		Size = UDim2.fromScale(1 / scale, 1 / scale),
		BackgroundTransparency = 1,
	}, {
		Scale = e("UIScale", { Scale = scale }),

		Top = if shopOpen then nil else e(TopButtons),
		Objective = if shopOpen then nil else e(Objective),
		Hotbar = if shopOpen then nil else e(Hotbar),
		SellPopup = e(SellPopup),
		Notifications = e(Notifications),
		Results = e(Results),
		LootFeed = if shopOpen then nil else e(LootFeed),
		Announcer = e(Announcer),

		Left = if shopOpen then nil else e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -14),
			Size = UDim2.fromOffset(280, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 10),
			}),
			Timer = e(Timer, { LayoutOrder = 1 }),
			Money = e(MoneyCard, { LayoutOrder = 2 }),
			Bag = e(BagCard, { LayoutOrder = 3 }),
		}),

		UpgradeButton = if shopOpen then nil else e(UpgradeButton, {
			OnActivated = function()
				setJournalTool(nil)
				setJournalOpen(not journalOpen)
			end,
		}),

		Journal = if journalOpen
			then e(Journal, {
				OnClose = function()
					setJournalOpen(false)
				end,
				RootScale = scale,
				InitialTool = journalTool,
			})
			else nil,
		Shop = if shopOpen
			then e(ShopView, {
				OnClose = function()
					setShopOpen(false)
				end,
				RootScale = scale,
				OnUpgrade = function(toolId)
					setShopOpen(false)
					setJournalTool(toolId)
					setJournalOpen(true)
				end,
			})
			else nil,
	})
end

return App