local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

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

-- tune after a screenshot ------------------------------------------
local BAR_H = 84 -- black bar height
local PW, PH = 360, 484 -- side card size
local TOOL_DIST = 10 -- studs from the camera to a tool or gear
local BAG_DIST = 13 -- studs from the camera to a bag (must stay clear of the counter)
local FRAME = 0.72 -- how much room around the item (smaller = item fills more of the screen)
local GENERIC_FOV = 40 -- lens for stops without a 3D item (the Ladder)
local LIFT = 0.7 -- how far the selected item rises
local SPIN = 0.8 -- turn speed (radians per second)
local DIM_OTHERS = 1 -- 1 = other items vanish while you look at one, 0 = they stay visible
local BLUR = 0.8 -- background blur (0 = none)
----------------------------------------------------------------------

local function icon(id)
	local v = Theme.Icons and Theme.Icons[id]
	if v and v ~= "" then
		return v
	end
	return nil
end

local function rawToolStats(toolId)
	local d = ToolDefinitions[toolId]
	return { Power = d.Damage / d.AttackInterval, Tier = d.Power, Reach = d.Range }
end
local MAXT = { Power = 1, Tier = 1, Reach = 1 }
for toolId in ToolDefinitions do
	for key, value in rawToolStats(toolId) do
		MAXT[key] = math.max(MAXT[key], value)
	end
end

local function pickupInfo(up)
	local src = GameConfig.Pickup[up.Id]
	if type(src) == "table" then
		return src
	end
	return up
end
local MAXP = { Reach = 1, Sweep = 1 }
for _, up in GameConfig.Pickup.Upgrades do
	local info = pickupInfo(up)
	MAXP.Reach = math.max(MAXP.Reach, info.Reach or 0)
	MAXP.Sweep = math.max(MAXP.Sweep, info.Sweep or 0)
end
local MAXCAP = 1
for _, up in GameConfig.Inventory.CapacityUpgrades do
	MAXCAP = math.max(MAXCAP, up.Capacity)
end

