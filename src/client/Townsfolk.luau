-- Townsfolk: cosmetic villagers that make the town feel alive. They run
-- entirely on each client (no network traffic): they wander the village,
-- chat, and panic once the Regulars attack. They can't be shot or hurt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Townsfolk = {}

local gameState = ReplicatedStorage:WaitForChild("GameState")

local SKIN_TONES = {
	Color3.fromRGB(234, 192, 160),
	Color3.fromRGB(210, 160, 120),
	Color3.fromRGB(160, 110, 75),
	Color3.fromRGB(110, 75, 50),
}
local CLOTH = {
	Color3.fromRGB(110, 75, 50),
	Color3.fromRGB(70, 90, 60),
	Color3.fromRGB(130, 60, 45),
	Color3.fromRGB(60, 70, 100),
	Color3.fromRGB(150, 130, 100),
	Color3.fromRGB(90, 60, 80),
}
local WHITE = Color3.fromRGB(240, 236, 225)
local BLACK = Color3.fromRGB(30, 28, 26)
local WOOD = Color3.fromRGB(105, 70, 40)

-- Open ground in the village that folk stroll between.
local WAYPOINTS = {
	Vector3.new(-20, 0, 96), Vector3.new(20, 0, 96), Vector3.new(-25, 0, 115), Vector3.new(25, 0, 112),
	Vector3.new(-22, 0, 140), Vector3.new(22, 0, 145), Vector3.new(0, 0, 155), Vector3.new(-30, 0, 160),
	Vector3.new(35, 0, 160), Vector3.new(-62, 0, 125), Vector3.new(65, 0, 130), Vector3.new(-70, 0, 160),
	Vector3.new(75, 0, 105), Vector3.new(-75, 0, 100), Vector3.new(0, 0, 94), Vector3.new(-5, 0, 165),
}
-- Where people huddle while the battle rages.
local SHELTER = {
	Vector3.new(-30, 0, 162), Vector3.new(-12, 0, 160), Vector3.new(10, 0, 163),
	Vector3.new(-65, 0, 165), Vector3.new(70, 0, 165), Vector3.new(38, 0, 165),
}

local CHATTER = {
	"Fine evening, neighbour.",
	"Have you seen the Regulars?",
	"Mind the powder stores!",
	"The bread's fresh today.",
	"My boy joined the militia.",
	"They say the King is cross.",
	"Liberty or death, I say!",
	"Lovely weather for a revolution.",
	"Is that smoke over the hill?",
	"I hid the silver in the well.",
}
local PANIC = {
	"The Regulars are coming!",
	"To arms! To arms!",
	"Hide the children!",
	"Huzzah for the militia!",
	"Run!",
	"Save the powder!",
	"God help us!",
	"Give 'em what for, lads!",
}
local CRIER = {
	"Hear ye, hear ye!",
	"The Regulars march from Boston!",
	"All militia to the North Bridge!",
	"Defend the powder stores!",
}
local CRIER_PANIC = { "To arms! The Regulars are upon us!", "Every man to the line!", "Hold them at the stockade!" }

type Villager = {
	Model: Model,
	Root: BasePart,
	LeftLeg: Weld?,
	RightLeg: Weld?,
	LeftArm: Weld?,
	RightArm: Weld?,
	Role: string,
	Speed: number,
	Target: Vector3?,
	WaitUntil: number,
	Phase: number,
	NextTalk: number,
	Bubble: TextLabel,
	Scale: number,
	Facing: Vector3,
	Anchor: Vector3?,
}

local folder: Folder
local villagers: { Villager } = {}
local chickens: { { Root: BasePart, Target: Vector3, WaitUntil: number, Head: Weld } } = {}
local avoidParams = RaycastParams.new()
avoidParams.FilterType = Enum.RaycastFilterType.Include

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
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
	return p
end

