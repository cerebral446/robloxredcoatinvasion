-- HUD (health, ammo, wave info, powder stores), announcements, crosshair,
-- and the between-wave shop. Built entirely in code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local gameState = ReplicatedStorage:WaitForChild("GameState")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local Interface = {}

local PARCHMENT = Color3.fromRGB(236, 224, 196)
local INK = Color3.fromRGB(45, 32, 22)
local RED = Color3.fromRGB(190, 40, 35)
local BLUE = Color3.fromRGB(40, 70, 140)
local FONT = Enum.Font.Antique
local FONT_BOLD = Enum.Font.Garamond

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(color: Color3?, thickness: number?): UIStroke
	return new("UIStroke", { Color = color or INK, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = INK,
		TextScaled = true,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base)
end

local function bar(parent: Instance, position: UDim2, size: UDim2, color: Color3, title: string): (Frame, TextLabel)
	local back = new("Frame", {
		Parent = parent,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(40, 30, 25),
	}, { corner(4), stroke(INK, 2) })
	local fill = new("Frame", {
		Parent = back,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, { corner(4) })
	local text = label({
		Parent = back,
		Size = UDim2.fromScale(1, 1),
		Text = title,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
		Font = FONT_BOLD,
		ZIndex = 2,
	})
	return fill, text
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local gui: ScreenGui
local refs: { [string]: any } = {}
local shopOpen = false
local shopFrame: Frame
local shopStatus: TextLabel
local shopRefreshers: { () -> () } = {}

local function buildHud()
	gui = new("ScreenGui", {
		Name = "RedcoatHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Top banner: wave + phase + stores.
	local top = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(420, 92),
		BackgroundColor3 = PARCHMENT,
		BackgroundTransparency = 0.05,
	}, { corner(8), stroke(INK, 3) })
	refs.WaveLabel = label({ Parent = top, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 30), Font = FONT_BOLD, Text = "Redcoat Invasion" })
	refs.PhaseLabel = label({ Parent = top, Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 20), Text = "" })
	refs.StoresFill, refs.StoresText = bar(top, UDim2.fromOffset(16, 62), UDim2.new(1, -32, 0, 20), Color3.fromRGB(200, 140, 50), "Powder Stores")

	-- Bottom left: health + money.
	local status = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(280, 92),
		BackgroundColor3 = PARCHMENT,
		BackgroundTransparency = 0.05,
	}, { corner(8), stroke(INK, 3) })
	refs.HealthFill, refs.HealthText = bar(status, UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 26), RED, "Health")
	refs.MoneyLabel = label({ Parent = status, Position = UDim2.fromOffset(12, 46), Size = UDim2.new(0.5, -12, 0, 34), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "$0" })
	refs.AlliesLabel = label({ Parent = status, Position = UDim2.new(0.5, 0, 0, 50), Size = UDim2.new(0.5, -12, 0, 26), TextXAlignment = Enum.TextXAlignment.Right, Text = "" })

	-- Bottom right: weapon + ammo + reload.
	local weapon = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(300, 120),
		BackgroundColor3 = PARCHMENT,
		BackgroundTransparency = 0.05,
	}, { corner(8), stroke(INK, 3) })
	refs.WeaponLabel = label({ Parent = weapon, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "Musket" })
	refs.AmmoRow = new("Frame", { Parent = weapon, Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	refs.ReloadFill, refs.ReloadText = bar(weapon, UDim2.fromOffset(12, 70), UDim2.new(1, -24, 0, 18), Color3.fromRGB(90, 90, 90), "")
	refs.SlotsLabel = label({ Parent = weapon, Position = UDim2.fromOffset(12, 94), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Text = "" })

	-- Controls hint.
	label({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(780, 18),
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		Text = "WASD move  |  Shift sprint  |  Mouse aim  |  Click fire  |  R reload  |  F / Right-click hatchet  |  1-4 weapons  |  B shop",
	})

	-- Announcement banner.
	refs.Banner = label({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 60),
		Font = FONT_BOLD,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		TextTransparency = 1,
		TextStrokeColor3 = INK,
		Text = "",
	})

	-- Death notice.
	refs.DeadLabel = label({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(700, 40),
		Font = FONT_BOLD,
		TextColor3 = Color3.fromRGB(255, 120, 110),
		TextStrokeTransparency = 0,
		Text = "You have fallen! You will rejoin the fight next wave.",
		Visible = false,
	})

	-- Crosshair that follows the mouse.
	refs.Crosshair = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, {
		corner(13),
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }),
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }),
	})
	refs.CrossReload = new("Frame", {
		Parent = refs.Crosshair,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Color3.fromRGB(255, 220, 120),
		BorderSizePixel = 0,
	})
