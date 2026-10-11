-- Redcoats and hired militia: model construction, AI, and damage handling.
--
-- Units are anchored models moved by CFrame every frame. That keeps dozens of
-- soldiers cheap and lets line infantry hold tidy formations. Each unit's
-- invisible Root part is its hitbox; all visual parts are welded to it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local FX = require(script.Parent:WaitForChild("FX"))

local Units = {}

export type Target = {
	Kind: string, -- "Player" | "Unit" | "Stores"
	Position: Vector3,
	Player: Player?,
	Humanoid: Humanoid?,
	Unit: any?,
	Distance: number,
}

export type Unit = {
	Kind: string,
	Def: Config.UnitDef,
	Team: string,
	Model: Model,
	Root: BasePart,
	Health: number,
	MaxHealth: number,
	Dead: boolean,
	Group: any?,
	SlotOffset: Vector3?,
	NextAttack: number,
	Aiming: boolean,
	AimEnd: number,
	AimDir: Vector3,
	AimPoint: Vector3,
	AimTarget: Target?,
	Owner: Player?,
	ArmWelds: { Weld },
	WeaponWeld: Weld?,
	Poses: { [string]: { CFrame } },
	Bar: Frame?,
	BarGui: BillboardGui?,
	Alert: TextLabel?,
	Facing: Vector3,
}

local units: { Unit } = {}
local byModel: { [Model]: Unit } = {}
local groups: { any } = {}

local redFolder: Folder
local blueFolder: Folder
local coverFolder: Instance
local storesModel: Model
local gameState: Instance

local coverParams = RaycastParams.new()
coverParams.FilterType = Enum.RaycastFilterType.Include

Units.OnKill = nil :: ((killer: Player?, unit: Unit) -> ())?
Units.OnStoresDestroyed = nil :: (() -> ())?

-- Roundshot flies far enough to reach the village from the gun line.
local CANNON_RANGE = 420

local SKIN = Color3.fromRGB(234, 192, 160)
local WHITE = Color3.fromRGB(235, 232, 220)
local BLACK = Color3.fromRGB(25, 25, 25)
local WOOD = Color3.fromRGB(105, 70, 40)
local STEEL = Color3.fromRGB(120, 120, 125)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = flat(v)
	if f.Magnitude < 1e-3 then
		return fallback
	end
	return f.Unit
end

