-- Walk animation for soldiers and armed townsfolk. The server moves each unit
-- by CFrame; here every client swings the leg welds (tagged "UnitLeg") based
-- on how fast the unit is actually moving. Purely visual, no network cost.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local UnitAnimator = {}

type LegState = { Weld: Weld, Hip: CFrame, Half: number, Sign: number }
type ModelState = { Root: BasePart, Legs: { LegState }, LastPos: Vector3, Phase: number, Swing: number }

local models: { [Model]: ModelState } = {}

local function track(weld: Instance)
	if not weld:IsA("Weld") then
		return
	end
	local model = weld:FindFirstAncestorOfClass("Model")
	local root = model and model:FindFirstChild("Root")
	local hip = weld:GetAttribute("Hip")
	local half = weld:GetAttribute("HalfLength")
	if not model or not root or not root:IsA("BasePart") or typeof(hip) ~= "CFrame" or typeof(half) ~= "number" then
		return
	end
	local state = models[model]
	if not state then
		state = { Root = root, Legs = {}, LastPos = root.Position, Phase = math.random() * 6, Swing = 0 }
		models[model] = state
	end
	local sign = if (weld.Part1 and weld.Part1.Name == "LeftLeg") then 1 else -1
	table.insert(state.Legs, { Weld = weld, Hip = hip, Half = half, Sign = sign })
end

function UnitAnimator.Init()
	for _, w in CollectionService:GetTagged("UnitLeg") do
		track(w)
	end
	CollectionService:GetInstanceAddedSignal("UnitLeg"):Connect(function(w)
		-- Attributes may arrive a moment after the tag.
		task.defer(track, w)
	end)

	RunService.RenderStepped:Connect(function(dt)
		if dt <= 0 then
			return
		end
		for model, state in models do
			if not model.Parent or not state.Root.Parent then
				models[model] = nil
				continue
			end
			local pos = state.Root.Position
			local delta = Vector3.new(pos.X - state.LastPos.X, 0, pos.Z - state.LastPos.Z)
			state.LastPos = pos
			local speed = delta.Magnitude / dt
			local walking = speed > 0.8 and not model:GetAttribute("Dead")
			-- Ease the stride in and out so starting/stopping looks natural.
			local targetSwing = if walking then math.rad(math.min(38, 10 + speed * 2)) else 0
			state.Swing += (targetSwing - state.Swing) * math.min(1, dt * 10)
			if walking then
				state.Phase += dt * math.clamp(speed, 4, 26) * 0.9
			end
			local angle = math.sin(state.Phase) * state.Swing
			for _, leg in state.Legs do
				if leg.Weld.Parent then
					leg.Weld.C0 = leg.Hip * CFrame.Angles(angle * leg.Sign, 0, 0) * CFrame.new(0, -leg.Half, 0)
				end
			end
		end
	end)
end

return UnitAnimator
