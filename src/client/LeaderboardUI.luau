-- Live leaderboard (press L) and the Campaign / Endless mode vote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LeaderboardUI = {}

local player = Players.LocalPlayer
local gameState = ReplicatedStorage:WaitForChild("GameState")
local voteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VoteMode") :: RemoteEvent

local PARCHMENT = Color3.fromRGB(236, 224, 196)
local INK = Color3.fromRGB(45, 32, 22)
local RED = Color3.fromRGB(190, 40, 35)
local BLUE = Color3.fromRGB(40, 70, 140)
local FADED = Color3.fromRGB(140, 125, 105)
local FONT = Enum.Font.Antique
local FONT_BOLD = Enum.Font.Garamond

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(r: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		Parent = parent,
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = INK,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base)
end

---------------------------------------------------------------------------
-- Leaderboard panel
---------------------------------------------------------------------------

local panel: Frame
local liveList: Frame
local topList: Frame
local topTitle: TextLabel
local modeLabel: TextLabel
local bestLabel: TextLabel
local visible = true

local ROW_HEIGHT = 20

local function clearRows(list: Frame)
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

-- columns: { text, widthScale, alignRight? }
local function row(list: Frame, order: number, columns: { { any } }, color: Color3, bold: boolean?)
	local r = new("Frame", {
		Parent = list,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = if order % 2 == 0 then 1 else 0.85,
		BackgroundColor3 = Color3.fromRGB(200, 185, 155),
		BorderSizePixel = 0,
	})
	local x = 0
	for _, col in columns do
		local width = col[2] :: number
		text(r, {
			Position = UDim2.new(x, 4, 0, 1),
			Size = UDim2.new(width, -8, 1, -2),
			Text = tostring(col[1]),
			TextColor3 = color,
			Font = if bold then FONT_BOLD else FONT,
			TextXAlignment = if col[3] then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		})
		x += width
	end
end

local function refreshLive()
	clearRows(liveList)
	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		return (a:GetAttribute("Score") or 0) > (b:GetAttribute("Score") or 0)
	end)
	row(liveList, 0, { { "#", 0.1 }, { "Militia", 0.46 }, { "Score", 0.24, true }, { "Kills", 0.2, true } }, FADED, true)
	for i, p in list do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local alive = hum ~= nil and hum.Health > 0
		local name = p.DisplayName .. (if alive then "" else " (fallen)")
		local color = if p == player then BLUE elseif alive then INK else FADED
		row(liveList, i, {
			{ i, 0.1 },
			{ name, 0.46 },
			{ p:GetAttribute("Score") or 0, 0.24, true },
			{ p:GetAttribute("Kills") or 0, 0.2, true },
		}, color, p == player)
	end
end

local function refreshTop()
	clearRows(topList)
	local source = gameState:GetAttribute("TopEndlessSource")
	topTitle.Text = if source == "global" then "All-time Endless" else "Endless: best on this server"
	local ok, rows = pcall(HttpService.JSONDecode, HttpService, gameState:GetAttribute("TopEndless") or "[]")
	if not ok or typeof(rows) ~= "table" or #rows == 0 then
		row(topList, 1, { { "No Endless runs yet. Be the first!", 1 } }, FADED)
		return
	end
	row(topList, 0, { { "#", 0.1 }, { "Name", 0.46 }, { "Wave", 0.2, true }, { "Score", 0.24, true } }, FADED, true)
	for i, r in rows do
		local me = r.name == player.DisplayName
		row(topList, i, { { i, 0.1 }, { r.name, 0.46 }, { r.wave, 0.2, true }, { r.score, 0.24, true } }, if me then BLUE elseif i == 1 then RED else INK, i == 1 or me)
	end
end

local function refreshHeader()
	local mode = gameState:GetAttribute("Mode") or "Campaign"
	modeLabel.Text = if mode == "Endless" then "Mode: Endless" else ("Mode: Campaign (%d waves)"):format(gameState:GetAttribute("FinalWave") or 15)
	local best = player:GetAttribute("BestWave") or 0
	bestLabel.Text = if best > 0 then ("Your best Endless run: wave %d"):format(best) else ""
