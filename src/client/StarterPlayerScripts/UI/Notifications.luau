local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)

local UI = script.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local e = React.createElement
local C = Theme.Colors

local Notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify", 5)

local SHOW_SECONDS = 2.6
local MAX_TOASTS = 4
local WIDTH = 340

local function colorFor(kind: any): Color3
	local k = string.lower(tostring(kind or ""))
	if k == "success" then
		return C.Green
	elseif k == "warning" then
		return C.Amber -- "Bag full", "Not enough money"
	elseif k == "info" then
		return C.Slate
	end
	return C.Red -- "error" and anything unknown
end

local function Toast(props)
	local appear = Kit.useEntrance()
	return e("Frame", {
		LayoutOrder = props.Id,
		Size = UDim2.fromOffset(WIDTH, 48),
		BackgroundTransparency = 1,
	}, {
		Pop = e("UIScale", {
			Scale = appear:map(function(a: number)
				return 0.8 + 0.2 * a
			end),
		}),
		Plate = e(Kit.Plate, {
			Size = UDim2.fromOffset(WIDTH, 42),
			Fill = colorFor(props.Kind),
			Radius = 12,
			EdgeThickness = 3,
		}, {
			Text = e(Kit.ChunkText, {
				Text = props.Text,
				Scaled = true,
				TextSize = 18,
				Stroke = 2,
				Drop = 2,
				Size = UDim2.new(1, -24, 1, 0),
				Position = UDim2.fromOffset(12, 0),
			}),
		}),
	})
end

local function Notifications()
	local toasts, setToasts = React.useState({})

	React.useEffect(function()
		if not Notify then
			return nil
		end
		local counter = 0
		local connection = Notify.OnClientEvent:Connect(function(message: any, kind: any)
			if typeof(message) ~= "string" then
				return
			end
			counter += 1
			local id = counter
			setToasts(function(old)
				local new = table.clone(old)
				table.insert(new, { Id = id, Text = message, Kind = kind })
				while #new > MAX_TOASTS do
					table.remove(new, 1)
				end
				return new
			end)
			task.delay(SHOW_SECONDS, function()
				setToasts(function(old)
					local new = {}
					for _, toast in old do
						if toast.Id ~= id then
							table.insert(new, toast)
						end
					end
					return new
				end)
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local kids = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	}
	for _, toast in toasts do
		kids["Toast" .. toast.Id] = e(Toast, { Id = toast.Id, Text = toast.Text, Kind = toast.Kind })
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -136),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, kids)
end

return Notifications