end

---------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------

local purchaseRemote = remotes:WaitForChild("Purchase") :: RemoteFunction
local readyRemote = remotes:WaitForChild("Ready") :: RemoteEvent

local function shopButton(parent: Instance, order: number, title: string, desc: string, onClick: () -> (), refresh: (TextButton, TextLabel) -> ())
	local row = new("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = Color3.fromRGB(246, 238, 218),
	}, { corner(6), stroke(Color3.fromRGB(150, 130, 100), 1) })
	label({ Parent = row, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -140, 0, 24), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = title })
	local info = label({ Parent = row, Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -140, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(90, 70, 50), Text = desc })
	local button = new("TextButton", {
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(118, 36),
		BackgroundColor3 = BLUE,
		TextColor3 = Color3.new(1, 1, 1),
		Font = FONT_BOLD,
		TextScaled = true,
		AutoButtonColor = true,
		Text = "",
	}, { corner(6), new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }) })
	button.Activated:Connect(onClick)
	local function doRefresh()
		refresh(button, info)
	end
	table.insert(shopRefreshers, doRefresh)
	doRefresh()
end

local function setStatus(text: string, good: boolean)
	shopStatus.Text = text
	shopStatus.TextColor3 = if good then Color3.fromRGB(40, 110, 40) else RED
end

local function buy(kind: string, id: string?)
	local ok, msg = purchaseRemote:InvokeServer(kind, id)
	setStatus(msg or "", ok)
	for _, r in shopRefreshers do
		r()
	end
end

local function section(parent: Instance, order: number, title: string)
	label({ Parent = parent, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 28), Font = FONT_BOLD, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Left, Text = title })
end

local function sortedKeys<T>(t: { [string]: T }, orderOf: (T) -> number): { string }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return orderOf(t[a]) < orderOf(t[b])
	end)
	return keys
end

