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
	FX.Shot(origin, ends, "Blue")

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

-- Give the avatar a tricorne and a musket so they look the part.
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
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local head = char:FindFirstChild("Head")
	if hand and hand:IsA("BasePart") then
		local length = if d.Equipped == "Pistols" then 1.4 elseif d.Equipped == "Blunderbuss" then 3.2 elseif d.Equipped == "LongRifle" then 5.2 else 4.4
		local weapon = Instance.new("Part")
		weapon.Name = "PropWeapon"
		weapon.Size = Vector3.new(0.25, 0.3, length)
		weapon.Color = Color3.fromRGB(105, 70, 40)
		weapon.Material = Enum.Material.Wood
		weapon.CanCollide = false
		weapon.CanQuery = false
		weapon.CanTouch = false
		weapon.Massless = true
		weapon.CFrame = hand.CFrame * CFrame.new(0, -0.3, -length / 2 + 0.6)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = weapon
		weld.Parent = weapon
		weapon.Parent = char
	end
	if head and head:IsA("BasePart") then
		local hat = Instance.new("Part")
		hat.Name = "PropHat"
		hat.Size = Vector3.new(1.9, 0.45, 1.9)
		hat.Color = Color3.fromRGB(25, 25, 25)
		hat.Material = Enum.Material.Fabric
		hat.CanCollide = false
		hat.CanQuery = false
		hat.CanTouch = false
		hat.Massless = true
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
