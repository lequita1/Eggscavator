local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.ReactLua.React)

local UI = script.Parent
local Theme = require(UI.Theme)
local Store = require(UI.Store)
local Kit = require(UI.Kit)

local e = React.createElement
local C = Theme.Colors
local player = Players.LocalPlayer

local SLOT = 78

local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

-- Looks at the character and backpack: which tool is held, and which tool instance is which.
-- A break tool is identified by ToolId, a pickup gear tool (Brush, Vacuum) by GearId.
local function scan()
	local held = nil
	local tools = {}

	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				local id = child:GetAttribute("ToolId") or child:GetAttribute("GearId")
				if id then
					tools[id] = child
					held = id
				end
			end
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				local id = child:GetAttribute("ToolId") or child:GetAttribute("GearId")
				if id then
					tools[id] = child
				end
			end
		end
	end

	local ids = {}
	for id in tools do
		table.insert(ids, id)
	end
	table.sort(ids)

	return { Held = held, Tools = tools, Signature = (held or "-") .. ":" .. table.concat(ids, ",") }
end

local function useToolSnapshot()
	local snapshot, setSnapshot = React.useState(scan)
	React.useEffect(function()
		local alive = true
		task.spawn(function()
			while alive do
				local fresh = scan()
				setSnapshot(function(old)
					if old.Signature == fresh.Signature then
						return old -- nothing changed, no re-render
					end
					return fresh
				end)
				task.wait(0.15)
			end
		end)
		return function()
			alive = false
		end
	end, {})
	return snapshot
end

-- Equip, or unequip if it's already held. Re-scans so it never uses a stale tool after respawn.
local function toggleTool(toolId: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = scan()
	local tool = now.Tools[toolId]
	if not tool then
		return
	end
	if now.Held == toolId then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

---------------------------------------------------------------------
-- One slot
---------------------------------------------------------------------
local function Slot(props)
	local tool = props.Tool
	local owned = tool.Owned
	local selected = props.Selected and owned
	local lift = Kit.useSpring(if selected then 0 else 8, 320, 16)

	local image = Theme.Icons and Theme.Icons[tool.Id]
	local content
	if not owned then
		content = e(Kit.ChunkText, { Text = "?", TextSize = 40, Color = C.PaperDark, ZIndex = 3 })
	elseif image and image ~= "" then
		content = e("ImageLabel", {
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		})
	else
		content = e(Kit.ChunkText, {
			Text = string.upper(string.sub(tool.Name, 1, 1)),
			TextSize = 42,
			ZIndex = 3,
		})
	end

	return e("Frame", {
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(SLOT, SLOT + 26),
		BackgroundTransparency = 1,
	}, {
		Body = e(Kit.Plate, {
			Size = UDim2.fromOffset(SLOT, SLOT),
			Position = lift:map(function(y: number)
				return UDim2.fromOffset(0, y)
			end),
			Fill = if not owned then C.IronDark elseif selected then C.Amber else C.Iron,
			Edge = if selected then C.Cream else C.Ink,
			EdgeThickness = if selected then 4 else 3,
			Radius = 14,
		}, {
			Content = content,
			Key = if owned
				then e(Kit.ChunkText, {
					Text = tostring(props.Index),
					TextSize = 16,
					Stroke = 2,
					Drop = 2,
					Size = UDim2.fromOffset(22, 22),
					Position = UDim2.fromOffset(4, 2),
					ZIndex = 4,
				})
				else nil,
		}),
		Name = e(Kit.ChunkText, {
			Text = if owned then tool.Name else "???",
			TextSize = 15,
			Stroke = 2,
			Drop = 2,
			Color = if selected then C.Amber else C.Cream,
			Size = UDim2.fromOffset(SLOT + 20, 20),
			Position = UDim2.new(0.5, -(SLOT + 20) / 2, 0, SLOT + 8),
		}),
		Hit = e("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 6,
			[React.Event.Activated] = function()
				if owned then
					toggleTool(tool.Id)
				end
			end,
		}),
	})
end

---------------------------------------------------------------------
-- The hotbar: break tools first, then pickup gear (Brush, Vacuum)
---------------------------------------------------------------------
local function Hotbar()
	local state = Store.useStore()
	local snapshot = useToolSnapshot()

	local entries = {}
	for _, tool in state.Tools do
		table.insert(entries, tool)
	end
	for _, gear in state.Gear or {} do
		table.insert(entries, gear)
	end

	-- the Climb Rig is always the first slot: a locked ? until it is bought, then the tool
	table.insert(entries, 1, { Id = "ClimbRig", Name = "Ladder", Owned = (state.ClimbTier or 0) >= 1 })

	local entriesRef = React.useRef(entries)
	entriesRef.current = entries

	React.useEffect(function()
		-- Turn off Roblox's default backpack bar (retry, because CoreGui can be slow at startup)
		task.spawn(function()
			for _ = 1, 20 do
				local ok = pcall(function()
					StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
				end)
				if ok then
					break
				end
				task.wait(0.5)
			end
		end)

		-- Number keys 1-9 pick the slot
		local connection = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			local slot = KEYS[input.KeyCode]
			if not slot then
				return
			end
			local entry = entriesRef.current[slot]
			if entry and entry.Owned then
				toggleTool(entry.Id)
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	local kids = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, tool in entries do
		kids["Slot" .. tool.Id] = e(Slot, {
			LayoutOrder = index,
			Index = index,
			Tool = tool,
			Selected = snapshot.Held == tool.Id,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(0, SLOT + 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, kids)
end

return Hotbar