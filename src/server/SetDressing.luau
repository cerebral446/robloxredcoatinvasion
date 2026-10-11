-- Atmosphere and set dressing: golden-hour lighting, fires, lanterns, flags,
-- the British redoubt, palisades, crates, barrels, haystacks and the forge.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local SetDressing = {}

local DARK_WOOD = Color3.fromRGB(80, 55, 35)
local STONE = Color3.fromRGB(150, 140, 125)
local IRON = Color3.fromRGB(45, 45, 48)
local FIRE_ORANGE = Color3.fromRGB(255, 140, 50)

local function part(props: { [string]: any }, parent: Instance, blocksShots: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.CanQuery = blocksShots == true
	p.Parent = parent
	return p
end

-- A light that the client makes flicker like a flame.
local function flameLight(parent: BasePart, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = FIRE_ORANGE
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light:SetAttribute("BaseBrightness", brightness)
	light.Parent = parent
	CollectionService:AddTag(light, "Flicker")
	return light
end

local function flames(parent: BasePart, size: number, smoky: boolean)
	local fire = Instance.new("Fire")
	fire.Size = size
	fire.Heat = size * 1.6
	fire.Color = Color3.fromRGB(255, 120, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 210, 90)
	fire.Parent = parent
	if smoky then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(70, 65, 60)
		smoke.Opacity = 0.12
		smoke.RiseVelocity = 5
		smoke.Size = size * 0.8
		smoke.Parent = parent
	end
end

local function fireSource(pos: Vector3, size: number, folder: Instance, smoky: boolean, lightRange: number?)
	local src = part({
		Name = "FireSource",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = pos,
		Transparency = 1,
		CanCollide = false,
	}, folder)
	flames(src, size, smoky)
	flameLight(src, 2.5, lightRange or size * 4)
	return src
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------

local function campfire(pos: Vector3, folder: Instance)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part({
			Name = "FireStone",
			Size = Vector3.new(0.9, 0.6, 0.9),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.8, 0.3, math.sin(a) * 1.8)) * CFrame.Angles(0, a, 0),
			Color = STONE,
			Material = Enum.Material.Slate,
			CanCollide = false,
		}, folder)
	end
	for i = 0, 2 do
		part({
			Name = "Log",
			Size = Vector3.new(0.5, 0.5, 2.8),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.rad(-15), i * math.rad(60), 0),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
			CanCollide = false,
		}, folder)
	end
	part({
		Name = "Embers",
		Size = Vector3.new(1.6, 0.15, 1.6),
		Position = pos + Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(255, 90, 20),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, folder)
	fireSource(pos + Vector3.new(0, 1, 0), 3, folder, true, 20)
end

local function lantern(pos: Vector3, folder: Instance)
	part({
		Name = "LanternPost",
		Size = Vector3.new(0.5, 8, 0.5),
		Position = pos + Vector3.new(0, 4, 0),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	}, folder)
	part({
		Name = "LanternArm",
		Size = Vector3.new(0.3, 0.3, 1.6),
		Position = pos + Vector3.new(0, 7.8, -0.7),
		Color = IRON,
		Material = Enum.Material.Metal,
	}, folder)
	part({
		Name = "LanternCap",
		Size = Vector3.new(1.1, 0.3, 1.1),
		Position = pos + Vector3.new(0, 7.6, -1.3),
		Color = IRON,
		Material = Enum.Material.Metal,
	}, folder)
	local glass = part({
		Name = "Lantern",
		Size = Vector3.new(0.8, 1.1, 0.8),
		Position = pos + Vector3.new(0, 6.9, -1.3),
		Color = Color3.fromRGB(255, 200, 110),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	}, folder)
	flameLight(glass, 1.6, 16)
end

local function crate(pos: Vector3, yaw: number, folder: Instance)
	local c = part({
		Name = "Crate",
		Size = Vector3.new(3.4, 3.4, 3.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, math.rad(yaw), 0),
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.WoodPlanks,
	}, folder, true)
	for _, z in { -1, 1 } do
		part({
			Name = "CrateBand",
			Size = Vector3.new(3.5, 0.35, 0.2),
			CFrame = c.CFrame * CFrame.new(0, 0, z * 1.7),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
		}, folder)
	end
end

local function barrel(pos: Vector3, folder: Instance)
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.4, 2.4, 2.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(125, 85, 50),
		Material = Enum.Material.Wood,
	}, folder, true)
	for _, y in { 0.5, 2.9 } do
		part({
			Name = "Hoop",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 2.5, 2.5),
			CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = IRON,
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, folder)
	end
