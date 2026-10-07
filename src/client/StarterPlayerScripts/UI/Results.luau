local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.ReactLua.React)

local UI = script.Parent
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)

local e = React.createElement
local C = Theme.Colors
local player = Players.LocalPlayer

local RoundResults = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundResults")

local W = 540 -- card width (design units)
local MAX_ROWS = 6
local ROW_STEP = 50

local function formatTime(totalSeconds: number): string
	local s = math.floor(math.max(totalSeconds, 0))
	return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end

local function useViewport()
	local camera = workspace.CurrentCamera
	local size, setSize = React.useState(camera.ViewportSize)
	React.useEffect(function()
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setSize(camera.ViewportSize)
		end)
		setSize(camera.ViewportSize)
		return function()
			connection:Disconnect()
		end
	end, {})
	return size
end

---------------------------------------------------------------------
-- A small stat box ("TIME", "DELIVERED BY")
---------------------------------------------------------------------
local function Stat(props)
	return e(Kit.Plate, {
		Size = UDim2.fromOffset(230, 64),
		Position = props.Position,
		Fill = C.IronDark,
		Radius = 12,
		EdgeThickness = 3,
		Shadow = false,
	}, {
		Caption = e(Kit.Text, {
			Text = props.Caption,
			TextSize = 12,
			Color = C.PaperDark,
			Size = UDim2.new(1, -20, 0, 18),
			Position = UDim2.fromOffset(10, 6),
		}),
		Value = e(Kit.ChunkText, {
			Text = props.Value,
			TextSize = 26,
			Scaled = true,
			Color = props.Color or C.Cream,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -20, 0, 34),
			Position = UDim2.fromOffset(10, 24),
		}),
	})
end

