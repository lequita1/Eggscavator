local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Everything in the match is first person (the cutscenes use their own scripted camera).
player.CameraMode = Enum.CameraMode.LockFirstPerson

local gui = Instance.new("ScreenGui")
gui.Name = "FirstPersonGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

-- Invisible modal button: while it is Modal the mouse is free, so the shop and journal can be clicked.
local modal = Instance.new("TextButton")
modal.Name = "FreeMouse"
modal.Size = UDim2.fromOffset(2, 2)
modal.BackgroundTransparency = 1
modal.Text = ""
modal.Modal = false
modal.Parent = gui

local dot = Instance.new("Frame")
dot.Name = "Crosshair"
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.new(1, 1, 1)
dot.BorderSizePixel = 0
dot.Visible = false
dot.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = dot
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(0, 0, 0)
stroke.Thickness = 1
stroke.Transparency = 0.3
stroke.Parent = dot

-- The mouse is free while a panel is open, during a cutscene, or while Left Alt is held.
local function wantFree(): boolean
	if player:GetAttribute("UiOpen") then
		return true
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		return true
	end
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Custom then
		return true
	end
	return false
end

RunService.RenderStepped:Connect(function()
	local free = wantFree()
	UserInputService.MouseIconEnabled = free
	if modal.Modal ~= free then
		modal.Modal = free
	end
	local show = not free
		and (
			UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			or UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
		)
	if dot.Visible ~= show then
		dot.Visible = show
	end
end)

print("[FirstPerson] Init OK")