end

local function list(parent: Instance, order: number): Frame
	return new("Frame", {
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, { new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
end

local function buildPanel(gui: ScreenGui)
	panel = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 150),
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = PARCHMENT,
		BackgroundTransparency = 0.08,
	}, {
		corner(8),
		new("UIStroke", { Color = INK, Thickness = 3 }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }),
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	text(panel, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), Font = FONT_BOLD, Text = "Leaderboard  (L)", TextXAlignment = Enum.TextXAlignment.Center })
	modeLabel = text(panel, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center })
	text(panel, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 20), Font = FONT_BOLD, Text = "This battle" })
	liveList = list(panel, 4)
	topTitle = text(panel, { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 20), Font = FONT_BOLD, Text = "All-time Endless" })
	topList = list(panel, 6)
	bestLabel = text(panel, { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = BLUE })
end

---------------------------------------------------------------------------
-- Mode vote
---------------------------------------------------------------------------

local votePanel: Frame
local voteButtons: { [string]: TextButton } = {}

local function buildVote(gui: ScreenGui)
	votePanel = new("Frame", {
		Parent = gui,
		Position = UDim2.new(0, 16, 0, 150),
		Size = UDim2.fromOffset(380, 96),
		BackgroundColor3 = PARCHMENT,
		BackgroundTransparency = 0.05,
		Visible = false,
	}, { corner(8), new("UIStroke", { Color = INK, Thickness = 3 }) })
	text(votePanel, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 22),
		Font = FONT_BOLD,
		Text = "Vote: how long will you hold out?",
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	for i, mode in { "Campaign", "Endless" } do
		local b = new("TextButton", {
			Parent = votePanel,
			Position = UDim2.new((i - 1) * 0.5, 12, 0, 34),
			Size = UDim2.new(0.5, -18, 0, 50),
			BackgroundColor3 = if mode == "Endless" then RED else BLUE,
			TextColor3 = Color3.new(1, 1, 1),
			Font = FONT_BOLD,
			TextScaled = true,
			Text = mode,
		}, { corner(6), new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
		b.Activated:Connect(function()
			voteRemote:FireServer(mode)
		end)
		voteButtons[mode] = b
	end
end

local function refreshVote()
	local phase = gameState:GetAttribute("Phase")
	local open = not gameState:GetAttribute("ModeLocked") and (phase == "Waiting" or phase == "Intermission")
	votePanel.Visible = open
	if not open then
		return
	end
	local leading = gameState:GetAttribute("Mode")
	local mine = player:GetAttribute("ModeVote")
	local counts = {
		Campaign = gameState:GetAttribute("VotesCampaign") or 0,
		Endless = gameState:GetAttribute("VotesEndless") or 0,
	}
	local labels = { Campaign = "Campaign: 15 waves", Endless = "Endless + leaderboard" }
	for mode, b in voteButtons do
		b.Text = ("%s%s\n%d vote%s"):format(if mine == mode then "> " else "", labels[mode], counts[mode], if counts[mode] == 1 then "" else "s")
		b.BackgroundTransparency = if leading == mode then 0 else 0.45
	end
end

---------------------------------------------------------------------------

function LeaderboardUI.Init()
	local gui = new("ScreenGui", {
		Name = "Leaderboard",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildPanel(gui)
	buildVote(gui)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.L then
			visible = not visible
			panel.Visible = visible
		end
	end)

	gameState:GetAttributeChangedSignal("TopEndless"):Connect(refreshTop)
	gameState:GetAttributeChangedSignal("TopEndlessSource"):Connect(refreshTop)
	refreshTop()

	task.spawn(function()
		while true do
			refreshLive()
			refreshHeader()
			refreshVote()
			task.wait(0.5)
		end
	end)
end

return LeaderboardUI