end

local function haystack(pos: Vector3, burning: boolean, cover: Instance, decor: Instance)
	part({
		Name = "Haystack",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 7, 7),
		Position = pos + Vector3.new(0, 1.5, 0),
		Color = if burning then Color3.fromRGB(110, 85, 40) else Color3.fromRGB(205, 175, 90),
		Material = Enum.Material.Grass,
	}, cover, true)
	if burning then
		fireSource(pos + Vector3.new(0, 4.5, 0), 7, decor, true, 26)
	end
end

local function wagonWreck(pos: Vector3, yaw: number, cover: Instance, decor: Instance)
	local base = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	part({
		Name = "WagonBed",
		Size = Vector3.new(5, 1, 9),
		CFrame = base * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(12)),
		Color = Color3.fromRGB(60, 40, 25),
		Material = Enum.Material.WoodPlanks,
	}, cover, true)
	part({
		Name = "WagonSide",
		Size = Vector3.new(0.4, 2.2, 9),
		CFrame = base * CFrame.new(-2.4, 2.4, 0) * CFrame.Angles(0, 0, math.rad(20)),
		Color = Color3.fromRGB(50, 35, 22),
		Material = Enum.Material.WoodPlanks,
	}, cover, true)
	part({
		Name = "Wheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3.6, 3.6),
		CFrame = base * CFrame.new(3, 0.25, 2.5) * CFrame.Angles(0, 0, math.rad(90)),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	}, decor)
	part({
		Name = "Wheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3.6, 3.6),
		CFrame = base * CFrame.new(2.6, 1.8, -2.5) * CFrame.Angles(0, 0, math.rad(15)),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	}, decor)
	fireSource((base * CFrame.new(0, 2.5, 0)).Position, 6, decor, true, 24)
end

-- A row of sharpened stakes like the stockade in the poster.
local function palisade(from: Vector3, to: Vector3, cover: Instance)
	local delta = to - from
	local count = math.floor(delta.Magnitude / 1.1)
	local dir = delta.Unit
	for i = 0, count do
		local p = from + dir * (i * 1.1)
		local height = 4.6 + math.random() * 0.8
		local stake = part({
			Name = "Stake",
			Size = Vector3.new(1, height, 1),
			CFrame = CFrame.lookAt(p + Vector3.new(0, height / 2, 0), p + Vector3.new(0, height / 2, 0) + dir)
				* CFrame.Angles(0, 0, math.rad(math.random(-4, 4))),
			Color = Color3.fromRGB(125 + math.random(-10, 10), 90, 55),
			Material = Enum.Material.Wood,
		}, cover, true)
		-- The point: a small block turned 45 degrees.
		part({
			Name = "StakeTip",
			Size = Vector3.new(0.72, 0.72, 0.72),
			CFrame = stake.CFrame * CFrame.new(0, height / 2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			Color = stake.Color,
			Material = Enum.Material.Wood,
			CanCollide = false,
		}, cover)
	end
	-- Horizontal binding rail.
	local mid = (from + to) / 2
	part({
		Name = "PalisadeRail",
		Size = Vector3.new(0.4, 0.4, delta.Magnitude),
		CFrame = CFrame.lookAt(mid + Vector3.new(0, 2.5, 0), to + Vector3.new(0, 2.5, 0)) * CFrame.new(0, 0, 0),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		CanCollide = false,
	}, cover)
end

---------------------------------------------------------------------------
-- Flags
---------------------------------------------------------------------------

local function flagPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance)
	part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		CastShadow = false,
	}, parent)
end

