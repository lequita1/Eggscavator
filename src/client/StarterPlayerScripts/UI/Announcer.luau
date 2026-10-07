local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local ItemDefinitions = require(Shared.ItemDefinitions)

local UI = script.Parent
local Theme = require(UI.Theme)
local Store = require(UI.Store)
local Kit = require(UI.Kit)
local Sounds = require(UI.Sounds)

local e = React.createElement
local C = Theme.Colors

local LootDropped = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LootDropped", 5)

local TOP = 14
local BANNER_SECONDS = 2.4
local RARE_ORDER = 4 -- Epic and above

local MILESTONES = {
	{ At = 0.75, Text = "CRACKS ARE SPREADING!", Color = C.Cream },
	{ At = 0.5, Text = "HALFWAY THERE!", Color = C.Amber },
	{ At = 0.25, Text = "ALMOST THROUGH!", Color = C.Clay },
	{ At = 0.1, Text = "THE CORE IS CLOSE!", Color = C.Red },
}

---------------------------------------------------------------------
-- Screen-edge glow (rare drops). Fades in and out over one second.
---------------------------------------------------------------------
local function Glow(props)
	local p = Kit.useAppear(1.0)
	local transparency = p:map(function(a: number)
		return 1 - 0.75 * math.sin(a * math.pi)
	end)

	local function edge(rotation: number, anchorX: number)
		return e("Frame", {
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.fromScale(anchorX, 0),
			Size = UDim2.fromScale(0.16, 1),
			BackgroundColor3 = props.Color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
		}, {
			Fade = e("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = rotation,
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Left = edge(0, 0),
		Right = edge(180, 1),
	})
end

---------------------------------------------------------------------
-- Banner: springs in, shrinks away just before it is removed
---------------------------------------------------------------------
local function Banner(props)
	local enter = Kit.useEntrance()
	local gone, setGone = React.useState(false)
	local exit = Kit.useSpring(if gone then 0 else 1, 300, 28, 1)

	React.useEffect(function()
		local thread = task.delay(BANNER_SECONDS - 0.4, function()
			setGone(true)
		end)
		return function()
			pcall(task.cancel, thread)
		end
	end, {})

	local hasSub = props.Sub ~= nil

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP + 104),
		Size = UDim2.fromOffset(440, if hasSub then 70 else 56),
		BackgroundTransparency = 1,
	}, {
		EnterScale = e("UIScale", {
			Scale = enter:map(function(a: number)
				return 0.6 + 0.4 * a
			end),
		}),
		Inner = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			ExitScale = e("UIScale", {
				Scale = exit:map(function(a: number)
					return math.clamp(a, 0, 1)
				end),
			}),
			Plate = e(Kit.Plate, {
				Size = UDim2.fromScale(1, 1),
				Fill = C.Iron,
				Edge = props.Color,
				EdgeThickness = 4,
				Radius = 14,
			}, {
				Title = e(Kit.ChunkText, {
					Text = props.Text,
					Scaled = true,
					TextSize = if hasSub then 28 else 30,
					Color = props.Color,
					Size = if hasSub then UDim2.new(1, -20, 0, 34) else UDim2.new(1, -20, 1, 0),
					Position = UDim2.fromOffset(10, if hasSub then 4 else 0),
				}),
				Sub = if hasSub
					then e(Kit.ChunkText, {
						Text = props.Sub,
						TextSize = 18,
						Stroke = 2,
						Drop = 2,
						Size = UDim2.new(1, -20, 0, 24),
						Position = UDim2.fromOffset(10, 38),
					})
					else nil,
			}),
		}),
	})
end

---------------------------------------------------------------------
-- Announcer: one banner at a time; a new one replaces the old
---------------------------------------------------------------------
local function Announcer()
	-- Egg health (Store.useEgg gives Present and Fraction)
	local egg = if Store.useEgg then Store.useEgg() else { Present = false, Fraction = 1 }

	local banner, setBanner = React.useState(false)
	local glow, setGlow = React.useState(false)
	local seq = React.useRef(0)
	local lastFraction = React.useRef(nil)

	local function show(text: string, sub: string?, color: Color3, withGlow: boolean)
		Sounds.Play(if withGlow then "Rare" else "Milestone")
		seq.current += 1
		local id = seq.current
		setBanner({ Id = id, Text = text, Sub = sub, Color = color })
		if withGlow then
			setGlow({ Id = id, Color = color })
		end
		task.delay(BANNER_SECONDS, function()
			setBanner(function(old)
				if old and old.Id == id then
					return false
				end
				return old
			end)
			setGlow(function(old)
				if old and old.Id == id then
					return false
				end
				return old
			end)
		end)
	end

	-- Milestones: fire when the egg's health crosses a threshold going down
	React.useEffect(function()
		local fraction = egg.Fraction
		local last = lastFraction.current
		lastFraction.current = fraction
		if not egg.Present or last == nil then
			return nil
		end
		for _, milestone in MILESTONES do
			if last > milestone.At and fraction <= milestone.At then
				show(milestone.Text, nil, milestone.Color, false)
			end
		end
		return nil
	end, { egg.Fraction, egg.Present })

	-- Rare drops: Epic and above
	React.useEffect(function()
		if not LootDropped then
			return nil
		end
		local connection = LootDropped.OnClientEvent:Connect(function(gained)
			local bestOrder, bestItem = 0, nil
			for _, gain in gained do
				local item = ItemDefinitions[gain.ItemId]
				local rarity = item and GameConfig.Rarities[item.Rarity]
				local order = rarity and (rarity.Order or 0) or 0
				if order >= RARE_ORDER and order > bestOrder then
					bestOrder, bestItem = order, item
				end
			end
			if bestItem then
				local rarity = GameConfig.Rarities[bestItem.Rarity]
				show(string.upper(bestItem.Rarity) .. " DROP!", bestItem.DisplayName, rarity.Color, true)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local kids = {}
	if glow then
		kids["Glow" .. glow.Id] = e(Glow, { Color = glow.Color })
	end
	if banner then
		kids["Banner" .. banner.Id] = e(Banner, { Text = banner.Text, Sub = banner.Sub, Color = banner.Color })
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, kids)
end

return Announcer