---------------------------------------------------------------------
-- The list of stops (display only; the server checks every purchase)
---------------------------------------------------------------------
local function buildStops(state, onUpgrade)
	local stops = {}

	for _, tool in state.Tools do
		if (tool.Price or 0) > 0 then
			local s = rawToolStats(tool.Id)
			table.insert(stops, {
				Key = "tool_" .. tool.Id,
				Kind = "tool",
				Display = tool.Id,
				Category = "TOOL",
				Name = tool.Name,
				Desc = tool.Description or "",
				Icon = icon(tool.Id),
				Rows = {
					{ "POWER", s.Power, MAXT.Power, C.Amber, string.format("%d/s", math.floor(s.Power + 0.5)) },
					{ "TIER", s.Tier, MAXT.Tier, C.Clay, tostring(math.floor(s.Tier + 0.5)) },
					{ "REACH", s.Reach, MAXT.Reach, C.Slate, tostring(math.floor(s.Reach + 0.5)) },
				},
				Tracks = tool.Tracks,
				State = if tool.Owned then "owned" else "buy",
				Price = tool.Price,
				OwnedText = "In your hotbar",
				OnBuy = function()
					Store.buyTool(tool.Id)
				end,
				OnOwned = function()
					if onUpgrade then
						onUpgrade(tool.Id)
					end
				end,
			})
		end
	end

	local pickups = GameConfig.Pickup.Upgrades
	for index, up in pickups do
		local info = pickupInfo(up)
		local rows = {}
		if type(info.Reach) == "number" then
			table.insert(rows, { "REACH", info.Reach, MAXP.Reach, C.Slate, tostring(math.floor(info.Reach + 0.5)) })
		end
		if type(info.Sweep) == "number" then
			table.insert(rows, { "SWEEP", info.Sweep, MAXP.Sweep, C.Amber, tostring(math.floor(info.Sweep + 0.5)) })
		end
		local previous = pickups[index - 1]
		table.insert(stops, {
			Key = "gear_" .. tostring(up.Id or up.Name),
			Kind = "gear",
			Display = up.Id or up.Name,
			Category = "PICKUP GEAR",
			Name = up.Name,
			Desc = up.Description or "",
			Icon = icon(up.Id),
			Rows = rows,
			Facts = { if info.Hold then "Hold the button to vacuum." else "Click to sweep pieces in." },
			State = if state.PickupTier >= index then "owned" elseif index == state.PickupTier + 1 then "buy" else "locked",
			Price = up.Price,
			OwnedText = "In your hotbar",
			LockText = "Buy the " .. (previous and previous.Name or "earlier gear") .. " first",
			OnBuy = Store.buyPickupUpgrade,
		})
	end

	for index, up in GameConfig.Inventory.CapacityUpgrades do
		table.insert(stops, {
			Key = "bag_" .. index,
			Kind = "bag",
			Display = up.Name,
			Category = "BAG",
			Name = up.Name,
			Desc = up.Description or string.format("Carry %d pieces at once.", up.Capacity),
			Rows = { { "CARRIES", up.Capacity, MAXCAP, C.Green, tostring(up.Capacity) } },
			Facts = { "Full price. Old bags are not traded in." },
			State = if index == state.BagTier then "yours" elseif index < state.BagTier then "smaller" else "buy",
			Price = up.Price,
			OwnedText = "Your current bag",
			OnBuy = function()
				Store.buyBagTier(index)
			end,
		})
	end

	local tiers = GameConfig.Climb.Tiers
	local climbTier = state.ClimbTier or 0
	local nextTier = tiers[climbTier + 1]
	table.insert(stops, {
		Key = "ladder",
		Kind = "ladder",
		Display = "Ladder",
		Category = "LADDER",
		Name = "Ladder",
		Desc = if nextTier then string.format("%s: %s", nextTier.Name, nextTier.Description) else "Your ladder is built as high as it goes.",
		Icon = icon("ClimbRig"),
		Facts = { "Carried and shared by your team." },
		Tiers = { Level = climbTier, Max = #tiers },
		State = if nextTier then "buy" else "maxed",
		Price = if nextTier then nextTier.Price else 0,
		OnBuy = Store.buyClimbUpgrade,
	})

	return stops
end

---------------------------------------------------------------------
-- Pieces of the side card
---------------------------------------------------------------------
local function StatRow(props)
	return e("Frame", {
		Size = UDim2.fromOffset(304, 20),
		Position = UDim2.fromOffset(0, props.Y),
		BackgroundTransparency = 1,
	}, {
		Label = e(Kit.Text, {
			Text = props.Label,
			TextSize = 13,
			Color = C.PaperDark,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(64, 20),
		}),
		Bar = e(Effects.ProgressBar, {
			Fraction = math.clamp(props.Value / math.max(props.Max, 1), 0, 1),
			Color = props.Color,
			Size = UDim2.fromOffset(176, 12),
			Position = UDim2.fromOffset(68, 4),
			Radius = 6,
			Stroke = 2,
		}),
		Value = e(Kit.Text, {
			Text = props.Text,
			TextSize = 14,
			Color = C.Cream,
			Align = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(52, 20),
			Position = UDim2.fromOffset(252, 0),
		}),
	})
end

local function StopCard(props)
	local stop = props.Stop
	local money = props.Money
	local p = Kit.useAppear(0.3)
	local celebrate, setCelebrate = React.useState(0)

	local isMine = stop.State == "owned" or stop.State == "yours"
	local was = React.useRef(isMine)
	React.useEffect(function()
		if isMine and not was.current then
			setCelebrate(function(n)
				return n + 1
			end)
		end
		was.current = isMine
		return nil
	end, { isMine })

	local price = stop.Price or 0
	local affordable = stop.State == "buy" and money >= price

	local actionKids
	if stop.State == "maxed" then
		actionKids = { Done = e(Kit.ChunkText, { Text = "MAXED!", TextSize = 32, Color = C.Amber }) }
	else
		local text, variant, disabled, onClick = "OWNED", "iron", true, nil
		if stop.State == "buy" then
			text, variant, disabled = "BUY  " .. Util.FormatCents(price), "gold", not affordable
			onClick = stop.OnBuy
		elseif stop.State == "owned" and stop.OnOwned then
			text, variant, disabled, onClick = "UPGRADE", "iron", false, stop.OnOwned
		elseif stop.State == "yours" then
			text = "YOURS"
		elseif stop.State == "smaller" then
			text = "SMALLER"
		elseif stop.State == "locked" then
			text = "LOCKED"
		end
		actionKids = {
			Button = e(Kit.BigButton, {
				Text = text,
				Variant = variant,
				Disabled = disabled,
				TextSize = 24,
				Size = UDim2.fromScale(1, 1),
				OnActivated = function()
					if onClick then
						onClick() -- intent only. The server checks everything.
					end
				end,
			}),
		}
		if affordable then
			actionKids.Pulse = e("UIScale", {
				Scale = props.Wave:map(function(w: number)
					return 1 + 0.03 * w
				end),
			})
		end
	end

	local status
	if stop.State == "buy" and not affordable then
		status = e(Effects.ProgressBar, {
			Fraction = math.clamp(money / math.max(price, 1), 0, 1),
			Color = C.Amber,
			Text = Util.FormatCents(money) .. " / " .. Util.FormatCents(price),
			TextSize = 13,
			Size = UDim2.fromOffset(304, 22),
			Position = UDim2.fromOffset(0, 342),
			Radius = 11,
		})
	elseif stop.State == "locked" then
		status = e(Kit.Text, {
			Text = stop.LockText or "Locked",
			TextSize = 14,
			Color = C.Amber,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(304, 22),
			Position = UDim2.fromOffset(0, 342),
		})
	elseif isMine then
		status = e(Kit.Text, {
			Text = stop.OwnedText or "Owned",
			TextSize = 14,
			Color = C.MoneyGreen,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(304, 22),
			Position = UDim2.fromOffset(0, 342),
		})
	end

	local kids = {
		Chip = e(Kit.Text, {
			Text = stop.Category,
			TextSize = 13,
			Color = C.PaperDark,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(200, 18),
			Position = UDim2.fromOffset(0, 18),
		}),
		Name = e(Kit.ChunkText, {
			Text = stop.Name,
			Scaled = true,
			TextSize = 34,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(238, 40),
			Position = UDim2.fromOffset(0, 38),
		}),
		Desc = e(Kit.Text, {
			Text = stop.Desc,
			TextSize = 14,
			Color = C.PaperDark,
			Wrapped = true,
			Align = Enum.TextXAlignment.Left,
			VAlign = Enum.TextYAlignment.Top,
			Size = UDim2.fromOffset(304, 54),
			Position = UDim2.fromOffset(0, 84),
		}),
		Divider = e("Frame", {
			Size = UDim2.fromOffset(304, 2),
			Position = UDim2.fromOffset(0, 144),
			BackgroundColor3 = C.IronLight,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		}),
		Status = status,
		Action = e("Frame", {
			Size = UDim2.fromOffset(304, 56),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(152, 400),
			BackgroundTransparency = 1,
		}, actionKids),
		Hint = e(Kit.Text, {
			Text = "< >  or  A / D  to browse",
			TextSize = 12,
			Color = C.PaperDark,
			Align = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(304, 18),
			Position = UDim2.fromOffset(0, 442),
		}),
	}

	if stop.Icon then
		kids.Icon = e("ImageLabel", {
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(244, 8),
			BackgroundTransparency = 1,
			Image = stop.Icon,
			ScaleType = Enum.ScaleType.Fit,
		})
	end

	local rows = stop.Rows or {}
	for i, row in rows do
		kids["Stat" .. i] = e(StatRow, {
			Y = 154 + (i - 1) * 22,
			Label = row[1],
			Value = row[2],
			Max = row[3],
			Color = row[4],
			Text = row[5],
		})
	end

	if stop.Tracks then
		kids.UpHead = e(Kit.Text, {
			Text = "UPGRADES",
			TextSize = 12,
			Color = C.PaperDark,
			Align = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(200, 16),
			Position = UDim2.fromOffset(0, 230),
		})
		for i, track in stop.Tracks do
			local x = ((i - 1) % 2) * 156
			local y = 248 + math.floor((i - 1) / 2) * 40
			kids["TrackName" .. i] = e(Kit.Text, {
				Text = track.Name,
				TextSize = 13,
				Color = C.Cream,
				Align = Enum.TextXAlignment.Left,
				Size = UDim2.fromOffset(148, 16),
				Position = UDim2.fromOffset(x, y),
			})
			kids["TrackPips" .. i] = e(Kit.Pips, {
				Level = track.Level,
				Max = track.MaxLevel,
				Align = Enum.HorizontalAlignment.Left,
				PipWidth = 24,
				PipHeight = 8,
				Size = UDim2.fromOffset(148, 10),
				Position = UDim2.fromOffset(x, y + 20),
			})
		end
	else
		for i, text in stop.Facts or {} do
			kids["Fact" .. i] = e(Kit.Text, {
				Text = text,
				TextSize = 14,
				Color = C.Cream,
				Align = Enum.TextXAlignment.Left,
				Size = UDim2.fromOffset(304, 20),
				Position = UDim2.fromOffset(0, 236 + (i - 1) * 22),
			})
		end
		if stop.Tiers then
			kids.Tiers = e(Kit.Pips, {
				Level = stop.Tiers.Level,
				Max = stop.Tiers.Max,
				Align = Enum.HorizontalAlignment.Left,
				PipWidth = 40,
				PipHeight = 10,
				Size = UDim2.fromOffset(304, 12),
				Position = UDim2.fromOffset(0, 290),
			})
		end
	end

	if celebrate > 0 then
		kids["Burst" .. celebrate] = e(Effects.Burst, {
			OriginX = 152,
			OriginY = 60,
			Count = 24,
			Colors = { C.Amber, C.Cream, C.MoneyGreen, C.Clay },
			ZIndex = 12,
		})
	end

	return e("Frame", {
		Size = UDim2.fromOffset(304, PH),
		Position = p:map(function(a: number)
			return UDim2.fromOffset(28 + 24 * (1 - math.min(a, 1)), 0)
		end),
		BackgroundTransparency = 1,
	}, kids)
end

---------------------------------------------------------------------
-- The stage: camera, spinning item, light, blur, hidden character
---------------------------------------------------------------------
local function findDisplays()
	local map = Workspace:FindFirstChild("Map")
	local shop = map and map:FindFirstChild("ToolShop")
	local tent = shop and shop:FindFirstChild("Tent")
	local displays, labels, extras, pieces = {}, {}, {}, {}
	if tent then
		for _, d in tent:GetDescendants() do
			if d:IsA("BasePart") and d.Name:sub(1, 8) == "Display_" then
				displays[d.Name:sub(9)] = d
			elseif d:IsA("BasePart") and (d.Name:sub(1, 9) == "Pedestal_" or d.Name:sub(1, 5) == "Glow_") then
				local key = if d.Name:sub(1, 9) == "Pedestal_" then d.Name:sub(10) else d.Name:sub(6)
				extras[key] = extras[key] or {}
				table.insert(extras[key], d)
			elseif d:IsA("BasePart") and d.Name:sub(1, 6) == "Piece_" then
				local pkey = d.Name:sub(7)
				pieces[pkey] = pieces[pkey] or {}
				table.insert(pieces[pkey], d)
			elseif d:IsA("BillboardGui") and d.Name == "Label" then
				table.insert(labels, d)
			end
		end
	end
	local counter = shop and shop:FindFirstChild("Counter")
	return displays, labels, if counter then counter.Position else Vector3.new(85, 2.5, -30), extras, pieces
end

local function ShopStage(props)
	local state = Store.useStore()
	local appear = Kit.useEntrance()
	local wave = Kit.useWave(3)
	local rootScale = props.RootScale or 1
	local avail, setAvail = React.useState(Workspace.CurrentCamera.ViewportSize)
	local index, setIndex = React.useState(1)

	React.useEffect(function()
		local camera = Workspace.CurrentCamera
		setAvail(camera.ViewportSize)
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setAvail(camera.ViewportSize)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local stops = buildStops(state, props.OnUpgrade)
	local count = #stops
	local safeIndex = math.clamp(index, 1, math.max(count, 1))
	local stop = stops[safeIndex]

	local fit = math.clamp((avail.Y / rootScale - BAR_H * 2 - 36) / PH, 0.5, 1.15)
	local panelPx = (PW * fit + 36) * rootScale
	local cx = math.clamp((avail.X - panelPx) / 2 / math.max(avail.X, 1), 0.2, 0.5) -- centre of the free space, as a fraction of the screen width

	local stopsRef = React.useRef(stops)
	local indexRef = React.useRef(safeIndex)
	local closeRef = React.useRef(props.OnClose)
	local cxRef = React.useRef(cx)
	stopsRef.current = stops
	indexRef.current = safeIndex
	closeRef.current = props.OnClose
	cxRef.current = cx

	local function go(delta)
		local n = #stopsRef.current
		if n == 0 then
			return
		end
		setIndex(function(i)
			return (i - 1 + delta) % n + 1
		end)
	end

	React.useEffect(function()
		local cam = Workspace.CurrentCamera
		local displays, labels, counterPos, extras, pieces = findDisplays()

		local states = {}
		for key, part in displays do
			local list = { part }
			for _, x in extras[key] or {} do
				table.insert(list, x)
			end
			local mine = {}
			for _, x in pieces[key] or {} do
				table.insert(list, x)
				table.insert(mine, { part = x, orig = x.CFrame, rel = part.CFrame:ToObjectSpace(x.CFrame) })
			end
			states[part] = { base = part.CFrame, lift = 0, angle = 0, hide = 0, list = list, pieces = mine }
		end
		local labelWas = {}
		for _, gui in labels do
			labelWas[gui] = gui.Enabled
			gui.Enabled = false
		end

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 120)
		light.Brightness = 2
		light.Range = 18
		light.Shadows = false

		local dof = Instance.new("DepthOfFieldEffect")
		dof.FarIntensity = BLUR
		dof.NearIntensity = 0.2
		dof.InFocusRadius = 6
		dof.FocusDistance = TOOL_DIST
		dof.Parent = cam

		local prevFov = cam.FieldOfView
		cam.CameraType = Enum.CameraType.Scriptable

		local selected = nil
		local failed = false

		local function frame(dt)
			local current = stopsRef.current[indexRef.current]
			local part = if current and current.Display then displays[current.Display] else nil

			local focus, camDist, fov, maxDim
			if part then
				maxDim = math.max(part.Size.X, part.Size.Y, part.Size.Z)
				focus = states[part].base.Position + Vector3.new(0, LIFT * 0.5, 0)
				camDist = if current.Kind == "bag" or current.Kind == "ladder" then BAG_DIST else TOOL_DIST
				fov = math.clamp(math.deg(2 * math.atan(maxDim * FRAME / camDist)), 12, 50)
			else
				maxDim = 8
				focus = counterPos + Vector3.new(0, 3.5, 0)
				camDist = 14
				fov = GENERIC_FOV
			end

			if part ~= selected then
				selected = part
				light.Parent = part
			end

			-- flat, straight-on shot looking along +X; the camera slides sideways so the item sits in the middle of the free space
			local vp = cam.ViewportSize
			local aspect = vp.X / math.max(vp.Y, 1)
			local halfWidth = camDist * math.tan(math.rad(fov / 2)) * aspect
			local shift = (1 - 2 * cxRef.current) * halfWidth
			local eye = Vector3.new(focus.X - camDist, focus.Y + 0.3, focus.Z + shift)
			local target = CFrame.lookAt(eye, eye + Vector3.xAxis)
			local a = 1 - math.exp(-dt * 5)
			cam.CFrame = cam.CFrame:Lerp(target, a)
			cam.FieldOfView += (fov - cam.FieldOfView) * a
			dof.FocusDistance = camDist
			dof.InFocusRadius = math.max(maxDim * 0.6, 3)

			-- rise and turn the selected item, fade and settle the others
			local ease = math.min(1, dt * 6)
			for part2, st in states do
				if part2 == selected then
					st.lift += (LIFT - st.lift) * ease
					st.angle += dt * SPIN
				else
					st.lift += (0 - st.lift) * ease
					local wrapped = st.angle % (2 * math.pi)
					if wrapped > math.pi then
						wrapped -= 2 * math.pi
					end
					st.angle = wrapped * (1 - ease)
				end
				local hideTarget = if selected and part2 ~= selected then DIM_OTHERS else 0
				st.hide += (hideTarget - st.hide) * ease
				for _, x in st.list do
					x.LocalTransparencyModifier = st.hide
				end
				local base = st.base
				part2.CFrame = CFrame.new(base.Position + Vector3.new(0, st.lift, 0))
					* CFrame.Angles(0, st.angle, 0)
					* (base - base.Position)
				for _, pc in st.pieces do
					pc.part.CFrame = part2.CFrame * pc.rel
				end
			end

			-- hide our own character while the camera is on the stall
			local character = player.Character
			if character then
				for _, d in character:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 1
					end
				end
			end
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				closeRef.current()
			end
		end

		RunService:BindToRenderStep("ShopStageCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
			if failed then
				return
			end
			local ok, err = pcall(frame, dt)
			if not ok then
				failed = true
				warn("[ShopStage] camera step failed, closing: " .. tostring(err))
				closeRef.current()
			end
		end)

		ContextActionService:BindActionAtPriority("ShopStageKeys", function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local key = input.KeyCode
				if key == Enum.KeyCode.Left or key == Enum.KeyCode.A then
					go(-1)
				elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D then
					go(1)
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.A, Enum.KeyCode.D,
			Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.Up, Enum.KeyCode.Down)

		return function()
			RunService:UnbindFromRenderStep("ShopStageCamera")
			ContextActionService:UnbindAction("ShopStageKeys")
			for part, st in states do
				part.CFrame = st.base
				for _, pc in st.pieces do
					pc.part.CFrame = pc.orig
				end
				for _, x in st.list do
					x.LocalTransparencyModifier = 0
				end
			end
			for gui, was in labelWas do
				gui.Enabled = was
			end
			light:Destroy()
			dof:Destroy()
			local character = player.Character
			if character then
				for _, d in character:GetDescendants() do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 0
					end
				end
			end
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = prevFov
		end
	end, {})

	local coinImage = icon("Coin")

	local dots = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i = 1, count do
		local on = i == safeIndex
		dots["Dot" .. i] = e("Frame", {
			LayoutOrder = i,
			Size = if on then UDim2.fromOffset(14, 14) else UDim2.fromOffset(10, 10),
			BackgroundColor3 = if on then C.Amber else C.IronLight,
			BackgroundTransparency = if on then 0 else 0.4,
			BorderSizePixel = 0,
		}, { Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
	}, {
		TopBar = e("Frame", {
			Size = UDim2.new(1, 0, 0, BAR_H),
			Position = appear:map(function(a: number)
				return UDim2.fromOffset(0, -BAR_H * (1 - math.min(a, 1)))
			end),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 21,
		}, {
			Line = e("Frame", {
				Size = UDim2.new(1, 0, 0, 3),
				Position = UDim2.new(0, 0, 1, -3),
				BackgroundColor3 = C.Amber,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
			}),
			Title = e(Kit.ChunkText, {
				Text = "TOOL SHOP",
				TextSize = 38,
				Color = C.Amber,
				Align = Enum.TextXAlignment.Left,
				Size = UDim2.fromOffset(320, 46),
				Position = UDim2.fromOffset(40, 8),
			}),
			Subtitle = e(Kit.Text, {
				Text = "Expedition outfitters",
				TextSize = 14,
				Color = C.PaperDark,
				Align = Enum.TextXAlignment.Left,
				Size = UDim2.fromOffset(320, 18),
				Position = UDim2.fromOffset(42, 56),
			}),
			Money = e("Frame", {
				Size = UDim2.fromOffset(200, 42),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -120, 0, 21),
				BackgroundTransparency = 1,
			}, {
				Pill = e(Kit.Plate, {
					Size = UDim2.fromScale(1, 1),
					Fill = C.Iron,
					Radius = 12,
					EdgeThickness = 3,
					Shadow = false,
				}, {
					Coin = if coinImage
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
			}),
			Close = e("Frame", {
				Size = UDim2.fromOffset(64, 64),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -24, 0, 10),
				BackgroundTransparency = 1,
			}, {
				Button = e(Kit.BigButton, {
					Text = "X",
					Variant = "red",
					TextSize = 34,
					Size = UDim2.fromScale(1, 1),
					OnActivated = props.OnClose,
				}),
			}),
		}),

		BottomBar = e("Frame", {
			Size = UDim2.new(1, 0, 0, BAR_H),
			Position = appear:map(function(a: number)
				return UDim2.new(0, 0, 1, -BAR_H + BAR_H * (1 - math.min(a, 1)))
			end),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 21,
		}, {
			Line = e("Frame", {
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = C.Amber,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
			}),
			Nav = e("Frame", {
				Size = UDim2.fromOffset(380, 52),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(cx, 0, 0.5, 0),
				BackgroundTransparency = 1,
			}, {
				Prev = e(Kit.BigButton, {
					Text = "<",
					Variant = "iron",
					TextSize = 30,
					Size = UDim2.fromOffset(64, 52),
					Position = UDim2.fromOffset(0, 0),
					OnActivated = function()
						go(-1)
					end,
				}),
				Next = e(Kit.BigButton, {
					Text = ">",
					Variant = "iron",
					TextSize = 30,
					Size = UDim2.fromOffset(64, 52),
					Position = UDim2.fromOffset(316, 0),
					OnActivated = function()
						go(1)
					end,
				}),
				Dots = e("Frame", {
					Size = UDim2.fromOffset(228, 52),
					Position = UDim2.fromOffset(76, 0),
					BackgroundTransparency = 1,
				}, dots),
			}),
		}),

		Caption = e(Kit.ChunkText, {
			Text = if stop then string.upper(stop.Name) else "",
			TextSize = 46,
			Color = C.Cream,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(cx, 0, 1, -BAR_H - 16),
			Size = UDim2.fromOffset(560, 54),
			ZIndex = 22,
		}),

		Panel = e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = appear:map(function(a: number)
				return UDim2.new(1, -36 + (1 - math.min(a, 1)) * 420, 0.5, 0)
			end),
			Size = UDim2.fromOffset(PW, PH),
			BackgroundTransparency = 1,
			ZIndex = 22,
		}, {
			Scale = e("UIScale", { Scale = fit }),
			Body = e(Kit.Plate, {
				Size = UDim2.fromScale(1, 1),
				Fill = C.IronDark,
				Radius = 20,
				EdgeThickness = 4,
			}, {
				["Card" .. (if stop then stop.Key else "none")] = if stop
					then e(StopCard, { Stop = stop, Money = state.Money, Wave = wave })
					else nil,
			}),
		}),
	})
end

return ShopStage
-- END OF SHOPSTAGE
