-- Draws the effects the server reports: musket smoke, tracers, grenades,
-- explosions and cannon fire. Everything here is local and purely cosmetic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Effects = {}

local folder = workspace:WaitForChild("Effects")

-- Built-in engine sounds (always available, no uploads required).
local SOUNDS = {
	Musket = "rbxasset://sounds/Rocket shot.wav",
	Slash = "rbxasset://sounds/swordslash.wav",
	Hit = "rbxasset://sounds/collide.wav",
}

local function sound(id: string, pos: Vector3?, volume: number?, pitch: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	if pos then
		local att = Instance.new("Attachment")
		att.WorldPosition = pos
		att.Parent = workspace.Terrain
		s.RollOffMinDistance = 20
		s.RollOffMaxDistance = 250
		s.Parent = att
		s:Play()
		Debris:AddItem(att, 3)
	else
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 3)
	end
end

local function basicPart(size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	return p
end

local function fadeOut(p: BasePart, duration: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, duration + 0.1)
end

local function smoke(pos: Vector3, size: number, duration: number)
	local puff = basicPart(Vector3.one * size, Color3.fromRGB(225, 225, 220))
	puff.Shape = Enum.PartType.Ball
	puff.Transparency = 0.25
	puff.Position = pos
	puff.Parent = folder
	fadeOut(puff, duration, Vector3.one * size * 3)
	TweenService:Create(puff, TweenInfo.new(duration), { Position = pos + Vector3.new(math.random() - 0.5, 2, math.random() - 0.5) }):Play()
end

local function tracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local line = basicPart(Vector3.new(0.15, 0.15, length), color, Enum.Material.Neon)
	line.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	line.Transparency = 0.2
	line.Parent = folder
	fadeOut(line, 0.18)
end

local function shot(from: Vector3, ends: { Vector3 }, team: string)
	local flash = basicPart(Vector3.one * 1.2, Color3.fromRGB(255, 200, 90), Enum.Material.Neon)
	flash.Shape = Enum.PartType.Ball
	flash.Position = from
	flash.Parent = folder
	fadeOut(flash, 0.08)
	smoke(from, 2, 1.4)
	local color = if team == "Red" then Color3.fromRGB(255, 170, 120) else Color3.fromRGB(255, 240, 180)
	for _, e in ends do
		tracer(from, e, color)
	end
	sound(SOUNDS.Musket, from, 0.6, 0.75 + math.random() * 0.2)
end

local function hit(pos: Vector3, flesh: boolean)
	local color = if flesh then Color3.fromRGB(150, 20, 20) else Color3.fromRGB(150, 130, 110)
	for _ = 1, 3 do
		local bit = basicPart(Vector3.one * 0.4, color)
		bit.Position = pos
		bit.Parent = folder
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 3
		TweenService:Create(bit, TweenInfo.new(0.35), { Position = pos + offset, Transparency = 1 }):Play()
		Debris:AddItem(bit, 0.4)
	end
end

local function marker(pos: Vector3, radius: number, duration: number)
	local ring = basicPart(Vector3.new(0.2, radius * 2, radius * 2), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(pos.X, 0.25, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.75
	ring.Parent = folder
	-- Pulse while counting down.
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.5 }):Play()
	Debris:AddItem(ring, duration)
end

local function cannonWarn(from: Vector3, to: Vector3, duration: number)
	local length = (to - from).Magnitude
	local line = basicPart(Vector3.new(3, 0.1, length), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	line.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	line.Transparency = 0.8
	line.Parent = folder
	TweenService:Create(line, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Transparency = 0.45 }):Play()
	Debris:AddItem(line, duration)
end

local function projectile(from: Vector3, to: Vector3, duration: number, size: number, arc: number)
	local ball = basicPart(Vector3.one * size, Color3.fromRGB(30, 30, 30), Enum.Material.Metal)
	ball.Shape = Enum.PartType.Ball
	ball.Position = from
	ball.Parent = folder
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - start) / duration)
		local pos = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * arc, 0)
		ball.Position = pos
		if t >= 1 then
			conn:Disconnect()
			ball:Destroy()
		end
	end)
end

local function explosion(pos: Vector3, radius: number)
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = radius
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.Parent = folder
	for _ = 1, 3 do
		smoke(pos + Vector3.new(math.random() - 0.5, 1, math.random() - 0.5) * radius * 0.4, radius * 0.5, 2)
	end
	-- Big blasts leave the ground burning for a few seconds.
	if radius >= 6 then
		local scorch = basicPart(Vector3.new(0.1, radius * 1.2, radius * 1.2), Color3.fromRGB(35, 30, 25))
		scorch.Shape = Enum.PartType.Cylinder
		scorch.CFrame = CFrame.new(pos.X, 0.22, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		scorch.Transparency = 0.25
		scorch.Parent = folder
		local flame = basicPart(Vector3.one * 0.5, Color3.new())
		flame.Transparency = 1
		flame.Position = Vector3.new(pos.X, 0.8, pos.Z)
		flame.Parent = folder
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 120, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 210, 90)
		fire.Parent = flame
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 50)
		light.Range = 14
		light.Brightness = 2
		light.Parent = flame
		task.delay(6, function()
			fire.Enabled = false
			TweenService:Create(light, TweenInfo.new(1.5), { Brightness = 0 }):Play()
			TweenService:Create(scorch, TweenInfo.new(4), { Transparency = 1 }):Play()
		end)
		Debris:AddItem(flame, 9)
		Debris:AddItem(scorch, 11)
	end
end

local function slash(pos: Vector3, dir: Vector3)
	local arc = basicPart(Vector3.new(6, 0.2, 1), Color3.fromRGB(240, 240, 255), Enum.Material.Neon)
	arc.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0.5, -3)
	arc.Transparency = 0.3
	arc.Parent = folder
	fadeOut(arc, 0.2)
	sound(SOUNDS.Slash, pos, 0.5)
end

-- Make every tagged flame light flicker.
local function startFlicker()
	local t0 = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		for i, light in CollectionService:GetTagged("Flicker") do
			if light:IsA("PointLight") then
				local base = light:GetAttribute("BaseBrightness") or 2
				local n = math.noise(t * 3.5, i * 1.7) * 0.6 + math.sin(t * 11 + i) * 0.12
				light.Brightness = base * (0.85 + n)
			end
		end
	end)
end

function Effects.Init()
	startFlicker()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Effect") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Shot" then
			shot(...)
		elseif kind == "Hit" then
			hit(...)
		elseif kind == "Grenade" then
			local from, to, duration = ...
			projectile(from, to, duration, 0.9, 10)
		elseif kind == "Cannonball" then
			local from, to, duration = ...
			projectile(from, to, duration, 1.3, 0)
			sound(SOUNDS.Musket, from, 1, 0.4)
		elseif kind == "Explosion" then
			explosion(...)
		elseif kind == "Marker" then
			marker(...)
		elseif kind == "CannonWarn" then
			cannonWarn(...)
		elseif kind == "Slash" then
			slash(...)
		end
	end)
end

return Effects