-- British Union flag. `cf` is the centre of the flag, facing -Z.
function SetDressing.UnionFlag(cf: CFrame, w: number, h: number, parent: Instance)
	local blue = Color3.fromRGB(1, 33, 105)
	local white = Color3.fromRGB(245, 245, 245)
	local red = Color3.fromRGB(200, 16, 46)
	flagPart("Field", Vector3.new(w, h, 0.1), cf, blue, parent)
	local diag = math.sqrt(w * w + h * h) - h * 0.2
	local angle = math.atan2(h, w)
	for _, sign in { 1, -1 } do
		flagPart("SaltireWhite", Vector3.new(diag, h * 0.2, 0.1), cf * CFrame.new(0, 0, -0.02) * CFrame.Angles(0, 0, sign * angle), white, parent)
		flagPart("SaltireRed", Vector3.new(diag, h * 0.07, 0.1), cf * CFrame.new(0, 0, -0.04) * CFrame.Angles(0, 0, sign * angle), red, parent)
	end
	flagPart("CrossWhiteH", Vector3.new(w, h * 0.33, 0.1), cf * CFrame.new(0, 0, -0.06), white, parent)
	flagPart("CrossWhiteV", Vector3.new(h * 0.33, h, 0.1), cf * CFrame.new(0, 0, -0.06), white, parent)
	flagPart("CrossRedH", Vector3.new(w, h * 0.2, 0.1), cf * CFrame.new(0, 0, -0.08), red, parent)
	flagPart("CrossRedV", Vector3.new(h * 0.2, h, 0.1), cf * CFrame.new(0, 0, -0.08), red, parent)
end

-- Thirteen stripes with a ring of thirteen stars.
function SetDressing.StripesFlag(cf: CFrame, w: number, h: number, parent: Instance)
	local red = Color3.fromRGB(178, 34, 52)
	local white = Color3.fromRGB(245, 245, 245)
	local stripe = h / 13
	for i = 0, 12 do
		local y = h / 2 - stripe * (i + 0.5)
		flagPart("Stripe", Vector3.new(w, stripe, 0.1), cf * CFrame.new(0, y, 0), if i % 2 == 0 then red else white, parent)
	end
	local cw, ch = w * 0.4, stripe * 7
	local canton = cf * CFrame.new(-w / 2 + cw / 2, h / 2 - ch / 2, -0.03)
	flagPart("Canton", Vector3.new(cw, ch, 0.1), canton, Color3.fromRGB(60, 59, 110), parent)
	local r = math.min(cw, ch) * 0.32
	for i = 0, 12 do
		local a = i / 13 * math.pi * 2
		flagPart("Star", Vector3.new(0.22, 0.22, 0.1), canton * CFrame.new(math.cos(a) * r, math.sin(a) * r, -0.03), white, parent)
	end
end

local function flagpole(base: Vector3, height: number, folder: Instance): CFrame
	part({
		Name = "Flagpole",
		Size = Vector3.new(0.5, height, 0.5),
		Position = base + Vector3.new(0, height / 2, 0),
		Color = Color3.fromRGB(90, 70, 50),
		Material = Enum.Material.Wood,
	}, folder)
	part({
		Name = "Finial",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.9,
		Position = base + Vector3.new(0, height + 0.3, 0),
		Color = Color3.fromRGB(214, 172, 60),
		Material = Enum.Material.Metal,
	}, folder)
	return CFrame.new(base + Vector3.new(0, height, 0))
end

---------------------------------------------------------------------------
-- Large set pieces
---------------------------------------------------------------------------