local function fixed(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
	local p = newPart(name, size, color, material)
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

-- A limb hung from a joint: the weld's C0 is the joint, C1 offsets the limb
-- so rotating C0 swings it like a pendulum.
local function limb(model: Model, root: BasePart, name: string, size: Vector3, joint: Vector3, color: Color3, material: Enum.Material?): (Part, Weld)
	local p = newPart(name, size, color, material)
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = CFrame.new(joint)
	w.C1 = CFrame.new(0, size.Y / 2, 0)
	p.CFrame = root.CFrame * w.C0 * w.C1:Inverse()
	w.Parent = p
	p.Parent = model
	return p, w
end

local function makeBubble(root: BasePart, height: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(250, 244, 228)
	text.BackgroundTransparency = 1
	text.TextTransparency = 1
	text.TextColor3 = Color3.fromRGB(45, 32, 22)
	text.Font = Enum.Font.Antique
	text.TextScaled = true
	text.TextWrapped = true
	text.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = text
	text.Parent = gui
	gui.Parent = root
	return text
end

local function say(v: Villager, line: string, duration: number?)
	local bubble = v.Bubble
	bubble.Text = line
	bubble.BackgroundTransparency = 0.1
	bubble.TextTransparency = 0
	local stamp = os.clock()
	bubble:SetAttribute("Stamp", stamp)
	task.delay(duration or 3, function()
		if bubble:GetAttribute("Stamp") == stamp then
			TweenService:Create(bubble, TweenInfo.new(0.5), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------------------
-- Building villagers
---------------------------------------------------------------------------

local function buildVillager(role: string, pos: Vector3): Villager
	local isWoman = role == "Woman"
	local isChild = role == "Child" or role == "Drummer"
	local s = if isChild then 0.68 else 1
	local skin = pick(SKIN_TONES)
	local cloth = pick(CLOTH)

	local model = Instance.new("Model")
	model.Name = "Villager"
	local root = newPart("Root", Vector3.new(2, 5, 1) * s, Color3.new(), nil)
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = CFrame.new(pos.X, 2.5 * s, pos.Z)
	root.Parent = model
	model.PrimaryPart = root

	local leftLeg, rightLeg, leftArm, rightArm
	if isWoman then
		-- Long skirt hides the legs; it sways a little instead.
		fixed(model, root, "Skirt", Vector3.new(2.3, 2.6, 1.5) * s, CFrame.new(0, -1.2 * s, 0), cloth, Enum.Material.Fabric)
		fixed(model, root, "Apron", Vector3.new(1.4, 2.2, 0.1) * s, CFrame.new(0, -1.1 * s, -0.78 * s), WHITE, Enum.Material.Fabric)
		fixed(model, root, "Bodice", Vector3.new(1.8, 1.9, 0.9) * s, CFrame.new(0, 0.85 * s, 0), cloth:Lerp(BLACK, 0.3), Enum.Material.Fabric)
	else
		local breeches = if role == "Blacksmith" then Color3.fromRGB(70, 60, 50) else Color3.fromRGB(190, 170, 130)
		_, leftLeg = limb(model, root, "LeftLeg", Vector3.new(0.85, 2.4, 0.85) * s, Vector3.new(-0.5, -0.1, 0) * s, breeches)
		_, rightLeg = limb(model, root, "RightLeg", Vector3.new(0.85, 2.4, 0.85) * s, Vector3.new(0.5, -0.1, 0) * s, breeches)
		local coat = if role == "Drummer" then Color3.fromRGB(32, 45, 100) else cloth
		fixed(model, root, "Torso", Vector3.new(2, 2, 1) * s, CFrame.new(0, 0.9 * s, 0), coat, Enum.Material.Fabric)
		if role == "Blacksmith" then
			fixed(model, root, "LeatherApron", Vector3.new(1.6, 2.6, 0.1) * s, CFrame.new(0, 0.2 * s, -0.55 * s), Color3.fromRGB(90, 60, 35), Enum.Material.Leather)
		else
			fixed(model, root, "Waistcoat", Vector3.new(1.2, 1.6, 0.1) * s, CFrame.new(0, 0.9 * s, -0.52 * s), pick(CLOTH):Lerp(WHITE, 0.4), Enum.Material.Fabric)
		end
	end
	local armColor = if isWoman then cloth:Lerp(BLACK, 0.3) elseif role == "Blacksmith" then skin elseif role == "Drummer" then Color3.fromRGB(32, 45, 100) else cloth
	_, leftArm = limb(model, root, "LeftArm", Vector3.new(0.7, 1.9, 0.7) * s, Vector3.new(-1.3, 1.8, 0) * s, armColor, Enum.Material.Fabric)
	_, rightArm = limb(model, root, "RightArm", Vector3.new(0.7, 1.9, 0.7) * s, Vector3.new(1.3, 1.8, 0) * s, armColor, Enum.Material.Fabric)

	local headY = 2.4 * s
	fixed(model, root, "Head", Vector3.new(1.1, 1.1, 1.1) * s, CFrame.new(0, headY, 0), skin)
	if isWoman then
		fixed(model, root, "MobCap", Vector3.new(1.3, 0.6, 1.3) * s, CFrame.new(0, headY + 0.55 * s, 0.05), WHITE, Enum.Material.Fabric)
	elseif role == "Crier" then
		fixed(model, root, "Hat", Vector3.new(1.8, 0.35, 1.8), CFrame.new(0, headY + 0.65, 0), BLACK, Enum.Material.Fabric)
		fixed(model, root, "HatCrown", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, headY + 0.9, 0), BLACK, Enum.Material.Fabric)
		fixed(model, root, "HatTrim", Vector3.new(1.85, 0.12, 1.85), CFrame.new(0, headY + 0.55, 0), Color3.fromRGB(214, 172, 60), Enum.Material.Metal)
	elseif role == "Farmer" then
		fixed(model, root, "StrawHat", Vector3.new(2.2, 0.25, 2.2), CFrame.new(0, headY + 0.6, 0), Color3.fromRGB(215, 190, 120), Enum.Material.Fabric)
		fixed(model, root, "StrawCrown", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, headY + 0.85, 0), Color3.fromRGB(215, 190, 120), Enum.Material.Fabric)
	elseif role == "Drummer" then
		fixed(model, root, "Cap", Vector3.new(1.2, 0.6, 1.2) * s, CFrame.new(0, headY + 0.55 * s, 0), BLACK, Enum.Material.Fabric)
	else
		fixed(model, root, "Hair", Vector3.new(1.15, 0.45, 1.15) * s, CFrame.new(0, headY + 0.45 * s, 0.05), pick({ BLACK, Color3.fromRGB(110, 70, 40), Color3.fromRGB(200, 170, 110) }))
	end

	-- Role props.
	if role == "Farmer" then
		local fork = newPart("Pitchfork", Vector3.new(0.2, 6, 0.2), WOOD, Enum.Material.Wood)
		fork.CFrame = root.CFrame * CFrame.new(1.8, 0.8, -0.3)
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = fork
		w.Parent = fork
		fork.Parent = model
		fixed(model, root, "Tines", Vector3.new(0.9, 0.8, 0.15), CFrame.new(1.8, 4.1, -0.3), Color3.fromRGB(120, 120, 125), Enum.Material.Metal)
	elseif role == "Drummer" then
		local drum = newPart("Drum", Vector3.new(1.0, 1.4, 1.4) * s, Color3.fromRGB(180, 30, 35), Enum.Material.Wood)
		drum.Shape = Enum.PartType.Cylinder
		drum.CFrame = root.CFrame * CFrame.new(0, 0.2 * s, -0.95 * s) * CFrame.Angles(0, 0, math.rad(90))
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = drum
		w.Parent = drum
		drum.Parent = model
	elseif role == "Crier" then
		local bell = newPart("Bell", Vector3.new(0.7, 0.8, 0.7), Color3.fromRGB(214, 172, 60), Enum.Material.Metal)
		local w = Instance.new("Weld")
		w.Part0 = model:FindFirstChild("RightArm") :: BasePart
		w.Part1 = bell
		w.C0 = CFrame.new(0, -1.1, 0)
		bell.CFrame = (w.Part0 :: BasePart).CFrame * w.C0
		w.Parent = bell
		bell.Parent = model
	elseif role == "Woman" and math.random() < 0.5 then
		local basket = newPart("Basket", Vector3.new(1.4, 0.8, 1.0), Color3.fromRGB(170, 130, 70), Enum.Material.Fabric)
		local w = Instance.new("Weld")
		w.Part0 = model:FindFirstChild("LeftArm") :: BasePart
		w.Part1 = basket
		w.C0 = CFrame.new(0.3, -1.1, 0)
		basket.CFrame = (w.Part0 :: BasePart).CFrame * w.C0
		w.Parent = basket
		basket.Parent = model
	elseif role == "Blacksmith" then
		local hammer = newPart("Hammer", Vector3.new(0.2, 1.4, 0.2), WOOD, Enum.Material.Wood)
		local w = Instance.new("Weld")
		w.Part0 = model:FindFirstChild("RightArm") :: BasePart
		w.Part1 = hammer
		w.C0 = CFrame.new(0, -1.0, -0.6) * CFrame.Angles(math.rad(90), 0, 0)
		hammer.CFrame = (w.Part0 :: BasePart).CFrame * w.C0
		w.Parent = hammer
		hammer.Parent = model
		local head = newPart("HammerHead", Vector3.new(0.45, 0.45, 0.8), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
		local hw = Instance.new("WeldConstraint")
		head.CFrame = hammer.CFrame * CFrame.new(0, 0.7, 0)
		hw.Part0 = hammer
		hw.Part1 = head
		hw.Parent = head
		head.Parent = model
	end

	model.Parent = folder

	local speedByRole = { Child = 9, Crier = 4.5, Farmer = 5, Woman = 5, Man = 5.5 }
	return {
		Model = model,
		Root = root,
		LeftLeg = leftLeg,
		RightLeg = rightLeg,
		LeftArm = leftArm,
		RightArm = rightArm,
		Role = role,
		Speed = speedByRole[role] or 0,
		Target = nil,
		WaitUntil = os.clock() + math.random() * 4,
		Phase = math.random() * 10,
		NextTalk = os.clock() + 3 + math.random() * 12,
		Bubble = makeBubble(root, 4 * s),
		Scale = s,
		Facing = Vector3.new(0, 0, -1),
		Anchor = nil,
	}
end

local function buildChicken(pos: Vector3)
	local model = Instance.new("Model")
	model.Name = "Chicken"
	local root = newPart("Root", Vector3.new(0.8, 0.8, 1.1), Color3.fromRGB(245, 240, 230), Enum.Material.Fabric)
	root.Anchored = true
	root.CFrame = CFrame.new(pos.X, 0.65, pos.Z)
	root.Parent = model
	local head = newPart("Head", Vector3.new(0.45, 0.5, 0.45), Color3.fromRGB(245, 240, 230), Enum.Material.Fabric)
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = head
	w.C0 = CFrame.new(0, 0.45, -0.55)
	head.CFrame = root.CFrame * w.C0
	w.Parent = head
	head.Parent = model
	fixed(model, head :: any, "Comb", Vector3.new(0.12, 0.25, 0.3), CFrame.new(0, 0.3, 0), Color3.fromRGB(200, 30, 30))
	fixed(model, head :: any, "Beak", Vector3.new(0.15, 0.12, 0.25), CFrame.new(0, 0, -0.3), Color3.fromRGB(240, 170, 40))
	fixed(model, root, "Tail", Vector3.new(0.5, 0.6, 0.2), CFrame.new(0, 0.3, 0.6) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(230, 225, 215))
	for _, x in { -0.2, 0.2 } do
		fixed(model, root, "Leg", Vector3.new(0.1, 0.35, 0.1), CFrame.new(x, -0.55, 0), Color3.fromRGB(240, 170, 40))
	end
	model.Parent = folder
	table.insert(chickens, { Root = root, Target = pos, WaitUntil = 0, Head = w })
end

---------------------------------------------------------------------------
-- Behaviour
---------------------------------------------------------------------------

local function blocked(pos: Vector3, dir: Vector3): boolean
	return workspace:Raycast(Vector3.new(pos.X, 2, pos.Z), dir * 3, avoidParams) ~= nil
end

local function walk(v: Villager, dt: number, speed: number)
	local pos = v.Root.Position
	local target = v.Target :: Vector3
	local delta = flat(target - pos)
	if delta.Magnitude < 1 then
		v.Target = nil
		return
	end
	local dir = delta.Unit
	if blocked(pos, dir) then
		-- Try to sidestep; give up on this destination if boxed in.
		local side = Vector3.new(-dir.Z, 0, dir.X)
		if not blocked(pos, side) then
			dir = side
		elseif not blocked(pos, -side) then
			dir = -side
		else
			v.Target = nil
			return
		end
	end
	v.Facing = v.Facing:Lerp(dir, math.min(1, dt * 6))
	if v.Facing.Magnitude < 0.01 then
		v.Facing = dir
	end
	local newPos = pos + dir * speed * dt
	v.Root.CFrame = CFrame.lookAt(newPos, newPos + flat(v.Facing).Unit)

	-- Swing legs and arms.
	v.Phase += dt * speed * 1.4
	local swing = math.sin(v.Phase) * math.rad(math.min(45, speed * 4))
	if v.LeftLeg then
		v.LeftLeg.C0 = CFrame.new(v.LeftLeg.C0.Position) * CFrame.Angles(swing, 0, 0)
	end
	if v.RightLeg then
		v.RightLeg.C0 = CFrame.new(v.RightLeg.C0.Position) * CFrame.Angles(-swing, 0, 0)
	end
	if v.LeftArm then
		v.LeftArm.C0 = CFrame.new(v.LeftArm.C0.Position) * CFrame.Angles(-swing * 0.7, 0, 0)
	end
	if v.RightArm and v.Role ~= "Crier" then
		v.RightArm.C0 = CFrame.new(v.RightArm.C0.Position) * CFrame.Angles(swing * 0.7, 0, 0)
	end
end

local function standStill(v: Villager)
	for _, w in { v.LeftLeg, v.RightLeg, v.LeftArm, v.RightArm } do
		if w then
			w.C0 = CFrame.new(w.C0.Position)
		end
	end
end

local function sparks(pos: Vector3)
	for _ = 1, 5 do
		local p = newPart("Spark", Vector3.one * 0.2, Color3.fromRGB(255, 200, 80), Enum.Material.Neon)
		p.Anchored = true
		p.Position = pos
		p.Parent = folder
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 3
		TweenService:Create(p, TweenInfo.new(0.35), { Position = pos + offset, Transparency = 1 }):Play()
		Debris:AddItem(p, 0.4)
	end
end

local function updateVillager(v: Villager, dt: number, panic: boolean)
	local t = os.clock()
	local role = v.Role

	if role == "Blacksmith" then
		-- Hammer the anvil; pause for a rest now and then.
		v.Phase += dt * 5
		local beat = math.sin(v.Phase)
		if v.RightArm then
			v.RightArm.C0 = CFrame.new(v.RightArm.C0.Position) * CFrame.Angles(math.rad(70 + beat * 55), 0, 0)
		end
		if beat < -0.97 and t - (v.WaitUntil or 0) > 0.5 then
			v.WaitUntil = t
			sparks(v.Root.Position + v.Root.CFrame.LookVector * 1.6 + Vector3.new(0, -0.4, 0))
		end
	elseif role == "Drummer" then
		v.Phase += dt * (if panic then 14 else 8)
		if v.LeftArm and v.RightArm then
			v.LeftArm.C0 = CFrame.new(v.LeftArm.C0.Position) * CFrame.Angles(math.rad(50 + math.sin(v.Phase) * 25), 0, math.rad(-20))
			v.RightArm.C0 = CFrame.new(v.RightArm.C0.Position) * CFrame.Angles(math.rad(50 - math.sin(v.Phase) * 25), 0, math.rad(20))
		end
	else
		local speed = v.Speed * (if panic then 2 else 1)
		if v.Target then
			walk(v, dt, speed)
		elseif t >= v.WaitUntil then
			if panic and role ~= "Crier" then
				v.Target = pick(SHELTER) + Vector3.new(math.random(-4, 4), 0, math.random(-3, 3))
			elseif v.Anchor then
				v.Target = v.Anchor + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
			else
				v.Target = pick(WAYPOINTS) + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
			end
			v.WaitUntil = t + (if panic then 0.5 + math.random() * 1.5 else 2 + math.random() * 6)
		else
			standStill(v)
			if role == "Crier" and v.RightArm then
				-- Ring the bell.
				v.RightArm.C0 = CFrame.new(v.RightArm.C0.Position) * CFrame.Angles(math.rad(120 + math.sin(t * 14) * 20), 0, 0)
			end
		end
	end

	if t >= v.NextTalk then
		local line
		if role == "Crier" then
			line = pick(if panic then CRIER_PANIC else CRIER)
		elseif role == "Drummer" or role == "Blacksmith" then
			line = if panic then pick(PANIC) else nil
		else
			line = pick(if panic then PANIC else CHATTER)
		end
		if line then
			say(v, line, 3)
		end
		v.NextTalk = t + (if role == "Crier" then 7 else 9) + math.random() * (if panic then 6 else 18)
	end
end

local function updateChickens(dt: number)
	local t = os.clock()
	for _, c in chickens do
		local pos = c.Root.Position
		local delta = flat(c.Target - pos)
		if delta.Magnitude > 0.5 then
			local dir = delta.Unit
			local newPos = pos + dir * 4 * dt
			-- Bob as they waddle.
			local bob = math.abs(math.sin(t * 14)) * 0.15
			c.Root.CFrame = CFrame.lookAt(Vector3.new(newPos.X, 0.65 + bob, newPos.Z), Vector3.new(newPos.X, 0.65 + bob, newPos.Z) + dir)
			c.Head.C0 = CFrame.new(0, 0.45, -0.55)
		elseif t >= c.WaitUntil then
			c.Target = pos + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
			c.Target = Vector3.new(math.clamp(c.Target.X, -40, 40), 0, math.clamp(c.Target.Z, 95, 165))
			if blocked(pos, flat(c.Target - pos).Unit) then
				c.Target = pos
			end
			c.WaitUntil = t + 1 + math.random() * 4
		else
			-- Peck at the ground.
			local peck = math.max(0, math.sin(t * 10 + pos.X)) * 0.5
			c.Head.C0 = CFrame.new(0, 0.45 - peck, -0.55 - peck * 0.4) * CFrame.Angles(-peck * 1.5, 0, 0)
		end
	end
end

function Townsfolk.Init()
	local map = workspace:WaitForChild("Map")
	local cover = map:WaitForChild("Cover")
	local stores = map:WaitForChild("PowderStores")
	avoidParams.FilterDescendantsInstances = { cover, stores }
	-- Wait for the props (built just before the map is parented).
	local anvil = map:WaitForChild("Decor"):WaitForChild("Props"):WaitForChild("Anvil", 10) :: BasePart?

	folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = workspace

	local roles = { "Man", "Man", "Man", "Woman", "Woman", "Woman", "Woman", "Child", "Child", "Child", "Farmer", "Crier" }
	for _, role in roles do
		local start = pick(WAYPOINTS) + Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
		local v = buildVillager(role, start)
		if role == "Farmer" then
			v.Anchor = Vector3.new(-80, 0, 125)
		end
		table.insert(villagers, v)
	end

	if anvil then
		local smithPos = anvil.Position + Vector3.new(0, 0, -2)
		local smith = buildVillager("Blacksmith", smithPos)
		smith.Root.CFrame = CFrame.lookAt(Vector3.new(smithPos.X, smith.Root.Position.Y, smithPos.Z), Vector3.new(anvil.Position.X, smith.Root.Position.Y, anvil.Position.Z))
		table.insert(villagers, smith)
	end

	local drummer = buildVillager("Drummer", Vector3.new(-6, 0, 122))
	drummer.Root.CFrame = CFrame.lookAt(drummer.Root.Position, drummer.Root.Position + Vector3.new(0, 0, -1))
	table.insert(villagers, drummer)

	for _ = 1, 8 do
		buildChicken(Vector3.new(math.random(-35, 35), 0, math.random(145, 162)))
	end

	RunService.Heartbeat:Connect(function(dt)
		local panic = gameState:GetAttribute("Phase") == "Wave"
		for _, v in villagers do
			updateVillager(v, math.min(dt, 0.1), panic)
		end
		updateChickens(math.min(dt, 0.1))
	end)
end

return Townsfolk
