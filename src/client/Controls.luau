-- Touch and gamepad controls. Mouse + keyboard stay in Client.client.luau;
-- this module adds a twin-stick scheme for phones/tablets (Roblox's own
-- thumbstick moves, our right-hand stick aims and auto-fires) plus buttons,
-- and controller bindings. It switches automatically with the last input used.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Controls = {}

export type Handlers = {
	Reload: () -> (),
	Melee: () -> (),
	SetSprint: (boolean) -> (),
	IsSprinting: () -> boolean,
	CycleWeapon: () -> (),
	ToggleShop: () -> (),
	ToggleBoard: () -> (),
	ModeChanged: (string) -> (),
}

local player = Players.LocalPlayer
local mode = "Mouse" -- "Mouse" | "Touch" | "Gamepad"
local handlers: Handlers

-- Aim state (flat world direction) from the touch stick or right thumbstick.
local touchAim: Vector3? = nil
local touchFiring = false
local padAim: Vector3? = nil
local padFiring = false

local PARCHMENT = Color3.fromRGB(236, 224, 196)
local INK = Color3.fromRGB(45, 32, 22)
local FIRE_THRESHOLD = 0.55 -- push the stick past this fraction to fire
local AIM_DEADZONE = 0.15

-- The camera looks north with "up" on screen = -Z, "right" = +X, so a
-- screen-space stick offset maps straight onto the ground plane.
local function screenToWorld(v: Vector2): Vector3
	return Vector3.new(v.X, 0, v.Y).Unit
end

function Controls.GetMode(): string
	return mode
end

-- Flat aim direction from a stick, or nil when the mouse is in charge.
function Controls.GetAimDirection(): Vector3?
	if mode == "Touch" then
		return touchAim
	elseif mode == "Gamepad" then
		return padAim
	end
	return nil
end

function Controls.IsFiring(): boolean
	return (mode == "Touch" and touchFiring) or (mode == "Gamepad" and padFiring)
end

---------------------------------------------------------------------------
-- Touch UI
---------------------------------------------------------------------------

local touchGui: ScreenGui
local sprintButton: TextButton

local function round(parent: Instance, name: string, text: string, size: number, position: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = position
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.25
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.4
	b.Font = Enum.Font.Garamond
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function buildTouchUI()
	touchGui = Instance.new("ScreenGui")
	touchGui.Name = "TouchControls"
	touchGui.ResetOnSpawn = false
	-- Keep the default inset so AbsolutePosition matches touch positions.
	touchGui.IgnoreGuiInset = false
	touchGui.Enabled = false
	touchGui.DisplayOrder = 5

	local scale = Instance.new("UIScale")
	scale.Parent = touchGui
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(vp.Y / 480, 0.7, 1.25)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Aim stick, bottom right.
	local holder = Instance.new("Frame")
	holder.Name = "AimArea"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -24, 1, -24)
	holder.Size = UDim2.fromOffset(170, 170)
	holder.BackgroundTransparency = 1
	holder.Parent = touchGui

	local pad = Instance.new("Frame")
	pad.Name = "AimPad"
	pad.Size = UDim2.fromScale(1, 1)
	pad.BackgroundColor3 = Color3.fromRGB(30, 22, 18)
	pad.BackgroundTransparency = 0.55
	pad.Active = true
	pad.Parent = holder
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0.5, 0)
	pc.Parent = pad
	local ps = Instance.new("UIStroke")
	ps.Color = PARCHMENT
	ps.Thickness = 2
	ps.Transparency = 0.3
	ps.Parent = pad
	-- Inner ring marks where auto-fire starts.
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(FIRE_THRESHOLD, FIRE_THRESHOLD)
	ring.BackgroundTransparency = 1
	ring.Parent = pad
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Color = Color3.fromRGB(255, 120, 90)
	rs.Thickness = 2
	rs.Transparency = 0.4
	rs.Parent = ring

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(64, 64)
	knob.BackgroundColor3 = PARCHMENT
	knob.BackgroundTransparency = 0.15
	knob.Parent = pad
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0.5, 0)
	kc.Parent = knob
	local kl = Instance.new("TextLabel")
	kl.Size = UDim2.fromScale(1, 1)
	kl.BackgroundTransparency = 1
	kl.Font = Enum.Font.Garamond
	kl.TextScaled = true
	kl.TextColor3 = INK
	kl.Text = "AIM"
	kl.Parent = knob

	local activeTouch: InputObject? = nil
	pad.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
			activeTouch = input
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == activeTouch then
			activeTouch = nil
			touchAim = nil
			touchFiring = false
			knob.Position = UDim2.fromScale(0.5, 0.5)
			kl.Text = "AIM"
		end
	end)
	RunService.RenderStepped:Connect(function()
		local input = activeTouch
		if not input then
			return
		end
		local center = pad.AbsolutePosition + pad.AbsoluteSize / 2
		local radius = pad.AbsoluteSize.X / 2
		local offset = Vector2.new(input.Position.X, input.Position.Y) - center
		local amount = math.min(1, offset.Magnitude / radius)
		local clamped = if offset.Magnitude > 0 then offset.Unit * amount else Vector2.zero
		knob.Position = UDim2.fromScale(0.5 + clamped.X / 2, 0.5 + clamped.Y / 2)
		if amount > AIM_DEADZONE then
			touchAim = screenToWorld(offset)
			touchFiring = amount >= FIRE_THRESHOLD
			kl.Text = if touchFiring then "FIRE" else "AIM"
		else
			touchAim = nil
			touchFiring = false
			kl.Text = "AIM"
		end
	end)

	-- Action buttons fanned around the stick.
	local red = Color3.fromRGB(170, 40, 35)
	local blue = Color3.fromRGB(40, 70, 140)
	local brown = Color3.fromRGB(110, 80, 50)
	round(touchGui, "Reload", "Reload", 66, UDim2.new(1, -235, 1, -60), blue).Activated:Connect(function()
		handlers.Reload()
	end)
	round(touchGui, "Hatchet", "Hatchet", 66, UDim2.new(1, -230, 1, -140), red).Activated:Connect(function()
		handlers.Melee()
	end)
	round(touchGui, "Swap", "Swap", 60, UDim2.new(1, -175, 1, -215), brown).Activated:Connect(function()
		handlers.CycleWeapon()
	end)
	sprintButton = round(touchGui, "Sprint", "Sprint", 60, UDim2.new(1, -95, 1, -235), brown)
	sprintButton.Activated:Connect(function()
		handlers.SetSprint(not handlers.IsSprinting())
	end)
	round(touchGui, "Shop", "Shop", 50, UDim2.new(1, -40, 0.42, 0), brown).Activated:Connect(function()
		handlers.ToggleShop()
	end)
	round(touchGui, "Board", "Board", 50, UDim2.new(1, -40, 0.42, 60), brown).Activated:Connect(function()
		handlers.ToggleBoard()
	end)

	touchGui.Parent = player:WaitForChild("PlayerGui")