-- The British redoubt along the north edge, where the Regulars march from.
local function redoubt(northZ: number, halfWidth: number, cover: Instance, decor: Instance)
	local z = northZ + 4
	local wallColor = Color3.fromRGB(140, 130, 115)
	part({
		Name = "RedoubtWall",
		Size = Vector3.new(halfWidth * 2, 7, 3),
		Position = Vector3.new(0, 3.5, z),
		Color = wallColor,
		Material = Enum.Material.Cobblestone,
	}, cover, true)
	for x = -halfWidth + 2, halfWidth - 2, 4 do
		part({
			Name = "Merlon",
			Size = Vector3.new(2, 1.6, 3),
			Position = Vector3.new(x, 7.8, z),
			Color = wallColor,
			Material = Enum.Material.Cobblestone,
		}, decor)
	end
	for _, x in { -88, 88 } do
		part({
			Name = "Bastion",
			Size = Vector3.new(12, 11, 9),
			Position = Vector3.new(x, 5.5, z - 1),
			Color = wallColor,
			Material = Enum.Material.Cobblestone,
		}, cover, true)
		for i = -1, 1 do
			part({
				Name = "Merlon",
				Size = Vector3.new(2.4, 1.8, 2.4),
				Position = Vector3.new(x + i * 4.5, 11.9, z + 3),
				Color = wallColor,
				Material = Enum.Material.Cobblestone,
			}, decor)
		end
		-- Union flag flying over each bastion.
		local top = flagpole(Vector3.new(x, 11, z - 2), 16, decor)
		SetDressing.UnionFlag(top * CFrame.new(4.2, -2.2, 0) * CFrame.Angles(0, math.rad(180), 0), 8, 4.2, decor)
		-- A brazier burning on the bastion.
		local brazier = part({
			Name = "Brazier",
			Size = Vector3.new(1.6, 1.2, 1.6),
			Position = Vector3.new(x - 4, 11.6, z - 2),
			Color = IRON,
			Material = Enum.Material.Metal,
		}, decor)
		fireSource(brazier.Position + Vector3.new(0, 1, 0), 2.5, decor, false, 18)
	end
end

local function forge(pos: Vector3, cover: Instance, decor: Instance)
	part({
		Name = "Forge",
		Size = Vector3.new(5, 3, 4),
		Position = pos + Vector3.new(0, 1.5, 0),
		Color = STONE,
		Material = Enum.Material.Brick,
	}, cover, true)
	part({
		Name = "ForgeChimney",
		Size = Vector3.new(2.4, 9, 2.4),
		Position = pos + Vector3.new(0, 7.5, 1.2),
		Color = STONE,
		Material = Enum.Material.Brick,
	}, decor)
	part({
		Name = "Coals",
		Size = Vector3.new(3, 0.3, 2),
		Position = pos + Vector3.new(0, 3.1, -0.4),
		Color = Color3.fromRGB(255, 90, 20),
		Material = Enum.Material.Neon,
	}, decor)
	fireSource(pos + Vector3.new(0, 3.6, -0.4), 2.2, decor, true, 18)
	-- Roof over the smithy.
	for _, x in { -3.5, 3.5 } do
		part({
			Name = "SmithyPost",
			Size = Vector3.new(0.5, 8, 0.5),
			Position = pos + Vector3.new(x, 4, -6),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
		}, decor)
	end
	part({
		Name = "SmithyRoof",
		Size = Vector3.new(9, 0.4, 9),
		CFrame = CFrame.new(pos + Vector3.new(0, 8.2, -2)) * CFrame.Angles(math.rad(-8), 0, 0),
		Color = Color3.fromRGB(80, 65, 55),
		Material = Enum.Material.WoodPlanks,
	}, decor)
	-- The anvil: townsfolk look this part up to place the blacksmith.
	part({
		Name = "AnvilBase",
		Size = Vector3.new(1, 1.6, 1),
		Position = pos + Vector3.new(0, 0.8, -4.5),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
	}, decor)
	part({
		Name = "Anvil",
		Size = Vector3.new(0.9, 0.6, 2),
		Position = pos + Vector3.new(0, 1.9, -4.5),
		Color = IRON,
		Material = Enum.Material.Metal,
	}, decor)
end

---------------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------------

