local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local ItemDefinitions = require(Shared.ItemDefinitions)

local UI = script.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local e = React.createElement
local C = Theme.Colors

local LootDropped = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LootDropped")

local WIDTH = 250
local MAX_ENTRIES = 5
local LIFE = 2.4 -- seconds a row stays after its last gain
local FADE = 0.35 -- seconds it takes to fade out
local RARE_ORDER = 3 -- Rare and above get the light sweep

---------------------------------------------------------------------
-- One row: a gem, "+N", and the item name
---------------------------------------------------------------------
local function Entry(props)
	local entry = props.Entry
	local item = ItemDefinitions[entry.Id]
	local rarity = item and GameConfig.Rarities[item.Rarity]
	local color = if rarity then rarity.Color else C.Cream
	local rank = if rarity then rarity.Order else 1
	local special = rank >= RARE_ORDER

	local enter = Kit.useEntrance() -- springs 0 -> ~1.2 -> 1
	local sweep = Kit.useAppear(0.7) -- one-shot 0 -> 1
	local pulse, setPulse = React.useState(false)
	local pulseScale = Kit.useSpring(if pulse then 1.12 else 1, 420, 14)
	local fade = Kit.useSpring(if entry.Leaving then 1 else 0, 260, 26, 0)

	-- A small pop every time more of this item arrives
	React.useEffect(function()
		if entry.Bump == 0 then
			return nil
		end
		setPulse(true)
		local thread = task.delay(0.09, function()
			setPulse(false)
		end)
		return function()
			pcall(task.cancel, thread)
		end
	end, { entry.Bump })

	local plateKids = {
		Gem = e("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(0, 22, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 2 }),
			Shine = e("Frame", {
				Size = UDim2.fromOffset(6, 6),
				Position = UDim2.fromOffset(3, 3),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
			}, { Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
		}),
		Count = e(Kit.ChunkText, {
			Text = "+" .. entry.Count,
			Align = Enum.TextXAlignment.Left,
			TextSize = 24,
			Stroke = 2.5,
			Drop = 2,
			Color = color,
			Size = UDim2.new(0, 56, 1, 0),
			Position = UDim2.fromOffset(40, 0),
			ZIndex = 3,
		}),
		Name = e(Kit.ChunkText, {
			Text = if item then item.DisplayName else entry.Id,
			Align = Enum.TextXAlignment.Left,
			Scaled = true,
			TextSize = 20,
			Stroke = 2,
			Drop = 2,
			Color = if special then color else C.Cream,
			Size = UDim2.new(1, -104, 1, 0),
			Position = UDim2.fromOffset(96, 0),
			ZIndex = 3,
		}),
	}

	-- Rare and better: a light sweeps across once when the row appears
	if special then
		plateKids.SweepHolder = e("Frame", {
			Size = UDim2.new(1, -6, 1, -6),
			Position = UDim2.fromOffset(3, 3),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
		}, {
			Bar = e("Frame", {
				Size = UDim2.new(0, 26, 1.8, 0),
				Position = sweep:map(function(a: number)
					return UDim2.fromScale(-0.2 + 1.4 * a, 0.5)
				end),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = 20,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.75,
				BorderSizePixel = 0,
			}),
		})
	end

	return e("CanvasGroup", {
		LayoutOrder = -entry.Order, -- newest first
		Size = UDim2.fromOffset(WIDTH, 52),
		BackgroundTransparency = 1,
		GroupTransparency = fade:map(function(a: number)
			return math.clamp(a, 0, 1)
		end),
	}, {
		Wrap = e("Frame", {
			Size = UDim2.new(1, -16, 0, 44), -- 16px spare so the pop isn't clipped
			Position = enter:map(function(a: number)
				return UDim2.new(0.5, (1 - a) * 70, 0, 22) -- slides in from the right
			end),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			EnterScale = e("UIScale", {
				Scale = enter:map(function(a: number)
					return 0.7 + 0.3 * a
				end),
			}),
			Pulse = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				PulseScale = e("UIScale", { Scale = pulseScale }),
				Plate = e(Kit.Plate, {
					Size = UDim2.fromScale(1, 1),
					Fill = if rank >= 2 then C.IronDark:Lerp(color, 0.22) else C.Iron,
					Edge = if rank >= 2 then color else C.Ink,
					EdgeThickness = if rank >= 4 then 5 elseif rank >= 3 then 4 else 3,
					Radius = 12,
				}, plateKids),
			}),
		}),
	})
end

---------------------------------------------------------------------
-- The feed: listens to LootDropped, merges gains, expires old rows
---------------------------------------------------------------------
local function LootFeed()
	local entries, setEntries = React.useState({})
	local seqRef = React.useRef(0)

	React.useEffect(function()
		local connection = LootDropped.OnClientEvent:Connect(function(gained)
			local base = seqRef.current
			seqRef.current += #gained + 1

			setEntries(function(old)
				local now = os.clock()
				local list = table.clone(old)

				for index, gain in gained do
					if ItemDefinitions[gain.ItemId] then
						local found
						for i, en in list do
							if en.Id == gain.ItemId and not en.Leaving then
								found = i
								break
							end
						end

						if found then
							local en = list[found]
							list[found] = {
								Id = en.Id,
								Count = en.Count + gain.Count,
								Stamp = now,
								Order = base + index,
								Bump = en.Bump + 1,
								Leaving = false,
							}
						else
							if #list >= MAX_ENTRIES then
								local oldestIndex, oldestOrder = 1, math.huge
								for i, en in list do
									if en.Order < oldestOrder then
										oldestIndex, oldestOrder = i, en.Order
									end
								end
								table.remove(list, oldestIndex)
							end
							table.insert(list, {
								Id = gain.ItemId,
								Count = gain.Count,
								Stamp = now,
								Order = base + index,
								Bump = 0,
								Leaving = false,
							})
						end
					end
				end
				return list
			end)
		end)

		-- Start fading old rows, then remove them
		local alive = true
		task.spawn(function()
			while alive do
				task.wait(0.2)
				setEntries(function(old)
					local now = os.clock()
					local changed = false
					local list = {}
					for _, en in old do
						local age = now - en.Stamp
						if age > LIFE + FADE then
							changed = true
						elseif age > LIFE and not en.Leaving then
							changed = true
							table.insert(list, {
								Id = en.Id,
								Count = en.Count,
								Stamp = en.Stamp,
								Order = en.Order,
								Bump = en.Bump,
								Leaving = true,
							})
						else
							table.insert(list, en)
						end
					end
					if changed then
						return list
					end
					return old -- nothing changed, so React skips the re-render
				end)
			end
		end)

		return function()
			alive = false
			connection:Disconnect()
		end
	end, {})

	local kids = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for _, en in entries do
		kids["Loot" .. en.Id] = e(Entry, { Entry = en })
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0.5, 66), -- right side, just under the UPGRADES button
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, kids)
end

return LootFeed