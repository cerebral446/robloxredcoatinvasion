-- Builds the battlefield procedurally: fields, the road, stone walls, trees,
-- the village and the powder stores the redcoats are marching to seize.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapBuilder = {}

local COLORS = {
	Grass = Color3.fromRGB(96, 128, 56),
	Field = Color3.fromRGB(130, 140, 70),
	Road = Color3.fromRGB(140, 115, 80),
	Stone = Color3.fromRGB(125, 122, 118),
	Wood = Color3.fromRGB(120, 85, 55),
	Clapboard = Color3.fromRGB(205, 195, 175),
	RedBarn = Color3.fromRGB(140, 45, 35),
	Roof = Color3.fromRGB(70, 60, 55),
	Trunk = Color3.fromRGB(90, 65, 40),
	Leaves = Color3.fromRGB(55, 95, 40),
}

local mapFolder: Folder
local coverFolder: Folder
local decorFolder: Folder

-- Cover blocks musket balls and movement. Decor does neither for shots.
local function part(props: { [string]: any }, parent: Instance, isCover: boolean): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	if not isCover then
		p.CanQuery = false
	end
	p.Parent = parent
	return p
end

local function wedge(props: { [string]: any }, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(w :: any)[k] = v
	end
	w.Parent = parent
	return w
end

local function stoneWall(from: Vector3, to: Vector3)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	part({
		Name = "StoneWall",
		Size = Vector3.new(2.5, 4, length),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, 2, mid.Z), Vector3.new(to.X, 2, to.Z)),
		Color = COLORS.Stone,
		Material = Enum.Material.Slate,
	}, coverFolder, true)
end

local function rail(from: Vector3, to: Vector3)
	-- Low split-rail fence: purely decorative, shots pass over it.
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(to.X, 0, to.Z))
	for _, h in { 0.9, 1.9 } do
		part({
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, length),
			CFrame = cf + Vector3.new(0, h, 0),
			Color = COLORS.Wood,
			Material = Enum.Material.Wood,
		}, decorFolder, false)
	end
end

local function tree(pos: Vector3, scale: number)
	local trunk = part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10 * scale, 2.2 * scale, 2.2 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.Trunk,
		Material = Enum.Material.Wood,
	}, coverFolder, true)
	trunk.Name = "Tree"
	local leaves = part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 11 * scale,
		Position = pos + Vector3.new(0, 11 * scale, 0),
		Color = COLORS.Leaves,
		Material = Enum.Material.Grass,
		CanCollide = false,
		Transparency = 0.15,
	}, decorFolder, false)
	leaves.CastShadow = true
end

local function rock(pos: Vector3, size: Vector3)
	part({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(pos + Vector3.new(0, size.Y / 2 - 0.3, 0))
			* CFrame.Angles(0, math.random() * math.pi, math.rad(math.random(-8, 8))),
		Color = COLORS.Stone,
		Material = Enum.Material.Rock,
	}, coverFolder, true)
end