local function buildShop()
	shopFrame = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0, 560, 0.62, 0),
		BackgroundColor3 = PARCHMENT,
		Visible = false,
		ZIndex = 5,
	}, { corner(10), stroke(INK, 4) })
	label({ Parent = shopFrame, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 40), Font = FONT_BOLD, Text = "Quartermaster" })
	shopStatus = label({ Parent = shopFrame, Position = UDim2.fromOffset(16, 48), Size = UDim2.new(1, -32, 0, 20), Text = "Spend your dollars before the Regulars arrive." })

	local list = new("ScrollingFrame", {
		Parent = shopFrame,
		Position = UDim2.fromOffset(16, 74),
		Size = UDim2.new(1, -32, 1, -140),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	section(list, nextOrder(), "Firearms")
	for _, id in sortedKeys(Config.Weapons, function(w)
		return w.Order
	end) do
		local w = Config.Weapons[id]
		local desc = ("%s  Dmg %d, reload %.1fs"):format(w.Description, w.Damage, w.ReloadTime)
		shopButton(list, nextOrder(), w.Name, desc, function()
			buy("Weapon", id)
		end, function(button)
			if player:GetAttribute("Weapon") == id then
				button.Text = "Equipped"
				button.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
			elseif player:GetAttribute("Owns_" .. id) then
				button.Text = "Equip"
				button.BackgroundColor3 = BLUE
			else
				button.Text = "$" .. w.Price
				button.BackgroundColor3 = if (player:GetAttribute("Money") or 0) >= w.Price then Color3.fromRGB(50, 120, 50) else Color3.fromRGB(140, 90, 80)
			end
		end)
	end

	section(list, nextOrder(), "Training")
	for _, id in sortedKeys(Config.Upgrades, function(u)
		return u.Order
	end) do
		local up = Config.Upgrades[id]
		shopButton(list, nextOrder(), up.Name, up.Description, function()
			buy("Upgrade", id)
		end, function(button, info)
			local level = player:GetAttribute("Up_" .. id) or 0
			info.Text = ("%s  (level %d/%d)"):format(up.Description, level, up.MaxLevel)
			if level >= up.MaxLevel then
				button.Text = "Maxed"
				button.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
			else
				local cost = up.BaseCost * (level + 1)
				button.Text = "$" .. cost
				button.BackgroundColor3 = if (player:GetAttribute("Money") or 0) >= cost then Color3.fromRGB(50, 120, 50) else Color3.fromRGB(140, 90, 80)
			end
		end)
	end

	section(list, nextOrder(), "Reinforcements")
	shopButton(list, nextOrder(), "Hire a Minuteman", "A militiaman follows you and fires on the Regulars.", function()
		buy("Ally")
	end, function(button, info)
		local count = player:GetAttribute("Allies") or 0
		info.Text = ("Follows you and fires on the Regulars.  (%d/%d)"):format(count, Config.Allies.MaxPerPlayer)
		button.Text = if count >= Config.Allies.MaxPerPlayer then "Full" else "$" .. Config.Allies.HireCost
		button.BackgroundColor3 = if count < Config.Allies.MaxPerPlayer and (player:GetAttribute("Money") or 0) >= Config.Allies.HireCost
			then Color3.fromRGB(50, 120, 50)
			else Color3.fromRGB(140, 90, 80)
	end)
	shopButton(list, nextOrder(), "Repair the Powder Stores", ("Restores %d health to the stores."):format(Config.Stores.RepairAmount), function()
		buy("Repair")
	end, function(button)
		button.Text = "$" .. Config.Stores.RepairCost
		local damaged = (gameState:GetAttribute("StoresHealth") or 0) < (gameState:GetAttribute("StoresMax") or 0)
		button.BackgroundColor3 = if damaged and (player:GetAttribute("Money") or 0) >= Config.Stores.RepairCost
			then Color3.fromRGB(50, 120, 50)
			else Color3.fromRGB(140, 90, 80)
	end)

	-- Footer buttons.
	local readyButton = new("TextButton", {
		Parent = shopFrame,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -12),
		Size = UDim2.fromOffset(200, 44),
		BackgroundColor3 = RED,
		TextColor3 = Color3.new(1, 1, 1),
		Font = FONT_BOLD,
		TextScaled = true,
		Text = "Ready for battle!",
	}, { corner(6), new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	readyButton.Activated:Connect(function()
		readyRemote:FireServer()
		readyButton.Text = "Waiting for others..."
	end)
	player:GetAttributeChangedSignal("Ready"):Connect(function()
		if not player:GetAttribute("Ready") then
			readyButton.Text = "Ready for battle!"
		end
	end)

	local closeButton = new("TextButton", {
		Parent = shopFrame,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -12),
		Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = Color3.fromRGB(110, 100, 90),
		TextColor3 = Color3.new(1, 1, 1),
		Font = FONT_BOLD,
		TextScaled = true,
		Text = "Close (B)",
	}, { corner(6), new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	closeButton.Activated:Connect(function()
		Interface.SetShopOpen(false)
	end)

	for _, attr in { "Money", "Weapon", "Allies" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			for _, r in shopRefreshers do
				r()
			end
		end)
	end
end

function Interface.SetShopOpen(open: boolean)
	local phase = gameState:GetAttribute("Phase")
	if open and phase ~= "Intermission" and phase ~= "Waiting" then
		Interface.Announce("The quartermaster only trades between waves.", RED)
		return
	end
	shopOpen = open
	shopFrame.Visible = open
	if open then
		for _, r in shopRefreshers do
			r()
		end
	end
end

function Interface.ToggleShop()
	Interface.SetShopOpen(not shopOpen)
end

function Interface.IsShopOpen(): boolean
	return shopOpen
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local bannerToken = 0
function Interface.Announce(text: string, color: Color3?)
	bannerToken += 1
	local token = bannerToken
	local banner = refs.Banner :: TextLabel
	banner.Text = text
	banner.TextColor3 = color or Color3.new(1, 1, 1)
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0
	task.delay(3.5, function()
		if token == bannerToken then
			TweenService:Create(banner, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local lastAmmo = -1
local lastCapacity = -1
local function refreshAmmo()
	local ammo = player:GetAttribute("Ammo") or 0
	local capacity = player:GetAttribute("Capacity") or 1
	if ammo == lastAmmo and capacity == lastCapacity then
		return
	end
	lastAmmo, lastCapacity = ammo, capacity
	for _, c in refs.AmmoRow:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i = 1, capacity do
		new("Frame", {
			Parent = refs.AmmoRow,
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = if i <= ammo then Color3.fromRGB(60, 60, 60) else Color3.fromRGB(200, 190, 170),
		}, { corner(8), stroke(INK, 1) })
	end
end

function Interface.Update()
	local t = workspace:GetServerTimeNow()
	local phase = gameState:GetAttribute("Phase")
	local wave = gameState:GetAttribute("Wave") or 0
	local final = gameState:GetAttribute("FinalWave") or Config.Rounds.FinalWave
	local phaseEnd = gameState:GetAttribute("PhaseEnd") or 0

	if phase == "Intermission" then
		refs.WaveLabel.Text = ("Wave %d of %d approaching"):format(wave + 1, final)
		refs.PhaseLabel.Text = ("Prepare! The Regulars march in %s  -  press B to shop"):format(formatTime(phaseEnd - t))
	elseif phase == "Wave" then
		local name = gameState:GetAttribute("WaveName") or ""
		refs.WaveLabel.Text = ("Wave %d of %d%s"):format(wave, final, if name ~= "" then ": " .. name else "")
		refs.PhaseLabel.Text = ("Redcoats remaining: %d"):format(gameState:GetAttribute("EnemiesLeft") or 0)
	elseif phase == "GameOver" then
		refs.WaveLabel.Text = "Defeat"
		refs.PhaseLabel.Text = ("A new battle begins in %s"):format(formatTime(phaseEnd - t))
	elseif phase == "Victory" then
		refs.WaveLabel.Text = "Victory!"
		refs.PhaseLabel.Text = ("A new battle begins in %s"):format(formatTime(phaseEnd - t))
	else
		refs.WaveLabel.Text = "Redcoat Invasion"
		refs.PhaseLabel.Text = "Waiting for militia..."
	end

	local storesHp = gameState:GetAttribute("StoresHealth") or 0
	local storesMax = gameState:GetAttribute("StoresMax") or 1
	refs.StoresFill.Size = UDim2.fromScale(math.clamp(storesHp / storesMax, 0, 1), 1)
	refs.StoresText.Text = ("Powder Stores  %d / %d"):format(storesHp, storesMax)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local alive = hum ~= nil and hum.Health > 0
	if hum then
		refs.HealthFill.Size = UDim2.fromScale(math.clamp(hum.Health / hum.MaxHealth, 0, 1), 1)
		refs.HealthText.Text = ("Health  %d / %d"):format(math.max(0, math.ceil(hum.Health)), hum.MaxHealth)
	else
		refs.HealthFill.Size = UDim2.fromScale(0, 1)
		refs.HealthText.Text = "Health"
	end
	refs.DeadLabel.Visible = not alive and phase == "Wave"

	refs.MoneyLabel.Text = "$" .. (player:GetAttribute("Money") or 0)
	local allies = player:GetAttribute("Allies") or 0
	refs.AlliesLabel.Text = if allies > 0 then ("Minutemen: %d"):format(allies) else ""

	local weaponId = player:GetAttribute("Weapon") or "Musket"
	local weapon = Config.Weapons[weaponId]
	refs.WeaponLabel.Text = if weapon then weapon.Name else weaponId
	refreshAmmo()

	local reloadEnd = player:GetAttribute("ReloadEnd") or 0
	local duration = player:GetAttribute("ReloadDuration") or 1
	if reloadEnd > t then
		local progress = 1 - (reloadEnd - t) / duration
		refs.ReloadFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		refs.ReloadFill.BackgroundColor3 = Color3.fromRGB(220, 170, 60)
		refs.ReloadText.Text = "Loading..."
		refs.CrossReload.Size = UDim2.fromOffset(26 * math.clamp(progress, 0, 1), 4)
	else
		local loaded = (player:GetAttribute("Ammo") or 0) > 0
		refs.ReloadFill.Size = UDim2.fromScale(1, 1)
		refs.ReloadFill.BackgroundColor3 = if loaded then Color3.fromRGB(70, 130, 70) else Color3.fromRGB(150, 60, 50)
		refs.ReloadText.Text = if loaded then "Ready" else "Empty - press R"
		refs.CrossReload.Size = UDim2.fromOffset(0, 4)
	end

	local slots = {}
	for _, id in sortedKeys(Config.Weapons, function(w)
		return w.Order
	end) do
		if player:GetAttribute("Owns_" .. id) then
			table.insert(slots, ("[%d] %s"):format(Config.Weapons[id].Order, Config.Weapons[id].Name))
		end
	end
	refs.SlotsLabel.Text = table.concat(slots, "   ")

	local mouse = UserInputService:GetMouseLocation()
	refs.Crosshair.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	refs.Crosshair.Visible = alive and not shopOpen
	UserInputService.MouseIconEnabled = shopOpen or not alive
end

function Interface.Init()
	buildHud()
	buildShop()

	local announce = remotes:WaitForChild("Announce") :: RemoteEvent
	announce.OnClientEvent:Connect(function(text: string, color: Color3?)
		Interface.Announce(text, color)
	end)

	gameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = gameState:GetAttribute("Phase")
		if phase == "Intermission" then
			Interface.SetShopOpen(true)
		elseif shopOpen then
			Interface.SetShopOpen(false)
		end
	end)
	gameState:GetAttributeChangedSignal("StoresHealth"):Connect(function()
		for _, r in shopRefreshers do
			r()
		end
	end)
end

return Interface
