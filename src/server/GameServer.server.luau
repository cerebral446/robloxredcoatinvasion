-- Redcoat Invasion: main server script.
-- Builds the map, then runs the loop: intermission (shop) -> wave -> ...
-- until the powder stores fall, every player is down, or the final wave is won.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- Networking objects must exist before the other modules load.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in { "Fire", "Reload", "Melee", "Equip", "Ready", "Effect", "Announce", "Sprint" } do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
end
local purchaseRemote = Instance.new("RemoteFunction")
purchaseRemote.Name = "Purchase"
purchaseRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local gameState = Instance.new("Configuration")
gameState.Name = "GameState"
gameState:SetAttribute("Phase", "Waiting")
gameState:SetAttribute("Wave", 0)
gameState:SetAttribute("FinalWave", Config.Rounds.FinalWave)
gameState:SetAttribute("PhaseEnd", 0)
gameState:SetAttribute("EnemiesLeft", 0)
gameState:SetAttribute("StoresHealth", Config.Stores.MaxHealth)
gameState:SetAttribute("StoresMax", Config.Stores.MaxHealth)
gameState:SetAttribute("WaveName", "")
gameState.Parent = ReplicatedStorage

local effects = Instance.new("Folder")
effects.Name = "Effects"
effects.Parent = workspace

Players.CharacterAutoLoads = false