local function lighting()
	Lighting.ClockTime = 17.3
	Lighting.GeographicLatitude = 42
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(75, 60, 50)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 125, 95)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ExposureCompensation = 0.15
	Lighting.GlobalShadows = true

	for _, child in Lighting:GetChildren() do
		if child:GetAttribute("RedcoatFX") then
			child:Destroy()
		end
	end
	local function add(className: string, props: { [string]: any })
		local inst = Instance.new(className)
		for k, v in props do
			(inst :: any)[k] = v
		end
		inst:SetAttribute("RedcoatFX", true)
		inst.Parent = Lighting
	end
	add("Atmosphere", {
		Density = 0.28,
		Offset = 0.15,
		Color = Color3.fromRGB(255, 214, 160),
		Decay = Color3.fromRGB(190, 120, 80),
		Glare = 0.5,
		Haze = 1.4,
	})
	add("ColorCorrectionEffect", {
		Brightness = 0.02,
		Contrast = 0.15,
		Saturation = 0.28,
		TintColor = Color3.fromRGB(255, 236, 212),
	})
	add("BloomEffect", { Intensity = 0.7, Size = 30, Threshold = 1.5 })
	add("SunRaysEffect", { Intensity = 0.07, Spread = 0.7 })
end

---------------------------------------------------------------------------

function SetDressing.Build(map: Folder, cover: Folder, decor: Folder, northZ: number, halfWidth: number)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = decor

	-- Village: campfires on the green, the smithy, lanterns along the street.
	campfire(Vector3.new(-24, 0, 100), props)
	campfire(Vector3.new(26, 0, 102), props)
	campfire(Vector3.new(-75, 0, 140), props)
	campfire(Vector3.new(80, 0, 140), props)
	forge(Vector3.new(24, 0, 162), cover, props)
	for _, z in { 70, 95, 120, 150 } do
		lantern(Vector3.new(-11, 0, z), props)
		lantern(Vector3.new(11, 0, z), props)
	end
	lantern(Vector3.new(-36, 0, 106), props)
	lantern(Vector3.new(36, 0, 106), props)
	lantern(Vector3.new(-50, 0, 138), props)
	lantern(Vector3.new(52, 0, 140), props)

	-- Stockade with firing gaps in front of the village.
	palisade(Vector3.new(-72, 0, 88), Vector3.new(-48, 0, 88), cover)
	palisade(Vector3.new(-40, 0, 88), Vector3.new(-16, 0, 88), cover)
	palisade(Vector3.new(16, 0, 88), Vector3.new(40, 0, 88), cover)
	palisade(Vector3.new(48, 0, 88), Vector3.new(72, 0, 88), cover)

	-- Supplies stacked as barricades.
	crate(Vector3.new(-12, 0, 84), 10, cover)
	crate(Vector3.new(13, 0, 85), -15, cover)
	barrel(Vector3.new(-14.5, 0, 87.5), cover)
	barrel(Vector3.new(15.5, 0, 88.5), cover)
	crate(Vector3.new(-14, 0, 128), 0, cover)
	barrel(Vector3.new(-14, 0, 132), cover)
	barrel(Vector3.new(14, 0, 130), cover)
	crate(Vector3.new(14, 0, 142), 25, cover)
	crate(Vector3.new(-30, 0, 30), 5, cover)
	barrel(Vector3.new(-26, 0, 31), cover)
	crate(Vector3.new(30, 0, -30), -20, cover)
	barrel(Vector3.new(33, 0, -27), cover)

	-- The battle has already reached the countryside.
	haystack(Vector3.new(75, 0, -50), true, cover, props)
	haystack(Vector3.new(97, 0, -28), false, cover, props)
	haystack(Vector3.new(-90, 0, -108), false, cover, props)
	haystack(Vector3.new(-68, 0, -138), true, cover, props)
	haystack(Vector3.new(-95, 0, 35), false, cover, props)
	wagonWreck(Vector3.new(-30, 0, -20), 30, cover, props)
	wagonWreck(Vector3.new(40, 0, -150), -60, cover, props)
	-- The barn roof and an outlying farmhouse are burning.
	fireSource(Vector3.new(-50, 13, 150), 8, props, true, 30)
	fireSource(Vector3.new(-100, 14, 128), 9, props, true, 30)

	redoubt(northZ, halfWidth, cover, props)
	lighting()
end

return SetDressing