---------------------------------------------------------------------
-- One contribution row. The bar fills in after a short stagger.
---------------------------------------------------------------------
local function Row(props)
	local row = props.Row
	local index = props.Index
	local go, setGo = React.useState(false)

	React.useEffect(function()
		local thread = task.delay(0.5 + index * 0.12, function()
			setGo(true)
		end)
		return function()
			pcall(task.cancel, thread)
		end
	end, {})

	local fill = Kit.useSpring(if go then math.clamp(row.Percent / 100, 0, 1) else 0, 140, 18, 0)
	local mine = row.Name == player.DisplayName
	local first = index == 1

	return e(Kit.Plate, {
		Size = UDim2.fromOffset(W - 56, 44),
		Position = UDim2.fromOffset(28, props.Y),
		Fill = if mine then C.AmberDark else C.Slate,
		Edge = if mine then C.Amber else C.Ink,
		EdgeThickness = if mine then 4 else 3,
		Radius = 12,
		Shadow = false,
	}, {
		Rank = e(Kit.Plate, {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(8, 7),
			Fill = if first then C.Amber else C.IronLight,
			Radius = 15,
			EdgeThickness = 2.5,
			Shadow = false,
		}, {
			Number = e(Kit.ChunkText, { Text = tostring(index), TextSize = 18, Stroke = 2, Drop = 1 }),
		}),
		Label = e(Kit.ChunkText, {
			Text = row.Name,
			Align = Enum.TextXAlignment.Left,
			Scaled = true,
			TextSize = 20,
			Stroke = 2,
			Drop = 2,
			Size = UDim2.fromOffset(190, 30),
			Position = UDim2.fromOffset(48, 7),
		}),
		Track = e("Frame", {
			Size = UDim2.fromOffset(150, 16),
			Position = UDim2.fromOffset(250, 14),
			BackgroundColor3 = C.IronDark,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Edge = e("UIStroke", { Color = C.Ink, Thickness = 2 }),
			Fill = e("Frame", {
				Size = fill:map(function(a: number)
					return UDim2.fromScale(math.max(a, 0), 1)
				end),
				BackgroundColor3 = if first then C.Amber else C.MoneyGreen,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),
		}),
		Percent = e(Kit.ChunkText, {
			Text = row.Percent .. "%",
			Align = Enum.TextXAlignment.Right,
			TextSize = 22,
			Stroke = 2,
			Drop = 2,
			Size = UDim2.fromOffset(66, 30),
			Position = UDim2.fromOffset(410, 7),
		}),
	})
end

---------------------------------------------------------------------
-- The screen itself (mounted fresh for each result, so it re-animates)
---------------------------------------------------------------------
local function Screen(props)
	local payload = props.Payload
	local viewport = useViewport()
	local pop = Kit.useEntrance()
	local fade = Kit.useAppear(0.35)
	local countdown, setCountdown = React.useBinding("")

	React.useEffect(function()
		local alive = true
		task.spawn(function()
			local restartAt = props.At + (payload.RestartIn or 15)
			while alive do
				local remaining = math.ceil(restartAt - os.clock())
				if remaining > 0 then
					setCountdown("Returning to lobby in " .. remaining .. "...")
				else
					setCountdown("Returning to lobby...")
				end
				task.wait(0.25)
			end
		end)
		return function()
			alive = false
		end
	end, {})

	local rows = payload.Rows or {}
	local shown = math.min(#rows, MAX_ROWS)
	local extra = #rows - shown

	-- Vertical layout (design units)
	local rowsY = 196
	local listH = if shown == 0 then 30 else shown * ROW_STEP + (if extra > 0 then 24 else 0)
	local footerY = rowsY + listH + 6
	local hideY = footerY + 32
	local H = hideY + 48 + 24

	-- Fit to any screen (same base scale the rest of the UI uses)
	local rootScale = math.clamp(viewport.Y / 720, 0.7, 1.5)
	local fit = math.clamp(
		math.min((viewport.Y - 40) / (H * rootScale), (viewport.X - 40) / (W * rootScale)),
		0.4,
		1
	)

	local body = {
		Title = e(Kit.ChunkText, {
			Text = "CORE DELIVERED!",
			TextSize = 46,
			Scaled = true,
			Color = C.Amber,
			Size = UDim2.fromOffset(W - 40, 60),
			Position = UDim2.fromOffset(20, 16),
		}),
		Time = e(Stat, {
			Caption = "TIME",
			Value = formatTime(payload.Seconds or 0),
			Color = C.MoneyGreen,
			Position = UDim2.fromOffset(28, 88),
		}),
		Deliverer = e(Stat, {
			Caption = "DELIVERED BY",
			Value = payload.Deliverer or "?",
			Position = UDim2.fromOffset(282, 88),
		}),
		Header = e(Kit.Text, {
			Text = "TEAM CONTRIBUTION",
			TextSize = 14,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(W - 56, 22),
			Position = UDim2.fromOffset(28, 166),
		}),
		Footer = e(Kit.ChunkText, {
			Text = countdown,
			TextSize = 20,
			Color = C.Cream,
			Size = UDim2.fromOffset(W - 40, 28),
			Position = UDim2.fromOffset(20, footerY),
		}),
		Hide = e(Kit.BigButton, {
			Text = "Hide",
			Variant = "iron",
			TextSize = 20,
			Size = UDim2.fromOffset(160, 48),
			Position = UDim2.fromOffset((W - 160) / 2, hideY),
			OnActivated = props.OnHide,
		}),
	}

	for index = 1, shown do
		body["Row" .. index] = e(Row, {
			Index = index,
			Row = rows[index],
			Y = rowsY + (index - 1) * ROW_STEP,
		})
	end
	if shown == 0 then
		body.Empty = e(Kit.Text, {
			Text = "No damage was recorded.",
			TextSize = 16,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(W - 56, 24),
			Position = UDim2.fromOffset(28, rowsY),
		})
	end
	if extra > 0 then
		body.More = e(Kit.Text, {
			Text = "+" .. extra .. " more",
			TextSize = 14,
			Color = C.PaperDark,
			Size = UDim2.fromOffset(W - 56, 20),
			Position = UDim2.fromOffset(28, rowsY + shown * ROW_STEP + 2),
		})
	end

	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = fade:map(function(a: number)
			return 1 - 0.6 * a
		end),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false, -- swallows clicks so nothing behind it is pressed
		ZIndex = 50,
	}, {
		Card = e("Frame", {
			Size = UDim2.fromOffset(W, H),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 51,
		}, {
			Scale = e("UIScale", {
				Scale = pop:map(function(a: number)
					return fit * (0.85 + 0.15 * a)
				end),
			}),
			Body = e(Kit.Plate, {
				Size = UDim2.fromScale(1, 1),
				Fill = C.Iron,
				Edge = C.Amber,
				EdgeThickness = 5,
				Radius = 22,
			}, body),
		}),
	})
end

---------------------------------------------------------------------
-- Wrapper: waits for the RoundResults event, then shows the screen
---------------------------------------------------------------------
local function Results()
	local data, setData = React.useState(nil)
	local hidden, setHidden = React.useState(false)

	React.useEffect(function()
		local connection = RoundResults.OnClientEvent:Connect(function(payload)
			setHidden(false)
			setData({ Payload = payload, At = os.clock() })
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	if not data or hidden then
		return e("Folder")
	end

	return e(Screen, {
		Payload = data.Payload,
		At = data.At,
		OnHide = function()
			setHidden(true)
		end,
	})
end

return Results