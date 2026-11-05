-- Power-up drops (Zombies-style) and the ray gun easter egg behind the church.
--
-- Drops: killed redcoats occasionally leave a glowing token. The first player
-- to touch it triggers it for the whole team. Timed power-ups store their end
-- time on GameState as "PU_<kind>" so the HUD and PlayerManager can read them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FX = require(script.Parent:WaitForChild("FX"))
local Units = require(script.Parent:WaitForChild("Units"))
local PlayerManager = require(script.Parent:WaitForChild("PlayerManager"))

local Powerups = {}

type Drop = { Kind: string, Model: Model, Position: Vector3, Expires: number }

local gameState: Instance
local folder: Folder
local drops: { Drop } = {}
local dropsThisWave = 0
local lastDrop = 0
local suppress = false -- no chain drops from a Powder Keg

local function now(): number
	return workspace:GetServerTimeNow()
end

local function pickKind(): string
	local total = 0
	for _, k in Config.Drops.Kinds do
		total += k.Weight
	end
	local roll = math.random() * total
	for id, k in Config.Drops.Kinds do
		roll -= k.Weight
		if roll <= 0 then
			return id
		end
	end
	return "WarChest"
end

local function buildToken(kind: string, pos: Vector3): Model
	local def = Config.Drops.Kinds[kind]
	local model = Instance.new("Model")
	model.Name = "Drop_" .. kind
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one * 2.2
	core.Color = def.Color
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CFrame = CFrame.new(pos.X, 3, pos.Z)
	core.Parent = model
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 3.6, 3.6)
	ring.Color = def.Color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(pos.X, 3, pos.Z)
	ring.Parent = model
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 14
	light.Brightness = 3
	light.Parent = core

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = def.Color
	label.TextStrokeTransparency = 0
	label.Text = def.Name
	label.Parent = gui
	gui.Parent = core

	model.PrimaryPart = core
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Expires", now() + Config.Drops.Lifetime)
	model.Parent = folder
	return model
end

function Powerups.SpawnDrop(kind: string, pos: Vector3)
	local model = buildToken(kind, pos)
	table.insert(drops, { Kind = kind, Model = model, Position = Vector3.new(pos.X, 0, pos.Z), Expires = now() + Config.Drops.Lifetime })
end

