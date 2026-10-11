-- Redcoat Invasion client: top-down camera, mouse aiming and input.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Interface = require(script.Parent:WaitForChild("Interface"))
local Townsfolk = require(script.Parent:WaitForChild("Townsfolk"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireRemote = remotes:WaitForChild("Fire") :: RemoteEvent
local reloadRemote = remotes:WaitForChild("Reload") :: RemoteEvent
local meleeRemote = remotes:WaitForChild("Melee") :: RemoteEvent
local equipRemote = remotes:WaitForChild("Equip") :: RemoteEvent
local sprintRemote = remotes:WaitForChild("Sprint") :: RemoteEvent

-- Hide default Roblox UI we don't use.
for _, coreType in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreType, false)
	end)
end

Effects.Init()
Interface.Init()
-- Villagers are cosmetic; never let them break the rest of the client.
task.spawn(function()
	local ok, err = pcall(Townsfolk.Init)
	if not ok then
		warn("Townsfolk failed to start:", err)
	end
end)

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------

local MIN_HEIGHT, MAX_HEIGHT = 45, 120
local cameraHeight = 75
local cameraFocus = Config.Map.PlayerSpawn

local function getCharacter(): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	return char, root, hum
end

-- Where the mouse points on the plane that musket balls travel along.
local function mouseAimPoint(): Vector3?
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = (Config.ShotHeight - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		cameraHeight = math.clamp(cameraHeight - input.Position.Z * 6, MIN_HEIGHT, MAX_HEIGHT)
	end
end)

RunService:BindToRenderStep("RedcoatCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	local _, root, hum = getCharacter()
	local target: Vector3
	if root and hum and hum.Health > 0 then
		target = root.Position
		-- Peek slightly toward the cursor so you can see further ahead.
		local aim = mouseAimPoint()
		if aim then
			local lean = Vector3.new(aim.X - target.X, 0, aim.Z - target.Z)
			if lean.Magnitude > 40 then
				lean = lean.Unit * 40
			end
			target += lean * 0.25
		end
	else
		-- Spectate the powder stores while down.
		target = Config.Map.StoresPosition + Vector3.new(0, 0, -40)
	end
	cameraFocus = cameraFocus:Lerp(Vector3.new(target.X, 0, target.Z), math.min(1, dt * 8))
	-- Mostly overhead with a slight tilt, so "up" on screen is north.
	camera.CFrame = CFrame.lookAt(cameraFocus + Vector3.new(0, cameraHeight, cameraHeight * 0.3), cameraFocus)
	camera.FieldOfView = 60
end)

-- Face the mouse.
RunService.RenderStepped:Connect(function()
	local _, root, hum = getCharacter()
	if root and hum and hum.Health > 0 and not Interface.IsShopOpen() then
		hum.AutoRotate = false
		local aim = mouseAimPoint()
		if aim then
			local flatAim = Vector3.new(aim.X, root.Position.Y, aim.Z)
			if (flatAim - root.Position).Magnitude > 0.5 then
				root.CFrame = CFrame.lookAt(root.Position, flatAim)
			end
		end
	end
	Interface.Update()
end)

---------------------------------------------------------------------------
-- Hold the gun: the server raises the arms (Motor6D.C0); here we cancel the
-- walk/idle animation on the arm joints each frame so the hands stay on the
-- weapon. Runs for every player's character so everyone sees it.
---------------------------------------------------------------------------

local ARM_JOINTS = { "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist", "Right Shoulder", "Left Shoulder" }
local jointCache: { [Model]: { Motor6D } } = {}

local function armJoints(char: Model): { Motor6D }
	local cached = jointCache[char]
	if cached then
		local valid = true
		for _, j in cached do
			if not j.Parent or not j:IsDescendantOf(char) then
				valid = false
				break
			end
		end
		if valid and #cached > 0 then
			return cached
		end
	end
	local list = {}
	for _, name in ARM_JOINTS do
		local j = char:FindFirstChild(name, true)
		if j and j:IsA("Motor6D") then
			table.insert(list, j)
		end
	end
	jointCache[char] = list
	return list
end

RunService.Stepped:Connect(function()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char and char:FindFirstChild("PropWeapon") then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				for _, j in armJoints(char) do
					j.Transform = CFrame.identity
				end
			end
		end
	end
	for char in jointCache do
		if not char.Parent then
			jointCache[char] = nil
		end
	end
end)

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local triggerHeld = false

local function tryFire()
	local _, root, hum = getCharacter()
	if not root or not hum or hum.Health <= 0 or Interface.IsShopOpen() then
		return
	end
	local aim = mouseAimPoint()
	if aim then
		fireRemote:FireServer(aim)
	end
end

local WEAPON_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

local function weaponBySlot(slot: number): string?
	for id, w in Config.Weapons do
		if w.Order == slot and player:GetAttribute("Owns_" .. id) then
			return id
		end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = true
		tryFire()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.F then
		if not Interface.IsShopOpen() then
			meleeRemote:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		reloadRemote:FireServer()
	elseif input.KeyCode == Enum.KeyCode.B then
		Interface.ToggleShop()
	elseif WEAPON_KEYS[input.KeyCode] then
		local id = weaponBySlot(WEAPON_KEYS[input.KeyCode])
		if id then
			equipRemote:FireServer(id)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = false
	end
end)

-- Hold Shift to sprint (the server sets the actual walk speed).
local sprinting = false
local function setSprint(on: boolean)
	if sprinting ~= on then
		sprinting = on
		sprintRemote:FireServer(on)
	end
end
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	setSprint(false)
end)

-- Holding the trigger keeps firing as soon as the weapon is loaded
-- (useful with the Brace of Pistols).
task.spawn(function()
	while true do
		task.wait(0.15)
		if triggerHeld and (player:GetAttribute("Ammo") or 0) > 0 and (player:GetAttribute("ReloadEnd") or 0) == 0 then
			tryFire()
		end
	end
end)

-- No jumping in a top-down shooter; free up Space.
ContextActionService:BindActionAtPriority("BlockJump", function()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