local FX = require(script.Parent:WaitForChild("FX"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Units = require(script.Parent:WaitForChild("Units"))
local PlayerManager = require(script.Parent:WaitForChild("PlayerManager"))

local map, stores = MapBuilder.Build()
Units.Init(map, stores, gameState)
PlayerManager.Init(gameState, function()
	local phase = gameState:GetAttribute("Phase")
	return phase == "Intermission" or phase == "Waiting"
end)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setPhase(phase: string, duration: number?)
	gameState:SetAttribute("Phase", phase)
	gameState:SetAttribute("PhaseEnd", if duration then now() + duration else 0)
end

local storesDestroyed = false
Units.OnStoresDestroyed = function()
	storesDestroyed = true
end

Units.OnKill = function(killer, unit)
	if unit.Team == "Red" and killer then
		PlayerManager.AddKill(killer, unit.Def.Bounty)
	elseif unit.Team == "Blue" and unit.Owner then
		PlayerManager.Sync(unit.Owner)
	end
end

-- Ready votes let players skip the rest of the intermission.
local ready: { [Player]: boolean } = {}
local readyRemote = remotes:WaitForChild("Ready") :: RemoteEvent
readyRemote.OnServerEvent:Connect(function(player)
	if gameState:GetAttribute("Phase") == "Intermission" then
		ready[player] = true
		player:SetAttribute("Ready", true)
	end
end)

local function allReady(): boolean
	local list = Players:GetPlayers()
	if #list == 0 then
		return false
	end
	for _, p in list do
		if not ready[p] then
			return false
		end
	end
	return true
end

local function clearReady()
	table.clear(ready)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Ready", false)
	end
end

local function anyoneAlive(): boolean
	for _, p in Players:GetPlayers() do
		if PlayerManager.IsAlive(p) then
			return true
		end
	end
	return false
end

local function respawnFallen()
	for _, p in Players:GetPlayers() do
		if not PlayerManager.IsAlive(p) then
			task.spawn(PlayerManager.Spawn, p)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	local phase = gameState:GetAttribute("Phase")
	if phase ~= "GameOver" and phase ~= "Victory" then
		task.wait(1)
		PlayerManager.Spawn(player)
		if phase == "Wave" then
			FX.Announce("You join the fight mid-battle!", nil, player)
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	ready[player] = nil
end)

RunService.Heartbeat:Connect(function(dt)
	Units.Step(math.min(dt, 0.1))
end)

---------------------------------------------------------------------------
-- Wave spawning
---------------------------------------------------------------------------

type SpawnEntry = { At: number, Run: () -> () }

local function edgePoint(spreadX: number): Vector3
	local x = (math.random() * 2 - 1) * spreadX
	return Vector3.new(x, 0, Config.Map.EnemySpawnZ + math.random() * 10)
end

local SOUTH = Vector3.new(0, 0, 1)

local function buildSpawnQueue(wave: number): { SpawnEntry }
	local def = Config.GetWave(wave)
	local queue: { SpawnEntry } = {}

	for i, formation in def.Formations do
		table.insert(queue, {
			At = (i - 1) * 9,
			Run = function()
				local lanes = { 0, -60, 60, -110, 110 }
				local x = lanes[((i - 1) % #lanes) + 1] + math.random(-8, 8)
				Units.SpawnFormation(formation, Vector3.new(x, 0, Config.Map.EnemySpawnZ), SOUTH)
			end,
		})
	end

	local function sprinkle(kind: string, count: number, startAt: number, interval: number, spreadX: number)
		for i = 1, count do
			table.insert(queue, {
				At = startAt + (i - 1) * interval + math.random() * 2,
				Run = function()
					Units.Spawn(kind, edgePoint(spreadX), SOUTH)
				end,
			})
		end
	end

	sprinkle("LightInfantry", def.LightInfantry, 4, 3, 140)
	sprinkle("Grenadier", def.Grenadier, 12, 6, 80)
	sprinkle("Dragoon", def.Dragoon, 20, 7, 120)

	local gunSpots = { -45, 45, -95, 95 }
	for i = 1, def.Cannon do
		table.insert(queue, {
			At = 2 + i,
			Run = function()
				local x = gunSpots[((i - 1) % #gunSpots) + 1]
				Units.Spawn("Cannon", Vector3.new(x, 0, Config.Map.NorthEdge + 14), SOUTH)
			end,
		})
	end

	table.sort(queue, function(a, b)
		return a.At < b.At
	end)
	return queue
end

---------------------------------------------------------------------------
-- Round flow
---------------------------------------------------------------------------

local function waitForPlayers()
	while #Players:GetPlayers() == 0 do
		task.wait(1)
	end
end

local function resetGame()
	Units.Clear()
	PlayerManager.ResetAll()
	storesDestroyed = false
	gameState:SetAttribute("StoresHealth", Config.Stores.MaxHealth)
	gameState:SetAttribute("StoresMax", Config.Stores.MaxHealth)
	gameState:SetAttribute("Wave", 0)
	gameState:SetAttribute("EnemiesLeft", 0)
	gameState:SetAttribute("WaveName", "")
end

local function intermission(duration: number)
	clearReady()
	setPhase("Intermission", duration)
	respawnFallen()
	PlayerManager.HealAll()
	local deadline = now() + duration
	while now() < deadline do
		if allReady() then
			break
		end
		task.wait(0.25)
	end
	clearReady()
end

-- Returns "Won" when every redcoat is dead, or "Lost".
local function runWave(wave: number): string
	local def = Config.GetWave(wave)
	gameState:SetAttribute("Wave", wave)
	gameState:SetAttribute("WaveName", def.Name or "")
	setPhase("Wave")
	Units.SetWave(wave)
	FX.Announce(("Wave %d%s"):format(wave, if def.Name then " - " .. def.Name else ""), Color3.fromRGB(255, 90, 80))

	local queue = buildSpawnQueue(wave)
	local start = now()
	local index = 1
	while true do
		local elapsed = now() - start
		while index <= #queue and queue[index].At <= elapsed do
			queue[index].Run()
			index += 1
		end

		local remaining = Units.Count("Red") + (#queue - index + 1)
		gameState:SetAttribute("EnemiesLeft", remaining)

		if storesDestroyed then
			return "Lost"
		end
		if #Players:GetPlayers() > 0 and not anyoneAlive() then
			return "Lost"
		end
		if remaining == 0 then
			return "Won"
		end
		task.wait(0.2)
	end
end

while true do
	resetGame()
	setPhase("Waiting")
	waitForPlayers()
	respawnFallen()

	local outcome = "Won"
	for wave = 1, Config.Rounds.FinalWave do
		intermission(if wave == 1 then Config.Rounds.FirstIntermission else Config.Rounds.IntermissionTime)
		outcome = runWave(wave)
		if outcome == "Lost" then
			break
		end
		for _, p in Players:GetPlayers() do
			PlayerManager.AddMoney(p, Config.Rounds.WaveClearBonus + wave * 10)
		end
		if wave < Config.Rounds.FinalWave then
			FX.Announce(("Wave %d repulsed! +$%d"):format(wave, Config.Rounds.WaveClearBonus + wave * 10), Color3.fromRGB(120, 200, 255))
		end
	end

	if outcome == "Won" then
		setPhase("Victory", Config.Rounds.GameOverTime)
		FX.Announce("VICTORY! The Regulars retreat to Boston!", Color3.fromRGB(120, 200, 255))
	else
		setPhase("GameOver", Config.Rounds.GameOverTime)
		local reason = if storesDestroyed then "The powder stores have fallen!" else "The militia has been routed!"
		FX.Announce(("%s Survived to wave %d."):format(reason, gameState:GetAttribute("Wave")), Color3.fromRGB(255, 90, 80))
	end
	task.wait(Config.Rounds.GameOverTime)
	Units.Clear()
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:Destroy()
			p.Character = nil
		end
	end
end
