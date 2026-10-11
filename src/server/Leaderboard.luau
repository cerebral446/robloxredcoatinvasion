-- All-time Endless leaderboard, saved with an OrderedDataStore.
--
-- Each player's best run is stored as one number so it sorts correctly:
-- wave * 1,000,000 + score (furthest wave first, then highest score).
-- If DataStores are unavailable (e.g. Studio without "Enable Studio Access to
-- API Services", or an unpublished place) it falls back to this server's
-- best runs so the board still works.
--
-- The current top runs are published as JSON on GameState."TopEndless".

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Leaderboard = {}

local STORE_NAME = "RedcoatEndlessBest_v1"
local TOP_COUNT = 10
local REFRESH_SECONDS = 60
local SCORE_SCALE = 1000000

type Entry = { UserId: number, Name: string, Wave: number, Score: number }

local gameState: Instance
local store: OrderedDataStore? = nil
local online = false
local sessionBest: { [number]: Entry } = {}
local nameCache: { [number]: string } = {}

local function encode(wave: number, score: number): number
	return math.floor(wave) * SCORE_SCALE + math.clamp(math.floor(score), 0, SCORE_SCALE - 1)
end

local function decode(value: number): (number, number)
	return value // SCORE_SCALE, value % SCORE_SCALE
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and name then name else ("Player " .. userId)
	nameCache[userId] = result
	return result
end

local function sessionTop(): { Entry }
	local list = {}
	for _, e in sessionBest do
		table.insert(list, e)
	end
	table.sort(list, function(a, b)
		return encode(a.Wave, a.Score) > encode(b.Wave, b.Score)
	end)
	while #list > TOP_COUNT do
		table.remove(list)
	end
	return list
end

local function publish(entries: { Entry }, source: string)
	local rows = {}
	for _, e in entries do
		table.insert(rows, { name = e.Name, wave = e.Wave, score = e.Score })
	end
	gameState:SetAttribute("TopEndless", HttpService:JSONEncode(rows))
	gameState:SetAttribute("TopEndlessSource", source)
end

function Leaderboard.Refresh()
	if not online or not store then
		publish(sessionTop(), "server")
		return
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, TOP_COUNT)
	end)
	if not ok then
		warn("[Leaderboard] Could not read the all-time board:", pages)
		publish(sessionTop(), "server")
		return
	end
	local entries = {}
	for _, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			local wave, score = decode(item.value)
			table.insert(entries, { UserId = userId, Name = nameFor(userId), Wave = wave, Score = score })
		end
	end
	publish(entries, "global")
end

-- Record an Endless run for each player. `wave` is the wave they reached.
function Leaderboard.RecordRun(results: { { Player: Player, Wave: number, Score: number } })
	for _, r in results do
		local userId = r.Player.UserId
		local value = encode(r.Wave, r.Score)
		nameCache[userId] = r.Player.DisplayName

		local prev = sessionBest[userId]
		if not prev or encode(prev.Wave, prev.Score) < value then
			sessionBest[userId] = { UserId = userId, Name = r.Player.DisplayName, Wave = r.Wave, Score = r.Score }
		end
		if r.Player.Parent then
			local best = r.Player:GetAttribute("BestWave") or 0
			r.Player:SetAttribute("BestWave", math.max(best, r.Wave))
		end

		if online and store then
			-- Test players in Studio have negative ids; don't save those.
			if userId > 0 then
				local ok, err = pcall(function()
					(store :: OrderedDataStore):UpdateAsync(tostring(userId), function(old)
						if old and old >= value then
							return nil -- keep the better existing record
						end
						return value
					end)
				end)
				if not ok then
					warn("[Leaderboard] Could not save run:", err)
				end
			end
		end
	end
	Leaderboard.Refresh()
end

local function loadPersonalBest(player: Player)
	if not online or not store or player.UserId <= 0 then
		return
	end
	local ok, value = pcall(function()
		return (store :: OrderedDataStore):GetAsync(tostring(player.UserId))
	end)
	if ok and typeof(value) == "number" and player.Parent then
		local wave = decode(value)
		player:SetAttribute("BestWave", math.max(player:GetAttribute("BestWave") or 0, wave))
	end
end

function Leaderboard.Init(state: Instance)
	gameState = state
	gameState:SetAttribute("TopEndless", "[]")
	gameState:SetAttribute("TopEndlessSource", "server")

	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		-- A cheap read tells us whether API access actually works here.
		local probe = pcall(function()
			return (store :: OrderedDataStore):GetSortedAsync(false, 1)
		end)
		online = probe
	end
	if not online then
		warn("[Leaderboard] DataStores unavailable; showing this server's best runs only. "
			.. "Publish the place and enable 'Studio Access to API Services' to save all-time scores.")
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadPersonalBest, player)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(loadPersonalBest, p)
	end

	task.spawn(function()
		while true do
			Leaderboard.Refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return Leaderboard
