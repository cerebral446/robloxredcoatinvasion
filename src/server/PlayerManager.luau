-- Per-player state: money, weapons, upgrades, firing, reloading and the shop.
-- State the client needs to draw the HUD is mirrored onto player attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FX = require(script.Parent:WaitForChild("FX"))
local Units = require(script.Parent:WaitForChild("Units"))

local PlayerManager = {}

type Data = {
	Money: number,
	Kills: number,
	Owned: { [string]: boolean },
	Equipped: string,
	Ammo: { [string]: number },
	ReloadToken: number,
	Reloading: boolean,
	Spawning: boolean,
	LastFire: number,
	LastMelee: number,
	Upgrades: { [string]: number },
}

local data: { [Player]: Data } = {}

-- How far past the shot origin each weapon's visible muzzle sits.
local MUZZLE_DISTANCE = { Musket = 3.6, LongRifle = 4.6, Blunderbuss = 2.6, Pistols = 1.2 }
local gameState: Instance
local canShop: () -> boolean = function()
	return false
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getRoot(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return nil, nil
	end
	return root, hum
end

local function upgradeValue(d: Data, id: string): number
	return (d.Upgrades[id] or 0) * Config.Upgrades[id].PerLevel
end

local function reloadTime(d: Data, weapon: Config.WeaponDef): number
	return weapon.ReloadTime * math.max(0.3, 1 - upgradeValue(d, "Reload"))
end

local function walkSpeed(d: Data): number
	return Config.Player.WalkSpeed + upgradeValue(d, "Speed")
end

local function sync(player: Player)
	local d = data[player]
	if not d then
		return
	end
	local weapon = Config.Weapons[d.Equipped]
	player:SetAttribute("Money", d.Money)
	player:SetAttribute("Weapon", d.Equipped)
	player:SetAttribute("Ammo", d.Ammo[d.Equipped] or 0)
	player:SetAttribute("Capacity", weapon.Capacity)
	player:SetAttribute("Reloading", d.Reloading)
	for id in Config.Weapons do
		player:SetAttribute("Owns_" .. id, d.Owned[id] == true)
	end
	for id in Config.Upgrades do
		player:SetAttribute("Up_" .. id, d.Upgrades[id] or 0)
	end
	player:SetAttribute("Allies", Units.CountOwnedBy(player))

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local kills = stats:FindFirstChild("Kills") :: IntValue
		local money = stats:FindFirstChild("Dollars") :: IntValue
		kills.Value = d.Kills
		money.Value = d.Money
	end
end
PlayerManager.Sync = sync

local function setSpeed(player: Player)
	local d = data[player]
	local _, hum = getRoot(player)
	if d and hum then
		hum.WalkSpeed = if d.Reloading then Config.Player.ReloadWalkSpeed + upgradeValue(d, "Speed") else walkSpeed(d)
	end
end

local function cancelReload(player: Player)
	local d = data[player]
	if d and d.Reloading then
		d.ReloadToken += 1
		d.Reloading = false
		player:SetAttribute("ReloadEnd", 0)
		setSpeed(player)
	end
end

local function startReload(player: Player)
	local d = data[player]
	if not d or d.Reloading then
		return
	end
	local weapon = Config.Weapons[d.Equipped]
	if d.Ammo[d.Equipped] >= weapon.Capacity then
		return
	end
	if not getRoot(player) then
		return
	end
	d.Reloading = true
	d.ReloadToken += 1
	local token = d.ReloadToken
	local duration = reloadTime(d, weapon)
	player:SetAttribute("ReloadEnd", now() + duration)
	player:SetAttribute("ReloadDuration", duration)
	setSpeed(player)
	sync(player)
	task.delay(duration, function()
		if data[player] == d and d.ReloadToken == token and d.Reloading then
			d.Reloading = false
			d.Ammo[d.Equipped] = weapon.Capacity
			player:SetAttribute("ReloadEnd", 0)
			setSpeed(player)
			sync(player)
		end
	end)
end

local function fire(player: Player, aimPoint: Vector3)
	local d = data[player]
	if not d or typeof(aimPoint) ~= "Vector3" then
		return
	end
	local root, hum = getRoot(player)
	if not root or not hum then
		return
	end
	local weapon = Config.Weapons[d.Equipped]
	local t = now()
	if d.Reloading or t - d.LastFire < weapon.FireCooldown then
		return
	end
	if (d.Ammo[d.Equipped] or 0) <= 0 then
		startReload(player)
		return
	end
	d.LastFire = t
	d.Ammo[d.Equipped] -= 1

	local forward = Vector3.new(aimPoint.X - root.Position.X, 0, aimPoint.Z - root.Position.Z)
	if forward.Magnitude < 0.5 then
		forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	forward = forward.Unit

	local spread = weapon.Spread * math.max(0.1, 1 - upgradeValue(d, "Accuracy"))
	if hum.MoveDirection.Magnitude > 0.1 then
		spread *= 1.6 -- firing on the move is less accurate
	end
	local damage = weapon.Damage * (1 + upgradeValue(d, "Damage"))
	local origin = Vector3.new(root.Position.X, Config.ShotHeight, root.Position.Z) + forward * 1.5

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { workspace:FindFirstChild("Militia") :: Instance, workspace:FindFirstChild("Effects") :: Instance }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	params.FilterDescendantsInstances = exclude

	local ends = {}
	-- Pellets that hit the same soldier stack their damage.
	local pending: { [Instance]: number } = {}
	local hitAt: { [Instance]: Vector3 } = {}
	for _ = 1, weapon.Pellets do
		local angle = (math.random() * 2 - 1) * spread
		local dir = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(forward)
		local result = workspace:Raycast(origin, dir * weapon.Range, params)
		if result then
			table.insert(ends, result.Position)
			pending[result.Instance] = (pending[result.Instance] or 0) + damage
			hitAt[result.Instance] = result.Position
		else
			table.insert(ends, origin + dir * weapon.Range)
		end
	end
	for inst, dmg in pending do
		local flesh = Units.ApplyHit(inst, dmg, "Blue", player)
		FX.Hit(hitAt[inst], flesh)
	end
	-- Draw smoke and tracers from the visible muzzle (unless something was
	-- hit closer than that, e.g. when standing against a wall).
	local fxOrigin = origin
	local muzzle = MUZZLE_DISTANCE[d.Equipped] or 0
	local nearest = math.huge
	for _, e in ends do
		nearest = math.min(nearest, (e - origin).Magnitude)
	end
	fxOrigin = origin + forward * math.max(0, math.min(muzzle, nearest - 0.5))
	FX.Shot(fxOrigin, ends, "Blue")

	sync(player)
	if d.Ammo[d.Equipped] <= 0 then
		task.delay(0.15, startReload, player)
	end
end

local function melee(player: Player)
	local d = data[player]
	local root = getRoot(player)
	if not d or not root then
		return
	end
	local t = now()
	if t - d.LastMelee < Config.Melee.Cooldown then
		return
	end
	d.LastMelee = t
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local cosLimit = math.cos(math.rad(Config.Melee.ArcDegrees / 2))
	FX.Slash(root.Position, look)
	for _, unit in table.clone(Units.All()) do
		if unit.Team == "Red" and not unit.Dead then
			local delta = unit.Root.Position - root.Position
			delta = Vector3.new(delta.X, 0, delta.Z)
			local reach = Config.Melee.Range + unit.Root.Size.Z / 2
			if delta.Magnitude <= reach and (delta.Magnitude < 1 or delta.Unit:Dot(look) >= cosLimit) then
				Units.Damage(unit, Config.Melee.Damage * (1 + upgradeValue(d, "Damage")), player)
				FX.Hit(unit.Root.Position, true)
			end
		end
	end
end

local function equip(player: Player, weaponId: string)
	local d = data[player]
	if not d or typeof(weaponId) ~= "string" or not d.Owned[weaponId] or d.Equipped == weaponId then
		return
	end
	cancelReload(player)
	d.Equipped = weaponId
	sync(player)
	PlayerManager.DressCharacter(player)
	if d.Ammo[weaponId] <= 0 then
		startReload(player)
	end
end

local function purchase(player: Player, kind: string, id: string?): (boolean, string)
	local d = data[player]
	if not d then
		return false, "No data"
	end
	if not canShop() then
		return false, "The shop is only open between waves."
	end

	if kind == "Weapon" and typeof(id) == "string" then
		local weapon = Config.Weapons[id]
		if not weapon then
			return false, "Unknown weapon"
		end
		if d.Owned[id] then
			equip(player, id)
			return true, "Equipped " .. weapon.Name
		end
		if d.Money < weapon.Price then
			return false, "Not enough money"
		end
		d.Money -= weapon.Price
		d.Owned[id] = true
		d.Ammo[id] = weapon.Capacity
		equip(player, id)
		sync(player)
		return true, "Bought " .. weapon.Name
	elseif kind == "Upgrade" and typeof(id) == "string" then
		local up = Config.Upgrades[id]
		if not up then
			return false, "Unknown upgrade"
		end
		local level = d.Upgrades[id] or 0
		if level >= up.MaxLevel then
			return false, "Already maxed"
		end
		local cost = up.BaseCost * (level + 1)
		if d.Money < cost then
			return false, "Not enough money"
		end
		d.Money -= cost
		d.Upgrades[id] = level + 1
		PlayerManager.ApplyStats(player, true)
		sync(player)
		return true, up.Name .. " level " .. (level + 1)
	elseif kind == "Ally" then
		if Units.CountOwnedBy(player) >= Config.Allies.MaxPerPlayer then
			return false, "You already lead " .. Config.Allies.MaxPerPlayer .. " minutemen"
		end
		if d.Money < Config.Allies.HireCost then
			return false, "Not enough money"
		end
		d.Money -= Config.Allies.HireCost
		local root = getRoot(player)
		local base = if root then root.Position else Config.Map.PlayerSpawn
		local offset = Vector3.new(math.random(-6, 6), 0, math.random(3, 8))
		Units.Spawn("Militia", base + offset, Vector3.new(0, 0, -1), player)
		sync(player)
		return true, "A minuteman joins you!"
	elseif kind == "Repair" then
		local hp = gameState:GetAttribute("StoresHealth")
		local max = gameState:GetAttribute("StoresMax")
		if hp >= max then
			return false, "The stores are undamaged"
		end
		if d.Money < Config.Stores.RepairCost then
			return false, "Not enough money"
		end
		d.Money -= Config.Stores.RepairCost
		gameState:SetAttribute("StoresHealth", math.min(max, hp + Config.Stores.RepairAmount))
		sync(player)
		return true, "Stores repaired"
	end
	return false, "Unknown purchase"
end

local WOOD = Color3.fromRGB(105, 70, 40)
local STEEL = Color3.fromRGB(150, 150, 155)
local BRASS = Color3.fromRGB(200, 165, 70)

-- Weapon shapes as { size, offset from the grip, color, material }.
-- The grip sits at the origin and the muzzle points along -Z.
type PieceDef = { Vector3 | CFrame | Color3 | Enum.Material }

local function longGun(barrelLength: number, barrelColor: Color3, bayonet: boolean, flared: boolean): { PieceDef }
	local pieces: { PieceDef } = {
		{ Vector3.new(0.4, 0.55, 1.5), CFrame.new(0, -0.1, 0.55), WOOD, Enum.Material.Wood }, -- butt stock
		{ Vector3.new(0.32, 0.36, barrelLength * 0.8), CFrame.new(0, 0, -barrelLength * 0.4), WOOD, Enum.Material.Wood }, -- fore stock
		{ Vector3.new(0.24, 0.24, barrelLength), CFrame.new(0, 0.22, -barrelLength / 2 - 0.1), barrelColor, Enum.Material.Metal }, -- barrel
		{ Vector3.new(0.2, 0.3, 0.35), CFrame.new(0.2, 0.25, -0.1), STEEL, Enum.Material.Metal }, -- lock
	}
	if bayonet then
		table.insert(pieces, { Vector3.new(0.1, 0.1, 1.5), CFrame.new(0, 0.05, -barrelLength - 0.8), STEEL, Enum.Material.Metal })
	end
	if flared then
		table.insert(pieces, { Vector3.new(0.6, 0.6, 0.45), CFrame.new(0, 0.22, -barrelLength - 0.2), barrelColor, Enum.Material.Metal })
	end
	return pieces
end

local function pistol(): { PieceDef }
	return {
		{ Vector3.new(0.3, 0.7, 0.45), CFrame.new(0, -0.25, 0.15) * CFrame.Angles(math.rad(-20), 0, 0), WOOD, Enum.Material.Wood },
		{ Vector3.new(0.22, 0.24, 1.4), CFrame.new(0, 0.1, -0.55), STEEL, Enum.Material.Metal },
	}
end

-- Where each weapon is held, relative to the HumanoidRootPart.
local WEAPON_MODELS: { [string]: { { Grip: CFrame, Pieces: { PieceDef } } } } = {
	Musket = { { Grip = CFrame.new(0.55, 0.9, -1.1), Pieces = longGun(3.8, STEEL, true, false) } },
	LongRifle = { { Grip = CFrame.new(0.55, 0.9, -1.1), Pieces = longGun(4.8, BRASS, false, false) } },
	Blunderbuss = { { Grip = CFrame.new(0.55, 0.9, -1.1), Pieces = longGun(2.6, BRASS, false, true) } },
	Pistols = {
		{ Grip = CFrame.new(1.1, 0.75, -1.3), Pieces = pistol() },
		{ Grip = CFrame.new(-1.1, 0.75, -1.3), Pieces = pistol() },
	},
}

local function propPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Raise both arms forward so the avatar looks like it is holding the gun.
-- The rotation is applied in the torso's space, so it works for R6 and R15.
local function poseArms(char: Model)
	for _, spec in { { "RightShoulder", "Right Shoulder", 10 }, { "LeftShoulder", "Left Shoulder", -35 } } do
		local joint = char:FindFirstChild(spec[1], true) or char:FindFirstChild(spec[2], true)
		if joint and joint:IsA("Motor6D") then
			local original = joint:GetAttribute("OriginalC0")
			if typeof(original) ~= "CFrame" then
				original = joint.C0
				joint:SetAttribute("OriginalC0", original)
			end
			local c0 = original :: CFrame
			local raise = CFrame.Angles(0, math.rad(spec[3] :: number), 0) * CFrame.Angles(math.rad(80), 0, 0)
			joint.C0 = CFrame.new(c0.Position) * raise * c0.Rotation
		end
	end
end

-- Give the avatar a tricorne and the equipped firearm so they look the part.
function PlayerManager.DressCharacter(player: Player)
	local char = player.Character
	local d = data[player]
	if not char or not d then
		return
	end
	for _, name in { "PropWeapon", "PropHat" } do
		local old = char:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")

	if root and root:IsA("BasePart") then
		local weapon = Instance.new("Model")
		weapon.Name = "PropWeapon"
		for _, holder in WEAPON_MODELS[d.Equipped] or WEAPON_MODELS.Musket do
			for i, piece in holder.Pieces do
				local size, offset, color, material = piece[1] :: Vector3, piece[2] :: CFrame, piece[3] :: Color3, piece[4] :: Enum.Material
				local p = propPart("Piece" .. i, size, color, material)
				local c0 = holder.Grip * offset
				p.CFrame = root.CFrame * c0
				-- Welded to the root (never swapped out by avatar loading) so it
				-- always points where the player is aiming.
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = p
				weld.C0 = c0
				weld.Parent = p
				p.Parent = weapon
			end
		end
		weapon.Parent = char
		poseArms(char)
	end

	if head and head:IsA("BasePart") then
		local hat = propPart("PropHat", Vector3.new(1.9, 0.45, 1.9), Color3.fromRGB(25, 25, 25), Enum.Material.Fabric)
		hat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.15, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = hat
		weld.Parent = hat
		hat.Parent = char
	end
end

-- Apply max health / speed from upgrades. `keepHealth` preserves damage taken.
function PlayerManager.ApplyStats(player: Player, keepHealth: boolean?)
	local d = data[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not d or not hum or hum.Health <= 0 then
		return
	end
	local missing = hum.MaxHealth - hum.Health
	hum.MaxHealth = Config.Player.MaxHealth + upgradeValue(d, "Health")
	hum.Health = if keepHealth then math.max(1, hum.MaxHealth - missing) else hum.MaxHealth
	setSpeed(player)
end

function PlayerManager.Spawn(player: Player)
	local d = data[player]
	if not d or not player.Parent or d.Spawning then
		return
	end
	d.Spawning = true
	local ok = pcall(player.LoadCharacter, player)
	d.Spawning = false
	local char = player.Character
	if not ok or not char then
		return
	end
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	-- No passive regeneration: health only comes back between waves.
	local regen = char:FindFirstChild("Health")
	if regen then
		regen:Destroy()
	end
	hum.AutoRotate = false
	hum.JumpPower = 0
	hum.JumpHeight = 0
	local spawn = Config.Map.PlayerSpawn + Vector3.new(math.random(-12, 12), 0, math.random(-4, 4))
	char:PivotTo(CFrame.lookAt(spawn, spawn + Vector3.new(0, 0, -1)))
	root.AssemblyLinearVelocity = Vector3.zero

	d.Reloading = false
	d.ReloadToken += 1
	for id, owned in d.Owned do
		if owned then
			d.Ammo[id] = Config.Weapons[id].Capacity
		end
	end
	player:SetAttribute("ReloadEnd", 0)
	PlayerManager.ApplyStats(player, false)
	PlayerManager.DressCharacter(player)
	sync(player)

	-- Avatar clothing/bodies load in after spawning and can replace the head
	-- and arms, so dress again once the appearance has finished loading.
	if not player:HasAppearanceLoaded() then
		task.spawn(function()
			local loaded = false
			local conn = player.CharacterAppearanceLoaded:Connect(function()
				loaded = true
			end)
			local deadline = os.clock() + 10
			while not loaded and os.clock() < deadline and player.Character == char do
				task.wait(0.2)
			end
			conn:Disconnect()
			if player.Character == char then
				PlayerManager.DressCharacter(player)
			end
		end)
	end
end

function PlayerManager.IsAlive(player: Player): boolean
	return getRoot(player) ~= nil
end

function PlayerManager.HealAll()
	for player in data do
		PlayerManager.ApplyStats(player, false)
	end
end

function PlayerManager.AddMoney(player: Player, amount: number)
	local d = data[player]
	if d then
		d.Money += amount
		sync(player)
	end
end

function PlayerManager.AddKill(player: Player, reward: number)
	local d = data[player]
	if d then
		d.Kills += 1
		d.Money += reward
		sync(player)
	end
end

function PlayerManager.Reset(player: Player)
	local d: Data = {
		Money = Config.Player.StartingMoney,
		Kills = 0,
		Owned = { Musket = true },
		Equipped = "Musket",
		Ammo = { Musket = Config.Weapons.Musket.Capacity },
		ReloadToken = 0,
		Reloading = false,
		Spawning = false,
		LastFire = 0,
		LastMelee = 0,
		Upgrades = {},
	}
	data[player] = d
	sync(player)
end

function PlayerManager.ResetAll()
	for player in data do
		PlayerManager.Reset(player)
	end
end

local function onPlayerAdded(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = stats
	local money = Instance.new("IntValue")
	money.Name = "Dollars"
	money.Parent = stats
	stats.Parent = player

	PlayerManager.Reset(player)
end

function PlayerManager.Init(state: Instance, shopOpen: () -> boolean)
	gameState = state
	canShop = shopOpen

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local fireRemote = remotes:WaitForChild("Fire") :: RemoteEvent
	local reloadRemote = remotes:WaitForChild("Reload") :: RemoteEvent
	local meleeRemote = remotes:WaitForChild("Melee") :: RemoteEvent
	local equipRemote = remotes:WaitForChild("Equip") :: RemoteEvent
	local purchaseRemote = remotes:WaitForChild("Purchase") :: RemoteFunction
	fireRemote.OnServerEvent:Connect(fire)
	reloadRemote.OnServerEvent:Connect(startReload)
	meleeRemote.OnServerEvent:Connect(melee)
	equipRemote.OnServerEvent:Connect(equip)
	purchaseRemote.OnServerInvoke = purchase

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		data[player] = nil
		Units.RemoveOwnedBy(player)
	end)
end

return PlayerManager