local function rotateY(v: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(v)
end

local function clampToMap(p: Vector3): Vector3
	local m = Config.Map
	return Vector3.new(
		math.clamp(p.X, -m.HalfWidth + 3, m.HalfWidth - 3),
		p.Y,
		math.clamp(p.Z, m.NorthEdge + 3, m.SouthEdge - 3)
	)
end

local function storesPosition(): Vector3
	return Config.Map.StoresPosition
end

local function storesHealth(): number
	return gameState:GetAttribute("StoresHealth") or 0
end

---------------------------------------------------------------------------
-- Model construction
---------------------------------------------------------------------------

local function addPart(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

-- A part attached with a classic Weld so its pose can be changed (arms, musket).
local function addPosable(model: Model, root: BasePart, name: string, size: Vector3, c0: CFrame, color: Color3, material: Enum.Material?): (Part, Weld)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * c0
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = p
	weld.C0 = c0
	weld.Parent = p
	p.Parent = model
	return p, weld
end

local function addHat(model: Model, root: BasePart, hat: string, headY: number, def: Config.UnitDef)
	if hat == "Tricorne" then
		addPart(model, root, "Hat", Vector3.new(1.8, 0.35, 1.8), CFrame.new(0, headY + 0.65, 0), BLACK, Enum.Material.Fabric)
		addPart(model, root, "HatCrown", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, headY + 0.9, 0), BLACK, Enum.Material.Fabric)
		if def.Team == "Red" then
			addPart(model, root, "HatTrim", Vector3.new(1.85, 0.12, 1.85), CFrame.new(0, headY + 0.55, 0), WHITE)
		end
	elseif hat == "Bearskin" then
		addPart(model, root, "Bearskin", Vector3.new(1.3, 2.0, 1.3), CFrame.new(0, headY + 1.3, 0), BLACK, Enum.Material.Fabric)
		addPart(model, root, "Plate", Vector3.new(0.9, 0.9, 0.1), CFrame.new(0, headY + 0.9, -0.66), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	elseif hat == "Helmet" then
		addPart(model, root, "Helmet", Vector3.new(1.25, 0.8, 1.35), CFrame.new(0, headY + 0.7, 0), BLACK, Enum.Material.Metal)
		addPart(model, root, "Plume", Vector3.new(0.35, 0.6, 1.2), CFrame.new(0, headY + 1.25, 0.1), def.CoatColor, Enum.Material.Fabric)
	elseif hat == "Cap" then
		addPart(model, root, "Cap", Vector3.new(1.2, 0.7, 1.2), CFrame.new(0, headY + 0.75, 0), BLACK, Enum.Material.Fabric)
	end
end

local function makeHealthBar(root: BasePart, height: number): (BillboardGui, Frame, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Overhead"
	gui.Size = UDim2.fromOffset(46, 34)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.LightInfluence = 0

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, 0)
	back.Size = UDim2.new(1, 0, 0, 6)
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(220, 60, 50)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local alert = Instance.new("TextLabel")
	alert.Name = "Alert"
	alert.BackgroundTransparency = 1
	alert.Size = UDim2.new(3, 0, 0, 24)
	alert.Position = UDim2.new(-1, 0, 0, 0)
	alert.Font = Enum.Font.GothamBlack
	alert.TextColor3 = Color3.fromRGB(255, 220, 80)
	alert.TextStrokeTransparency = 0.2
	alert.TextScaled = true
	alert.Text = ""
	alert.Parent = gui

	gui.Parent = root
	return gui, fill, alert
end

local function buildSoldier(kind: string, def: Config.UnitDef, cf: CFrame): Unit
	local s = def.Scale or 1
	local model = Instance.new("Model")
	model.Name = def.DisplayName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2.2, 5, 1.4) * s
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	root.CFrame = CFrame.new(cf.Position.X, 2.5 * s, cf.Position.Z) * cf.Rotation
	root.Parent = model
	model.PrimaryPart = root

	local coat = def.CoatColor
	local breeches = if def.Team == "Red" then WHITE else Color3.fromRGB(170, 150, 110)

	-- Legs and boots.
	for _, x in { -0.5, 0.5 } do
		addPart(model, root, "Leg", Vector3.new(0.85, 1.6, 0.85) * s, CFrame.new(x * s, -1.0 * s, 0), breeches)
		addPart(model, root, "Boot", Vector3.new(0.9, 0.9, 1.0) * s, CFrame.new(x * s, -2.05 * s, -0.05 * s), BLACK)
	end
	-- Body.
	addPart(model, root, "Torso", Vector3.new(2, 2, 1) * s, CFrame.new(0, 0.8 * s, 0), coat, Enum.Material.Fabric)
	addPart(model, root, "Tails", Vector3.new(2.05, 0.8, 1.05) * s, CFrame.new(0, -0.5 * s, 0.05 * s), coat, Enum.Material.Fabric)
	local beltColor = if def.Team == "Red" then WHITE else Color3.fromRGB(190, 170, 130)
	for _, a in { 38, -38 } do
		addPart(model, root, "Crossbelt", Vector3.new(0.3, 2.5, 0.08) * s, CFrame.new(0, 0.8 * s, -0.53 * s) * CFrame.Angles(0, 0, math.rad(a)), beltColor)
	end
	-- Head.
	local headY = 2.35 * s
	addPart(model, root, "Head", Vector3.new(1.1, 1.1, 1.1) * s, CFrame.new(0, headY, 0), SKIN)
	addHat(model, root, def.Hat, headY, def)

	-- Arms and weapon are posable.
	local poses = {
		Idle = {
			CFrame.new(-1.45 * s, 0.75 * s, 0),
			CFrame.new(1.45 * s, 0.75 * s, 0),
			CFrame.new(1.6 * s, 1.1 * s, -0.5 * s) * CFrame.Angles(math.rad(82), 0, 0),
		},
		Aim = {
			CFrame.new(-0.9 * s, 1.35 * s, -1.1 * s) * CFrame.Angles(math.rad(90), 0, math.rad(-20)),
			CFrame.new(0.9 * s, 1.35 * s, -0.9 * s) * CFrame.Angles(math.rad(90), 0, 0),
			CFrame.new(0.55 * s, 1.55 * s, -1.9 * s),
		},
	}
	local _, leftWeld = addPosable(model, root, "LeftArm", Vector3.new(0.75, 2, 0.75) * s, poses.Idle[1], coat, Enum.Material.Fabric)
	local _, rightWeld = addPosable(model, root, "RightArm", Vector3.new(0.75, 2, 0.75) * s, poses.Idle[2], coat, Enum.Material.Fabric)

	local weaponWeld: Weld? = nil
	if def.Attack == "Musket" then
		local musket, w = addPosable(model, root, "Musket", Vector3.new(0.28, 0.32, 4.6) * s, poses.Idle[3], WOOD, Enum.Material.Wood)
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = Vector3.new(0.18, 0.18, 2.2) * s
		barrel.Color = STEEL
		barrel.Material = Enum.Material.Metal
		barrel.CanCollide = false
		barrel.CanQuery = false
		barrel.Massless = true
		barrel.CFrame = musket.CFrame * CFrame.new(0, 0.2 * s, -1.6 * s)
		local bw = Instance.new("WeldConstraint")
		bw.Part0 = musket
		bw.Part1 = barrel
		bw.Parent = barrel
		barrel.Parent = model
		weaponWeld = w
	elseif def.Attack == "Grenade" then
		addPart(model, root, "GrenadePouch", Vector3.new(0.7, 0.7, 0.7) * s, CFrame.new(-1.1 * s, -0.3 * s, 0.3 * s), BLACK)
	end

	local gui, fill, alert = makeHealthBar(root, 4.5 * s)

	return {
		Kind = kind,
		Def = def,
		Team = def.Team,
		Model = model,
		Root = root,
		Health = def.Health,
		MaxHealth = def.Health,
		Dead = false,
		NextAttack = 0,
		Aiming = false,
		AimEnd = 0,
		AimDir = root.CFrame.LookVector,
		AimPoint = root.Position,
		Owner = nil,
		ArmWelds = { leftWeld, rightWeld },
		WeaponWeld = weaponWeld,
		Poses = poses,
		Bar = fill,
		BarGui = gui,
		Alert = alert,
		Facing = root.CFrame.LookVector,
	}
end

local function buildDragoon(kind: string, def: Config.UnitDef, cf: CFrame): Unit
	local model = Instance.new("Model")
	model.Name = def.DisplayName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(3, 6.5, 6.5)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = true
	root.CanTouch = false
	root.CFrame = CFrame.new(cf.Position.X, 3.25, cf.Position.Z) * cf.Rotation
	root.Parent = model
	model.PrimaryPart = root

	local horse = Color3.fromRGB(85, 55, 35)
	addPart(model, root, "Body", Vector3.new(2.4, 2.4, 5), CFrame.new(0, -0.1, 0.2), horse)
	for _, x in { -0.8, 0.8 } do
		for _, z in { -1.8, 2.0 } do
			addPart(model, root, "HorseLeg", Vector3.new(0.6, 2.2, 0.6), CFrame.new(x, -2.2, z), horse)
		end
	end
	addPart(model, root, "Neck", Vector3.new(1, 2.4, 1.1), CFrame.new(0, 1.0, -2.5) * CFrame.Angles(math.rad(-30), 0, 0), horse)
	addPart(model, root, "HorseHead", Vector3.new(1, 1, 2.1), CFrame.new(0, 2.0, -3.2) * CFrame.Angles(math.rad(20), 0, 0), horse)
	addPart(model, root, "Tail", Vector3.new(0.4, 1.8, 0.4), CFrame.new(0, -0.3, 2.9) * CFrame.Angles(math.rad(25), 0, 0), BLACK)
	addPart(model, root, "Saddle", Vector3.new(2.5, 0.3, 1.6), CFrame.new(0, 1.15, 0.3), Color3.fromRGB(60, 40, 30))

	-- Rider.
	addPart(model, root, "Torso", Vector3.new(1.8, 1.8, 1), CFrame.new(0, 2.2, 0.3), def.CoatColor, Enum.Material.Fabric)
	for _, x in { -1.3, 1.3 } do
		addPart(model, root, "RiderLeg", Vector3.new(0.6, 1.8, 0.7), CFrame.new(x, 0.9, 0.0), WHITE)
	end
	addPart(model, root, "Head", Vector3.new(1, 1, 1), CFrame.new(0, 3.6, 0.3), SKIN)
	addHat(model, root, def.Hat, 3.6, def)

	local poses = {
		Idle = {
			CFrame.new(-1.25, 2.2, 0.3),
			CFrame.new(1.25, 2.4, -0.2) * CFrame.Angles(math.rad(40), 0, 0),
			CFrame.new(1.35, 3.6, -0.5) * CFrame.Angles(math.rad(70), 0, 0),
		},
		Aim = {
			CFrame.new(-1.25, 2.2, 0.3),
			CFrame.new(1.4, 2.6, -0.9) * CFrame.Angles(math.rad(100), 0, 0),
			CFrame.new(1.5, 2.5, -2.8) * CFrame.Angles(math.rad(-10), 0, 0),
		},
	}
	local _, leftWeld = addPosable(model, root, "LeftArm", Vector3.new(0.6, 1.8, 0.6), poses.Idle[1], def.CoatColor, Enum.Material.Fabric)
	local _, rightWeld = addPosable(model, root, "RightArm", Vector3.new(0.6, 1.8, 0.6), poses.Idle[2], def.CoatColor, Enum.Material.Fabric)
	local _, sabreWeld = addPosable(model, root, "Sabre", Vector3.new(0.12, 0.35, 3.4), poses.Idle[3], Color3.fromRGB(210, 210, 215), Enum.Material.Metal)

	local gui, fill, alert = makeHealthBar(root, 5.5)

	return {
		Kind = kind,
		Def = def,
		Team = def.Team,
		Model = model,
		Root = root,
		Health = def.Health,
		MaxHealth = def.Health,
		Dead = false,
		NextAttack = 0,
		Aiming = false,
		AimEnd = 0,
		AimDir = root.CFrame.LookVector,
		AimPoint = root.Position,
		Owner = nil,
		ArmWelds = { leftWeld, rightWeld },
		WeaponWeld = sabreWeld,
		Poses = poses,
		Bar = fill,
		BarGui = gui,
		Alert = alert,
		Facing = root.CFrame.LookVector,
	}
end

local function buildCannon(kind: string, def: Config.UnitDef, cf: CFrame): Unit
	local model = Instance.new("Model")
	model.Name = def.DisplayName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(4.5, 4, 7)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = true
	root.CanTouch = false
	root.CFrame = CFrame.new(cf.Position.X, 2, cf.Position.Z) * cf.Rotation
	root.Parent = model
	model.PrimaryPart = root

	addPart(model, root, "Carriage", Vector3.new(1.8, 1, 5.5), CFrame.new(0, -0.6, 0.6) * CFrame.Angles(math.rad(-6), 0, 0), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
	addPart(model, root, "Trail", Vector3.new(1.2, 0.6, 2.5), CFrame.new(0, -1.5, 3.2), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
	for _, x in { -1.5, 1.5 } do
		addPart(model, root, "Wheel", Vector3.new(0.45, 3.4, 3.4), CFrame.new(x, -0.3, 0), Color3.fromRGB(70, 50, 35), Enum.Material.Wood, Enum.PartType.Cylinder)
	end
	addPart(model, root, "Barrel", Vector3.new(6.5, 1.2, 1.2), CFrame.new(0, 0.6, -1.4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(160, 120, 60), Enum.Material.Metal, Enum.PartType.Cylinder)

	-- A gunner standing behind the piece.
	addPart(model, root, "GunnerTorso", Vector3.new(1.6, 1.8, 0.9), CFrame.new(1.8, 0.4, 2.6), Color3.fromRGB(30, 40, 90), Enum.Material.Fabric)
	addPart(model, root, "GunnerHead", Vector3.new(1, 1, 1), CFrame.new(1.8, 1.8, 2.6), SKIN)
	addPart(model, root, "GunnerHat", Vector3.new(1.6, 0.35, 1.6), CFrame.new(1.8, 2.45, 2.6), BLACK)
	addPart(model, root, "GunnerLegs", Vector3.new(1.4, 1.6, 0.8), CFrame.new(1.8, -1.2, 2.6), WHITE)

	local gui, fill, alert = makeHealthBar(root, 4.5)

	return {
		Kind = kind,
		Def = def,
		Team = def.Team,
		Model = model,
		Root = root,
		Health = def.Health,
		MaxHealth = def.Health,
		Dead = false,
		NextAttack = 0,
		Aiming = false,
		AimEnd = 0,
		AimDir = root.CFrame.LookVector,
		AimPoint = root.Position,
		Owner = nil,
		ArmWelds = {},
		WeaponWeld = nil,
		Poses = { Idle = {}, Aim = {} },
		Bar = fill,
		BarGui = gui,
		Alert = alert,
		Facing = root.CFrame.LookVector,
	}
end

local function setPose(unit: Unit, pose: string)
	local p = unit.Poses[pose]
	if not p or #p == 0 then
		return
	end
	if unit.ArmWelds[1] then
		unit.ArmWelds[1].C0 = p[1]
	end
	if unit.ArmWelds[2] then
		unit.ArmWelds[2].C0 = p[2]
	end
	if unit.WeaponWeld and p[3] then
		unit.WeaponWeld.C0 = p[3]
	end
end

local function shout(unit: Unit, text: string, duration: number?)
	local alert = unit.Alert
	if not alert then
		return
	end
	alert.Text = text
	local stamp = now()
	alert:SetAttribute("Stamp", stamp)
	if duration then
		task.delay(duration, function()
			if alert.Parent and alert:GetAttribute("Stamp") == stamp then
				alert.Text = ""
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

function Units.Spawn(kind: string, position: Vector3, facing: Vector3, owner: Player?): Unit
	local def = Config.Units[kind]
	assert(def, "Unknown unit kind " .. tostring(kind))
	local cf = CFrame.lookAt(flat(position), flat(position) + flatUnit(facing, Vector3.new(0, 0, 1)))

	local unit: Unit
	if def.Attack == "Sabre" then
		unit = buildDragoon(kind, def, cf)
	elseif def.Attack == "Cannon" then
		unit = buildCannon(kind, def, cf)
	else
		unit = buildSoldier(kind, def, cf)
	end

	unit.Owner = owner
	-- Stagger first shots so a fresh wave doesn't fire in perfect unison.
	unit.NextAttack = now() + 1 + math.random() * 2
	unit.Model:SetAttribute("Team", def.Team)
	unit.Model:SetAttribute("Kind", kind)
	if owner then
		unit.Model:SetAttribute("Owner", owner.UserId)
	end
	if def.Team == "Blue" then
		unit.Bar.BackgroundColor3 = Color3.fromRGB(80, 140, 230)
		unit.Bar.Parent.Visible = true
	end
	unit.Model.Parent = if def.Team == "Red" then redFolder else blueFolder

	table.insert(units, unit)
	byModel[unit.Model] = unit
	return unit
end

-- Line infantry march as a formation and fire volleys on the officer's word.
function Units.SpawnFormation(spec: { Ranks: number, Files: number, Officer: boolean }, center: Vector3, facing: Vector3)
	local group = {
		Center = flat(center),
		Facing = facing.Unit,
		Members = {},
		State = "March",
		NextVolley = now() + 3,
		Officer = nil :: Unit?,
		HoldSince = 0,
	}
	local spacing = 3.2
	local frame = CFrame.lookAt(group.Center, group.Center + group.Facing)
	for rank = 1, spec.Ranks do
		for file = 1, spec.Files do
			local offset = Vector3.new((file - (spec.Files + 1) / 2) * spacing, 0, (rank - 1) * 3.6)
			local unit = Units.Spawn("Regular", frame:PointToWorldSpace(offset), facing)
			unit.Group = group
			unit.SlotOffset = offset
			table.insert(group.Members, unit)
		end
	end
	if spec.Officer then
		local offset = Vector3.new(0, 0, spec.Ranks * 3.6 + 2)
		local officer = Units.Spawn("Officer", frame:PointToWorldSpace(offset), facing)
		officer.Group = group
		officer.SlotOffset = offset
		group.Officer = officer
		table.insert(group.Members, officer)
	end
	table.insert(groups, group)
	return group
end

---------------------------------------------------------------------------
-- Targeting
---------------------------------------------------------------------------

local function livingCharacters(): { { Player: Player, Root: BasePart, Humanoid: Humanoid } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				table.insert(list, { Player = player, Root = root, Humanoid = hum })
			end
		end
	end
	return list
end
Units.LivingCharacters = livingCharacters

local function storesTarget(from: Vector3): Target?
	if storesHealth() <= 0 then
		return nil
	end
	local pos = storesPosition()
	return {
		Kind = "Stores",
		Position = Vector3.new(pos.X, Config.ShotHeight, pos.Z),
		Distance = math.max(0, (flat(pos) - flat(from)).Magnitude - 9),
	}
end

-- Nearest enemy of `team` (players, militia, or redcoats) within maxDist.
local function nearestHostile(team: string, from: Vector3, maxDist: number, playersOnly: boolean?): Target?
	local best: Target? = nil
	local bestDist = maxDist
	if team == "Red" then
		for _, c in livingCharacters() do
			local d = (flat(c.Root.Position) - flat(from)).Magnitude
			if d < bestDist then
				bestDist = d
				best = { Kind = "Player", Position = c.Root.Position, Player = c.Player, Humanoid = c.Humanoid, Distance = d }
			end
		end
	end
	if not playersOnly then
		for _, u in units do
			if not u.Dead and u.Team ~= team then
				local d = (flat(u.Root.Position) - flat(from)).Magnitude
				if d < bestDist then
					bestDist = d
					best = { Kind = "Unit", Position = u.Root.Position, Unit = u, Distance = d }
				end
			end
		end
	end
	return best
end

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local origin = Vector3.new(from.X, Config.ShotHeight, from.Z)
	local delta = Vector3.new(to.X, Config.ShotHeight, to.Z) - origin
	if delta.Magnitude < 1 then
		return true
	end
	return workspace:Raycast(origin, delta, coverParams) == nil
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------

local function updateBar(unit: Unit)
	if unit.Bar then
		unit.Bar.Size = UDim2.fromScale(math.clamp(unit.Health / unit.MaxHealth, 0, 1), 1)
		;(unit.Bar.Parent :: Frame).Visible = true
	end
end

local function removeFromGroup(unit: Unit)
	local group = unit.Group
	if not group then
		return
	end
	local idx = table.find(group.Members, unit)
	if idx then
		table.remove(group.Members, idx)
	end
	if group.Officer == unit then
		group.Officer = nil
	end
end

function Units.Kill(unit: Unit, killer: Player?)
	if unit.Dead then
		return
	end
	unit.Dead = true
	unit.Health = 0
	byModel[unit.Model] = nil
	local idx = table.find(units, unit)
	if idx then
		table.remove(units, idx)
	end
	removeFromGroup(unit)

	if unit.BarGui then
		unit.BarGui:Destroy()
	end
	-- Topple over and fade.
	local root = unit.Root
	root.CanCollide = false
	root.CanQuery = false
	if unit.Def.Attack ~= "Cannon" then
		local fallDir = if math.random() < 0.5 then 1 else -1
		root.CFrame = root.CFrame * CFrame.new(0, -root.Size.Y / 2 + 0.6, 0) * CFrame.Angles(math.rad(85) * fallDir, 0, 0) * CFrame.new(0, root.Size.Y / 2 - 0.6, 0)
	end
	for _, d in unit.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	unit.Model:SetAttribute("Dead", true)
	Debris:AddItem(unit.Model, 6)

	if Units.OnKill then
		Units.OnKill(killer, unit)
	end
end

function Units.Damage(unit: Unit, amount: number, attacker: Player?)
	if unit.Dead then
		return
	end
	unit.Health -= amount
	updateBar(unit)
	if unit.Health <= 0 then
		Units.Kill(unit, attacker)
	end
end

function Units.DamageStores(amount: number)
	local hp = storesHealth()
	if hp <= 0 then
		return
	end
	hp = math.max(0, hp - amount)
	gameState:SetAttribute("StoresHealth", hp)
	if hp <= 0 and Units.OnStoresDestroyed then
		Units.OnStoresDestroyed()
	end
end

-- Resolve a raycast hit into damage. Returns true if something living was hit.
function Units.ApplyHit(inst: Instance, damage: number, attackerTeam: string, attacker: Player?): boolean
	local model = inst:FindFirstAncestorOfClass("Model")
	if not model then
		return false
	end
	local unit = byModel[model]
	if unit then
		if unit.Team ~= attackerTeam then
			Units.Damage(unit, damage, attacker)
		end
		return true
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and attackerTeam == "Red" then
			hum:TakeDamage(damage)
		end
		return true
	end
	if model == storesModel then
		if attackerTeam == "Red" then
			Units.DamageStores(damage)
		end
		return false
	end
	return false
end

-- Damage everything hostile to `attackerTeam` within radius of pos.
function Units.AreaDamage(pos: Vector3, radius: number, damage: number, attackerTeam: string, storesMultiplier: number?)
	if attackerTeam == "Red" then
		for _, c in livingCharacters() do
			local d = (c.Root.Position - pos).Magnitude
			if d <= radius then
				c.Humanoid:TakeDamage(damage * (1 - 0.5 * d / radius))
			end
		end
		local sp = storesPosition()
		if (flat(sp) - flat(pos)).Magnitude <= radius + 8 then
			Units.DamageStores(damage * (storesMultiplier or 1))
		end
	end
	for i = #units, 1, -1 do
		local u = units[i]
		if u and not u.Dead and u.Team ~= attackerTeam then
			local d = (u.Root.Position - pos).Magnitude
			if d <= radius then
				Units.Damage(u, damage * (1 - 0.5 * d / radius), nil)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Attacks
---------------------------------------------------------------------------

local function shotParamsFor(team: string): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { workspace:FindFirstChild("Effects") :: Instance }
	if team == "Red" then
		table.insert(exclude, redFolder)
	else
		table.insert(exclude, blueFolder)
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(exclude, p.Character)
			end
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

local function fireMusket(unit: Unit)
	local def = unit.Def
	local dir = rotateY(unit.AimDir, (math.random() * 2 - 1) * def.Spread)
	local origin = Vector3.new(unit.Root.Position.X, Config.ShotHeight, unit.Root.Position.Z) + dir * 2
	local range = def.Range * 1.2
	local result = workspace:Raycast(origin, dir * range, shotParamsFor(unit.Team))
	local hitPos = origin + dir * range
	if result then
		hitPos = result.Position
		local flesh = Units.ApplyHit(result.Instance, def.Damage, unit.Team, unit.Owner)
		FX.Hit(hitPos, flesh)
	end
	FX.Shot(origin, { hitPos }, unit.Team)
end

local function throwGrenade(unit: Unit)
	local def = unit.Def
	local from = unit.Root.Position + Vector3.new(0, 2, 0)
	local scatter = rotateY(Vector3.new(0, 0, 1), math.random() * 360) * math.random() * 4
	local to = Vector3.new(unit.AimPoint.X, 0.5, unit.AimPoint.Z) + scatter
	local flightTime = 1.1
	FX.Grenade(from, to, flightTime)
	task.delay(flightTime, function()
		FX.Explosion(to, 11)
		Units.AreaDamage(to, 11, def.Damage, "Red", 2)
	end)
end

local function sabreStrike(unit: Unit, target: Target)
	local def = unit.Def
	if target.Distance > def.Range + 2.5 then
		return
	end
	FX.Slash(unit.Root.Position, unit.Facing)
	if target.Kind == "Player" and target.Humanoid then
		target.Humanoid:TakeDamage(def.Damage)
	elseif target.Kind == "Unit" and target.Unit then
		Units.Damage(target.Unit, def.Damage, nil)
	elseif target.Kind == "Stores" then
		Units.DamageStores(def.Damage)
	end
end

local function fireCannon(unit: Unit)
	local def = unit.Def
	local dir = unit.AimDir
	local origin = Vector3.new(unit.Root.Position.X, Config.ShotHeight, unit.Root.Position.Z) + dir * 5
	local range = CANNON_RANGE
	local speed = 160
	local to = origin + dir * range
	FX.Cannonball(origin, to, range / speed)
	FX.Explosion(origin, 3)

	task.spawn(function()
		local hitPlayers: { [Player]: boolean } = {}
		local hitUnits: { [any]: boolean } = {}
		local hitStores = false
		local traveled = 0
		local radius = 3.5
		while traveled < range do
			local dt = task.wait()
			traveled += speed * dt
			local pos = origin + dir * math.min(traveled, range)
			for _, c in livingCharacters() do
				if not hitPlayers[c.Player] and (flat(c.Root.Position) - flat(pos)).Magnitude <= radius then
					hitPlayers[c.Player] = true
					c.Humanoid:TakeDamage(def.Damage)
					FX.Hit(c.Root.Position, true)
				end
			end
			for _, u in units do
				if not u.Dead and u.Team ~= "Red" and not hitUnits[u] and (flat(u.Root.Position) - flat(pos)).Magnitude <= radius then
					hitUnits[u] = true
					Units.Damage(u, def.Damage, nil)
				end
			end
			if not hitStores and (flat(storesPosition()) - flat(pos)).Magnitude <= 9 then
				hitStores = true
				Units.DamageStores(def.Damage * 1.5)
				FX.Explosion(pos, 6)
				break
			end
		end
	end)
end

local function beginAim(unit: Unit, target: Target, aimTime: number)
	unit.Aiming = true
	unit.AimTarget = target
	unit.AimPoint = target.Position
	unit.AimDir = flatUnit(target.Position - unit.Root.Position, unit.Facing)
	unit.AimEnd = now() + aimTime
	unit.Facing = unit.AimDir
	setPose(unit, "Aim")
	if unit.Def.Attack == "Cannon" then
		local origin = Vector3.new(unit.Root.Position.X, 0.3, unit.Root.Position.Z)
		FX.CannonWarn(origin, origin + unit.AimDir * CANNON_RANGE, aimTime)
	elseif unit.Def.Attack == "Grenade" then
		FX.Marker(Vector3.new(target.Position.X, 0.3, target.Position.Z), 11, aimTime + 1.1)
	end
	if unit.Team == "Red" and unit.Group == nil then
		shout(unit, "!", aimTime)
	end
end

local function officerAura(pos: Vector3): number
	for _, u in units do
		if u.Kind == "Officer" and not u.Dead and (u.Root.Position - pos).Magnitude <= Config.OfficerAura.Radius then
			return Config.OfficerAura.ReloadMultiplier
		end
	end
	return 1
end

local function executeAttack(unit: Unit)
	unit.Aiming = false
	local def = unit.Def
	local attack = def.Attack
	if attack == "Musket" then
		fireMusket(unit)
	elseif attack == "Grenade" then
		throwGrenade(unit)
	elseif attack == "Cannon" then
		fireCannon(unit)
	end
	local reload = def.Reload
	if unit.Team == "Red" then
		reload *= officerAura(unit.Root.Position)
	end
	unit.NextAttack = now() + reload * (0.9 + math.random() * 0.2)
	setPose(unit, "Idle")
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

-- Pick a direction near `desired` that isn't blocked by cover.
local function steer(pos: Vector3, desired: Vector3): Vector3
	local origin = Vector3.new(pos.X, Config.ShotHeight, pos.Z)
	for _, angle in { 0, 35, -35, 70, -70, 110, -110 } do
		local dir = if angle == 0 then desired else rotateY(desired, angle)
		if not workspace:Raycast(origin, dir * 5, coverParams) then
			return dir
		end
	end
	return -desired
end

local function separation(unit: Unit): Vector3
	local push = Vector3.zero
	local pos = unit.Root.Position
	for _, other in units do
		if other ~= unit and not other.Dead then
			local delta = flat(pos - other.Root.Position)
			local d = delta.Magnitude
			if d > 0.01 and d < 2.6 then
				push += delta.Unit * (2.6 - d)
			end
		end
	end
	return push
end

local function moveUnit(unit: Unit, desired: Vector3, speed: number, dt: number)
	local pos = unit.Root.Position
	local dir = steer(pos, desired)
	local step = dir * speed * dt + separation(unit) * dt * 4
	local newPos = clampToMap(pos + step)
	newPos = Vector3.new(newPos.X, pos.Y, newPos.Z)
	if not unit.Aiming then
		-- Turn smoothly toward the direction of travel.
		unit.Facing = flatUnit(unit.Facing:Lerp(dir, math.min(1, dt * 6)), dir)
	end
	unit.Root.CFrame = CFrame.lookAt(newPos, newPos + unit.Facing)
end

local function faceTowards(unit: Unit, dir: Vector3, dt: number)
	local pos = unit.Root.Position
	unit.Facing = flatUnit(unit.Facing:Lerp(dir, math.min(1, dt * 8)), dir)
	unit.Root.CFrame = CFrame.lookAt(pos, pos + unit.Facing)
end

---------------------------------------------------------------------------
-- AI
---------------------------------------------------------------------------

local function redTarget(from: Vector3, aggro: number): Target?
	return nearestHostile("Red", from, aggro) or storesTarget(from)
end

local function updateGroup(group: any, dt: number)
	local members = group.Members
	if #members == 0 then
		return
	end
	local line = Config.Units.Regular
	local target = redTarget(group.Center, 140)
	if not target then
		return
	end
	local toTarget = flat(target.Position - group.Center)
	local dist = if target.Kind == "Stores" then target.Distance else toTarget.Magnitude
	local desiredFacing = flatUnit(toTarget, group.Facing)
	group.Facing = flatUnit(group.Facing:Lerp(desiredFacing, math.min(1, dt * 1.2)), desiredFacing)

	local t = now()
	if dist > line.Range * 0.85 then
		if group.State == "Hold" and t - group.HoldSince < 4 then
			-- Finish the current volley before moving off.
		else
			group.State = "March"
			-- Wait for stragglers so the line stays dressed.
			local lag = 0
			local frame = CFrame.lookAt(group.Center, group.Center + group.Facing)
			for _, m in members do
				lag += (flat(m.Root.Position) - frame:PointToWorldSpace(m.SlotOffset)).Magnitude
			end
			lag /= #members
			local speed = line.Speed * (if lag > 5 then 0.3 else 1)
			local step = desiredFacing * speed * dt
			group.Center = clampToMap(group.Center + step)
		end
	else
		if group.State ~= "Hold" then
			group.State = "Hold"
			group.HoldSince = t
			group.NextVolley = math.max(group.NextVolley, t + 1.5)
			if group.Officer then
				shout(group.Officer, "Halt! Make ready!", 1.5)
			end
		end
		if t >= group.NextVolley then
			local reload = line.Reload * (if group.Officer then Config.OfficerAura.ReloadMultiplier else 1)
			group.NextVolley = t + reload + line.AimTime
			group.HoldSince = t
			for _, m in members do
				if m.Kind == "Regular" and not m.Aiming then
					local own = nearestHostile("Red", m.Root.Position, line.Range) or storesTarget(m.Root.Position)
					local aimAt = if own and own.Distance <= line.Range then own else target
					if aimAt.Distance <= line.Range * 1.15 then
						beginAim(m, aimAt, line.AimTime)
					end
				end
			end
			if group.Officer then
				shout(group.Officer, "Present!", line.AimTime * 0.9)
				task.delay(line.AimTime, function()
					if group.Officer and not group.Officer.Dead then
						shout(group.Officer, "FIRE!", 1)
					end
				end)
			end
		end
	end
end

local function updateFormationMember(unit: Unit, dt: number)
	local group = unit.Group
	local frame = CFrame.lookAt(group.Center, group.Center + group.Facing)
	local slot = frame:PointToWorldSpace(unit.SlotOffset)
	local toSlot = flat(slot - unit.Root.Position)

	if unit.Aiming then
		faceTowards(unit, unit.AimDir, dt)
		if now() >= unit.AimEnd then
			executeAttack(unit)
		end
		return
	end

	-- The officer fights back on his own with his pistol.
	if unit.Kind == "Officer" and now() >= unit.NextAttack then
		local target = nearestHostile("Red", unit.Root.Position, unit.Def.Range)
		if target and hasLineOfSight(unit.Root.Position, target.Position) then
			beginAim(unit, target, unit.Def.AimTime)
			return
		end
	end

	if toSlot.Magnitude > 0.4 then
		local speed = unit.Def.Speed * 1.5
		local step = math.min(toSlot.Magnitude, speed * dt)
		moveUnit(unit, toSlot.Unit, step / dt, dt)
		if toSlot.Magnitude < 2 then
			faceTowards(unit, group.Facing, dt)
		end
	else
		faceTowards(unit, group.Facing, dt)
	end
end

local function updateIndividual(unit: Unit, dt: number)
	local def = unit.Def
	local pos = unit.Root.Position
	local t = now()

	if unit.Aiming then
		faceTowards(unit, unit.AimDir, dt)
		if t >= unit.AimEnd then
			if def.Attack == "Sabre" then
				unit.Aiming = false
				local target = unit.AimTarget
				if target then
					-- Re-measure: the target may have dodged.
					if target.Kind == "Player" and target.Humanoid then
						local r = target.Humanoid.RootPart
						target.Distance = if r then (flat(r.Position) - flat(pos)).Magnitude else math.huge
					elseif target.Kind == "Unit" and target.Unit then
						target.Distance = (flat(target.Unit.Root.Position) - flat(pos)).Magnitude
					end
					sabreStrike(unit, target)
				end
				unit.NextAttack = t + def.Reload
				setPose(unit, "Idle")
			else
				executeAttack(unit)
			end
		end
		return
	end

	local target: Target?
	if unit.Team == "Blue" then
		target = nearestHostile("Blue", pos, 130)
	elseif def.Attack == "Sabre" then
		target = nearestHostile("Red", pos, 400, true) or nearestHostile("Red", pos, 160) or storesTarget(pos)
	elseif def.Attack == "Cannon" then
		target = nearestHostile("Red", pos, def.Range) or storesTarget(pos)
	else
		target = redTarget(pos, 150)
	end

	if not target then
		-- Militia with nothing to shoot fall in beside their owner.
		if unit.Team == "Blue" then
			local owner = unit.Owner
			local char = owner and owner.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local home = if root then root.Position else storesPosition() + Vector3.new(0, 0, -20)
			local toHome = flat(home - pos)
			if toHome.Magnitude > 12 then
				moveUnit(unit, toHome.Unit, def.Speed, dt)
			end
		end
		return
	end

	local toTarget = flat(target.Position - pos)
	local dir = flatUnit(toTarget, unit.Facing)
	local inRange = target.Distance <= def.Range
	local ignoresCover = def.Attack == "Grenade" or def.Attack == "Cannon" or def.Attack == "Sabre"
	local los = ignoresCover or hasLineOfSight(pos, target.Position)

	if inRange and los then
		if t >= unit.NextAttack then
			beginAim(unit, target, def.AimTime)
		elseif def.Attack == "Sabre" then
			-- Wheel around and come back for another pass.
			moveUnit(unit, dir, def.Speed * 0.6, dt)
		else
			faceTowards(unit, dir, dt)
		end
	elseif def.Speed > 0 then
		moveUnit(unit, dir, def.Speed, dt)
	else
		faceTowards(unit, dir, dt)
	end
end

function Units.Step(dt: number)
	for i = #groups, 1, -1 do
		local g = groups[i]
		if #g.Members == 0 then
			table.remove(groups, i)
		else
			updateGroup(g, dt)
		end
	end
	-- Iterate over a snapshot: attacks can kill units mid-loop.
	local snapshot = table.clone(units)
	for _, unit in snapshot do
		if not unit.Dead and unit.Root.Parent then
			if unit.Group then
				updateFormationMember(unit, dt)
			else
				updateIndividual(unit, dt)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Queries and lifecycle
---------------------------------------------------------------------------

function Units.FromInstance(inst: Instance): Unit?
	local model = inst:FindFirstAncestorOfClass("Model")
	return model and byModel[model] or nil
end

function Units.Count(team: string): number
	local n = 0
	for _, u in units do
		if u.Team == team and not u.Dead then
			n += 1
		end
	end
	return n
end

function Units.CountOwnedBy(player: Player): number
	local n = 0
	for _, u in units do
		if u.Owner == player and not u.Dead then
			n += 1
		end
	end
	return n
end

function Units.All(): { Unit }
	return units
end

function Units.Clear(team: string?)
	for i = #units, 1, -1 do
		local u = units[i]
		if team == nil or u.Team == team then
			byModel[u.Model] = nil
			u.Dead = true
			u.Model:Destroy()
			table.remove(units, i)
		end
	end
	if team == nil or team == "Red" then
		table.clear(groups)
	end
end

function Units.RemoveOwnedBy(player: Player)
	for i = #units, 1, -1 do
		local u = units[i]
		if u.Owner == player then
			byModel[u.Model] = nil
			u.Dead = true
			u.Model:Destroy()
			table.remove(units, i)
		end
	end
end

function Units.Init(map: Folder, stores: Model, state: Instance)
	storesModel = stores
	gameState = state
	coverFolder = map:WaitForChild("Cover")
	coverParams.FilterDescendantsInstances = { coverFolder }

	redFolder = Instance.new("Folder")
	redFolder.Name = "Redcoats"
	redFolder.Parent = workspace
	blueFolder = Instance.new("Folder")
	blueFolder.Name = "Militia"
	blueFolder.Parent = workspace
end

return Units