-- Called for every redcoat killed.
function Powerups.OnRedcoatKilled(unit: any)
	if suppress or gameState:GetAttribute("Phase") ~= "Wave" then
		return
	end
	local pos = unit.Root.Position
	if unit.Def.Boss then
		local list = Config.Drops.BossDrops
		Powerups.SpawnDrop(list[math.random(1, #list)], pos)
		return
	end
	local t = now()
	if dropsThisWave >= Config.Drops.MaxPerWave or t - lastDrop < Config.Drops.MinGap then
		return
	end
	if math.random() < Config.Drops.Chance then
		dropsThisWave += 1
		lastDrop = t
		Powerups.SpawnDrop(pickKind(), pos)
	end
end

local function trigger(kind: string, pos: Vector3, by: Player)
	local def = Config.Drops.Kinds[kind]
	FX.Powerup(pos, def.Color)
	FX.Announce(("%s!  %s  (%s)"):format(def.Name:upper(), def.Text, by.DisplayName), def.Color)

	if def.Duration then
		gameState:SetAttribute("PU_" .. kind, now() + def.Duration)
	end

	if kind == "RapidFire" then
		-- Top everyone up straight away.
		for _, p in Players:GetPlayers() do
			PlayerManager.RefillAll(p)
		end
	elseif kind == "Medic" then
		for _, p in Players:GetPlayers() do
			if PlayerManager.IsAlive(p) then
				PlayerManager.ApplyStats(p, false)
			else
				task.spawn(PlayerManager.Spawn, p)
			end
		end
	elseif kind == "Nuke" then
		suppress = true
		FX.Explosion(pos, 14)
		for _, u in table.clone(Units.All()) do
			if u.Team == "Red" and not u.Dead and (u.Root.Position - pos).Magnitude <= (def.Radius or 110) then
				FX.Explosion(u.Root.Position, 4)
				if u.Def.Boss then
					Units.Damage(u, def.BossDamage or 300, by)
				else
					Units.Kill(u, nil)
				end
			end
		end
		suppress = false
		for _, p in Players:GetPlayers() do
			PlayerManager.AddMoney(p, def.Payout or 100)
			PlayerManager.AddScore(p, def.Payout or 100)
		end
	elseif kind == "Rebuild" then
		gameState:SetAttribute("StoresHealth", gameState:GetAttribute("StoresMax"))
	elseif kind == "WarChest" then
		for _, p in Players:GetPlayers() do
			PlayerManager.AddMoney(p, def.Payout or 150)
		end
	end
end

local function step()
	local t = now()
	for i = #drops, 1, -1 do
		local drop = drops[i]
		local taken: Player? = nil
		for _, c in Units.LivingCharacters() do
			local d = Vector3.new(c.Root.Position.X - drop.Position.X, 0, c.Root.Position.Z - drop.Position.Z).Magnitude
			if d <= Config.Drops.PickupRadius then
				taken = c.Player
				break
			end
		end
		if taken then
			table.remove(drops, i)
			drop.Model:Destroy()
			trigger(drop.Kind, drop.Position, taken)
		elseif t >= drop.Expires then
			table.remove(drops, i)
			drop.Model:Destroy()
		end
	end
end

-- New wave: reset the drop budget.
function Powerups.StartWave()
	dropsThisWave = 0
	lastDrop = 0
end

-- New game: remove tokens and timers.
function Powerups.Reset()
	for _, d in drops do
		d.Model:Destroy()
	end
	table.clear(drops)
	for kind in Config.Drops.Kinds do
		gameState:SetAttribute("PU_" .. kind, 0)
	end
end

---------------------------------------------------------------------------
-- Easter egg: a strange contraption hidden behind the church tower. On boss
-- rounds it hums to life and lends the Ray Gun to whoever reaches inside, for
-- that round only.
---------------------------------------------------------------------------

local eggPrompt: ProximityPrompt
local eggGlow: BasePart
local eggLight: PointLight
local claimed: { [Player]: boolean } = {}

local function eggPart(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function buildEgg()
	local base = Config.EasterEgg.Position
	local model = Instance.new("Model")
	model.Name = "OddContraption"
	eggPart({ Name = "Stump", Size = Vector3.new(2.6, 1.6, 2.6), Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(base + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(90, 65, 40), Material = Enum.Material.Wood, CanCollide = true }, model)
	eggPart({ Name = "Housing", Size = Vector3.new(1.6, 1.2, 1.6), CFrame = CFrame.new(base + Vector3.new(0, 2.2, 0)), Color = Color3.fromRGB(150, 110, 60), Material = Enum.Material.Metal }, model)
	eggPart({ Name = "Dial", Size = Vector3.new(0.1, 0.5, 0.5), Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(base + Vector3.new(0.85, 2.2, 0)), Color = Color3.fromRGB(230, 220, 200), Material = Enum.Material.SmoothPlastic }, model)
	eggGlow = eggPart({ Name = "Orb", Size = Vector3.one * 1.1, Shape = Enum.PartType.Ball, CFrame = CFrame.new(base + Vector3.new(0, 3.3, 0)), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Glass, Transparency = 0.2 }, model)
	for _, x in { -0.6, 0.6 } do
		eggPart({ Name = "Coil", Size = Vector3.new(0.15, 1.4, 0.15), CFrame = CFrame.new(base + Vector3.new(x, 3.2, 0)) * CFrame.Angles(0, 0, math.rad(x * 25)), Color = Color3.fromRGB(190, 120, 60), Material = Enum.Material.Metal }, model)
	end
	-- A couple of barrels half-hide it.
	for _, offset in { Vector3.new(2.4, 0, 1.2), Vector3.new(-2.2, 0, 1.6) } do
		eggPart({ Name = "Barrel", Size = Vector3.new(3, 2.2, 2.2), Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(base + offset + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood, CanCollide = true }, model)
	end
	eggLight = Instance.new("PointLight")
	eggLight.Color = Color3.fromRGB(90, 255, 120)
	eggLight.Range = 6
	eggLight.Brightness = 0.4
	eggLight.Parent = eggGlow

	eggPrompt = Instance.new("ProximityPrompt")
	eggPrompt.ActionText = Config.EasterEgg.PromptText
	eggPrompt.ObjectText = Config.EasterEgg.ObjectText
	eggPrompt.HoldDuration = 1
	eggPrompt.MaxActivationDistance = 8
	eggPrompt.RequiresLineOfSight = false
	eggPrompt.GamepadKeyCode = Enum.KeyCode.ButtonB -- X is reload on controllers
	eggPrompt.Enabled = false
	eggPrompt.Parent = eggGlow
	eggPrompt.Triggered:Connect(function(player)
		if not eggPrompt.Enabled or claimed[player] then
			return
		end
		if PlayerManager.GiveRayGun(player) then
			claimed[player] = true
			FX.Powerup(eggGlow.Position, Color3.fromRGB(90, 255, 120))
			FX.Announce("You found the RAY GUN! It fades when this battle ends.", Color3.fromRGB(90, 255, 120), player)
			for _, other in Players:GetPlayers() do
				if other ~= player then
					FX.Announce(("%s found something strange behind the church..."):format(player.DisplayName), Color3.fromRGB(90, 255, 120), other)
				end
			end
		end
	end)

	local map = workspace:WaitForChild("Map")
	model.Parent = map:WaitForChild("Decor")
end

-- Boss rounds wake the contraption; everything else puts it to sleep.
function Powerups.SetBossRound(active: boolean)
	table.clear(claimed)
	eggPrompt.Enabled = active
	eggGlow.Material = if active then Enum.Material.Neon else Enum.Material.Glass
	eggGlow.Color = if active then Color3.fromRGB(90, 255, 120) else Color3.fromRGB(60, 120, 70)
	eggLight.Brightness = if active then 3 else 0.4
	eggLight.Range = if active then 14 else 6
	if not active then
		PlayerManager.TakeRayGuns()
	end
end

function Powerups.Init(state: Instance)
	gameState = state
	folder = Instance.new("Folder")
	folder.Name = "Drops"
	folder.Parent = workspace
	for kind in Config.Drops.Kinds do
		gameState:SetAttribute("PU_" .. kind, 0)
	end
	buildEgg()
	RunService.Heartbeat:Connect(step)
end

return Powerups