local function house(pos: Vector3, yaw: number, size: Vector3, wallColor: Color3)
	local model = Instance.new("Model")
	model.Name = "House"
	local base = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	part({
		Name = "Walls",
		Size = size,
		CFrame = base * CFrame.new(0, size.Y / 2, 0),
		Color = wallColor,
		Material = Enum.Material.WoodPlanks,
	}, model, true)
	local roofHeight = size.X * 0.45
	-- Two wedges make a gable roof running along Z.
	wedge({
		Name = "RoofL",
		Size = Vector3.new(size.Z + 1, roofHeight, size.X / 2 + 0.5),
		CFrame = base * CFrame.new(-size.X / 4 - 0.25, size.Y + roofHeight / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = COLORS.Roof,
		Material = Enum.Material.Slate,
	}, model)
	wedge({
		Name = "RoofR",
		Size = Vector3.new(size.Z + 1, roofHeight, size.X / 2 + 0.5),
		CFrame = base * CFrame.new(size.X / 4 + 0.25, size.Y + roofHeight / 2, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Color = COLORS.Roof,
		Material = Enum.Material.Slate,
	}, model)
	part({
		Name = "Chimney",
		Size = Vector3.new(2, roofHeight + 3, 2),
		CFrame = base * CFrame.new(0, size.Y + (roofHeight + 3) / 2, size.Z / 2 - 2),
		Color = COLORS.Stone,
		Material = Enum.Material.Brick,
	}, model, false)
	for _, side in { -1, 1 } do
		part({
			Name = "Window",
			Size = Vector3.new(0.2, 2.5, 2.5),
			CFrame = base * CFrame.new(side * (size.X / 2 + 0.05), size.Y * 0.55, 0),
			Color = Color3.fromRGB(40, 50, 60),
			Material = Enum.Material.Glass,
		}, model, false)
	end
	for _, p in model:GetChildren() do
		(p :: BasePart).CanQuery = p.Name == "Walls"
	end
	model.Parent = coverFolder
end

local function church(pos: Vector3)
	house(pos, 0, Vector3.new(18, 12, 26), Color3.fromRGB(235, 232, 225))
	local steepleBase = CFrame.new(pos + Vector3.new(0, 0, -15))
	part({
		Name = "Tower",
		Size = Vector3.new(7, 22, 7),
		CFrame = steepleBase * CFrame.new(0, 11, 0),
		Color = Color3.fromRGB(235, 232, 225),
		Material = Enum.Material.WoodPlanks,
	}, coverFolder, true)
	part({
		Name = "Belfry",
		Size = Vector3.new(5, 6, 5),
		CFrame = steepleBase * CFrame.new(0, 25, 0),
		Color = Color3.fromRGB(235, 232, 225),
		Material = Enum.Material.WoodPlanks,
	}, decorFolder, false)
	for i, w in { 4, 2.6, 1.2 } do
		part({
			Name = "Spire",
			Size = Vector3.new(w, 3.5, w),
			CFrame = steepleBase * CFrame.new(0, 28 + i * 3.5 - 1.75, 0),
			Color = COLORS.Roof,
			Material = Enum.Material.Slate,
		}, decorFolder, false)
	end
end

local function buildStores(): Model
	local pos = Config.Map.StoresPosition
	local model = Instance.new("Model")
	model.Name = "PowderStores"
	local building = part({
		Name = "Magazine",
		Size = Vector3.new(16, 9, 12),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)),
		Color = Color3.fromRGB(130, 110, 90),
		Material = Enum.Material.Brick,
	}, model, true)
	wedge({
		Name = "RoofL",
		Size = Vector3.new(13, 4, 8.5),
		CFrame = CFrame.new(pos + Vector3.new(-4.25, 11, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Color = COLORS.Roof,
	}, model)
	wedge({
		Name = "RoofR",
		Size = Vector3.new(13, 4, 8.5),
		CFrame = CFrame.new(pos + Vector3.new(4.25, 11, 0)) * CFrame.Angles(0, math.rad(-90), 0),
		Color = COLORS.Roof,
	}, model)
	-- Powder kegs out front.
	for i = -2, 2 do
		local keg = part({
			Name = "Keg",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.4, 2.2, 2.2),
			CFrame = CFrame.new(pos + Vector3.new(i * 2.6, 1.1, -8)) * CFrame.Angles(math.rad(90), 0, 0),
			Color = Color3.fromRGB(100, 70, 40),
			Material = Enum.Material.Wood,
		}, model, false)
		keg.CanCollide = true
	end
	-- Liberty flag.
	part({
		Name = "Pole",
		Size = Vector3.new(0.5, 26, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(10, 13, -6)),
		Color = Color3.fromRGB(230, 230, 230),
	}, model, false)
	part({
		Name = "Flag",
		Size = Vector3.new(7, 4, 0.2),
		CFrame = CFrame.new(pos + Vector3.new(13.75, 23.5, -6)),
		Color = Color3.fromRGB(30, 60, 140),
		Material = Enum.Material.Fabric,
	}, model, false)

	model.PrimaryPart = building
	model:SetAttribute("IsStores", true)
	model.Parent = mapFolder
	return model
end

function MapBuilder.Build(): (Folder, Model)
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local oldBaseplate = workspace:FindFirstChild("Baseplate")
	if oldBaseplate then
		oldBaseplate:Destroy()
	end

	math.randomseed(1775) -- same map every time

	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	coverFolder = Instance.new("Folder")
	coverFolder.Name = "Cover"
	coverFolder.Parent = mapFolder
	decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = mapFolder

	local m = Config.Map
	local width = m.HalfWidth * 2 + 120
	local depth = (m.SouthEdge - m.NorthEdge) + 120
	local centerZ = (m.SouthEdge + m.NorthEdge) / 2

	local ground = part({
		Name = "Ground",
		Size = Vector3.new(width, 2, depth),
		CFrame = CFrame.new(0, -1, centerZ),
		Color = COLORS.Grass,
		Material = Enum.Material.Grass,
	}, mapFolder, false)
	ground.CanQuery = true -- used for mouse/grenade placement only; shots are horizontal

	-- Fields and road.
	for _, f in { { -80, -120, 90, 70 }, { 85, -40, 80, 90 }, { -90, 40, 70, 60 } } do
		part({
			Name = "Field",
			Size = Vector3.new(f[3], 0.2, f[4]),
			CFrame = CFrame.new(f[1], 0.05, f[2]),
			Color = COLORS.Field,
			Material = Enum.Material.Ground,
		}, decorFolder, false)
	end
	part({
		Name = "Road",
		Size = Vector3.new(14, 0.2, depth),
		CFrame = CFrame.new(0, 0.1, centerZ),
		Color = COLORS.Road,
		Material = Enum.Material.Ground,
	}, decorFolder, false)
	part({
		Name = "VillageGreen",
		Size = Vector3.new(70, 0.2, 50),
		CFrame = CFrame.new(0, 0.12, 125),
		Color = Color3.fromRGB(110, 145, 65),
		Material = Enum.Material.Grass,
	}, decorFolder, false)

	-- Boundary walls keep everyone on the battlefield.
	local hw = m.HalfWidth
	for _, b in {
		{ Vector3.new(-hw - 2, 10, centerZ), Vector3.new(4, 20, depth) },
		{ Vector3.new(hw + 2, 10, centerZ), Vector3.new(4, 20, depth) },
		{ Vector3.new(0, 10, m.SouthEdge + 2), Vector3.new(width, 20, 4) },
		{ Vector3.new(0, 10, m.NorthEdge - 2), Vector3.new(width, 20, 4) },
	} do
		part({
			Name = "Boundary",
			Size = b[2],
			Position = b[1],
			Transparency = 1,
			CanQuery = false,
		}, mapFolder, false)
	end

	-- New England stone walls give cover across the battlefield.
	stoneWall(Vector3.new(-60, 0, -60), Vector3.new(-25, 0, -60))
	stoneWall(Vector3.new(25, 0, -60), Vector3.new(60, 0, -60))
	stoneWall(Vector3.new(-120, 0, -10), Vector3.new(-70, 0, 5))
	stoneWall(Vector3.new(70, 0, 10), Vector3.new(125, 0, 0))
	stoneWall(Vector3.new(-40, 0, 40), Vector3.new(-14, 0, 40))
	stoneWall(Vector3.new(14, 0, 40), Vector3.new(40, 0, 40))
	stoneWall(Vector3.new(-100, 0, 80), Vector3.new(-60, 0, 75))
	stoneWall(Vector3.new(60, 0, 75), Vector3.new(100, 0, 80))

	-- Split rail fences along the road.
	for z = -200, 60, 40 do
		rail(Vector3.new(-9, 0, z), Vector3.new(-9, 0, z + 30))
		rail(Vector3.new(9, 0, z), Vector3.new(9, 0, z + 30))
	end

	-- Woods on the flanks.
	for _ = 1, 45 do
		local side = if math.random() < 0.5 then -1 else 1
		local x = side * math.random(100, hw - 6)
		local z = math.random(m.NorthEdge + 40, 90)
		tree(Vector3.new(x, 0, z), 0.8 + math.random() * 0.5)
	end
	for _ = 1, 14 do
		local x = math.random(-90, 90)
		local z = math.random(-170, 70)
		if math.abs(x) > 14 then
			tree(Vector3.new(x, 0, z), 0.7 + math.random() * 0.4)
		end
	end
	for _ = 1, 18 do
		local x = math.random(-hw + 10, hw - 10)
		local z = math.random(-180, 80)
		if math.abs(x) > 12 then
			rock(Vector3.new(x, 0, z), Vector3.new(math.random(3, 6), math.random(3, 5), math.random(3, 6)))
		end
	end

	-- The village around the green.
	house(Vector3.new(-45, 0, 115), 90, Vector3.new(14, 10, 20), COLORS.Clapboard)
	house(Vector3.new(45, 0, 115), -90, Vector3.new(14, 10, 20), COLORS.Clapboard)
	house(Vector3.new(-50, 0, 150), 0, Vector3.new(14, 9, 18), COLORS.RedBarn)
	house(Vector3.new(52, 0, 152), 0, Vector3.new(16, 10, 18), COLORS.Clapboard)
	house(Vector3.new(-100, 0, 130), 15, Vector3.new(14, 10, 22), COLORS.RedBarn)
	house(Vector3.new(105, 0, 125), -10, Vector3.new(14, 10, 20), COLORS.Clapboard)
	church(Vector3.new(-28, 0, 70))

	-- A small bridge-like crossing point: the "North Bridge" landmark.
	part({
		Name = "Creek",
		Size = Vector3.new(width, 0.25, 12),
		CFrame = CFrame.new(0, 0.08, -95),
		Color = Color3.fromRGB(60, 100, 140),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
	}, decorFolder, false)
	part({
		Name = "Bridge",
		Size = Vector3.new(16, 0.6, 16),
		CFrame = CFrame.new(0, 0.3, -95),
		Color = COLORS.Wood,
		Material = Enum.Material.WoodPlanks,
	}, decorFolder, false)

	local stores = buildStores()

	mapFolder.Parent = workspace

	-- Warm late-afternoon light.
	Lighting.ClockTime = 16.5
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 130, 115)
	Lighting.GlobalShadows = true

	math.randomseed(os.clock() * 1000)

	return mapFolder, stores
end

return MapBuilder