end

-- Roblox shows a jump button on phones; there's no jumping in this game.
local function hideJumpButton()
	local touch = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("TouchGui")
	local jump = touch and touch:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") then
		jump.Visible = false
	end
end

---------------------------------------------------------------------------
-- Gamepad
---------------------------------------------------------------------------

local function bindGamepad()
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(input.Position.X, -input.Position.Y)
			padAim = if v.Magnitude > 0.25 then screenToWorld(v) else padAim
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonR2 then
			padFiring = true
		elseif key == Enum.KeyCode.ButtonL2 then
			handlers.SetSprint(true)
		elseif processed then
			return
		elseif key == Enum.KeyCode.ButtonX then
			handlers.Reload()
		elseif key == Enum.KeyCode.ButtonR1 then
			handlers.Melee()
		elseif key == Enum.KeyCode.ButtonY then
			handlers.CycleWeapon()
		elseif key == Enum.KeyCode.DPadUp then
			handlers.ToggleShop()
		elseif key == Enum.KeyCode.DPadDown then
			handlers.ToggleBoard()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			padFiring = false
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			handlers.SetSprint(false)
		end
	end)
end

---------------------------------------------------------------------------

local function modeFor(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" then
		return "Mouse"
	end
	return nil
end

local function setMode(newMode: string)
	if newMode == mode then
		return
	end
	mode = newMode
	touchGui.Enabled = mode == "Touch"
	if mode ~= "Touch" then
		touchAim = nil
		touchFiring = false
	end
	if mode ~= "Gamepad" then
		padFiring = false
	end
	handlers.ModeChanged(mode)
end

function Controls.Init(h: Handlers)
	handlers = h
	buildTouchUI()
	bindGamepad()

	local initial = "Mouse"
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		initial = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		initial = "Gamepad"
	end
	mode = ""
	setMode(initial)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local m = modeFor(inputType)
		if m then
			setMode(m)
		end
	end)

	-- Keep the sprint button's look in sync and the jump button hidden.
	task.spawn(function()
		while true do
			if mode == "Touch" then
				hideJumpButton()
				sprintButton.BackgroundTransparency = if handlers.IsSprinting() then 0 else 0.25
				sprintButton.Text = if handlers.IsSprinting() then "Running" else "Sprint"
			end
			task.wait(0.25)
		end
	end)
end

return Controls
