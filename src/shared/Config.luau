-- Shared tuning data for Redcoat Invasion.
-- Everything gameplay-related that you may want to tweak lives here.

local Config = {}

Config.GameName = "Redcoat Invasion"

-- Map layout (studs). Enemies enter from the north (negative Z) and march
-- south toward the powder stores in the village (positive Z).
Config.Map = {
	HalfWidth = 160,
	NorthEdge = -230,
	SouthEdge = 170,
	EnemySpawnZ = -215,
	StoresPosition = Vector3.new(0, 0, 135),
	PlayerSpawn = Vector3.new(0, 3, 105),
}

-- Height that musket balls travel at. Cover taller than this blocks shots.
Config.ShotHeight = 3

Config.Rounds = {
	IntermissionTime = 25, -- seconds of shopping between waves
	FirstIntermission = 15,
	FinalWave = 15, -- survive this wave to win
	GameOverTime = 12,
	KillReward = 10,
	WaveClearBonus = 75,
}

Config.Stores = {
	MaxHealth = 1000,
	RepairCost = 100,
	RepairAmount = 250,
}

Config.Player = {
	MaxHealth = 100,
	WalkSpeed = 18,
	SprintSpeed = 28, -- hold Shift
	ReloadWalkSpeed = 11,
	ReloadSprintSpeed = 17,
	StartingMoney = 0,
}

-- Player weapons. Spread is the max angle (degrees) a ball strays from aim.
export type WeaponDef = {
	Name: string,
	Order: number,
	Price: number,
	Damage: number,
	Range: number,
	Spread: number,
	Pellets: number,
	Capacity: number,
	ReloadTime: number,
	FireCooldown: number,
	Description: string,
}

Config.Weapons = {
	Musket = {
		Name = "Musket",
		Order = 1,
		Price = 0,
		Damage = 60,
		Range = 110,
		Spread = 4,
		Pellets = 1,
		Capacity = 1,
		ReloadTime = 2.6,
		FireCooldown = 0.2,
		Description = "Brown Bess style smoothbore. Reliable.",
	},
	Pistols = {
		Name = "Brace of Pistols",
		Order = 2,
		Price = 200,
		Damage = 45,
		Range = 70,
		Spread = 6,
		Pellets = 1,
		Capacity = 2,
		ReloadTime = 2.4,
		FireCooldown = 0.25,
		Description = "Two shots before reloading. Short ranged.",
	},
	Blunderbuss = {
		Name = "Blunderbuss",
		Order = 3,
		Price = 300,
		Damage = 30,
		Range = 50,
		Spread = 14,
		Pellets = 6,
		Capacity = 1,
		ReloadTime = 3.0,
		FireCooldown = 0.2,
		Description = "Fires a handful of shot. Devastating up close.",
	},
	LongRifle = {
		Name = "Long Rifle",
		Order = 4,
		Price = 450,
		Damage = 140,
		Range = 200,
		Spread = 0.8,
		Pellets = 1,
		Capacity = 1,
		ReloadTime = 3.6,
		FireCooldown = 0.2,
		Description = "Pennsylvania rifle. Deadly accurate, slow to load.",
	},
} :: { [string]: WeaponDef }

Config.Melee = {
	Damage = 70,
	Range = 8,
	ArcDegrees = 100,
	Cooldown = 1.0,
}

-- Upgrades: each level costs BaseCost * level.
export type UpgradeDef = {
	Name: string,
	Order: number,
	MaxLevel: number,
	BaseCost: number,
	PerLevel: number,
	Description: string,
}

Config.Upgrades = {
	Reload = { Name = "Quick Loading", Order = 1, MaxLevel = 5, BaseCost = 60, PerLevel = 0.12, Description = "-12% reload time per level" },
	Accuracy = { Name = "Marksmanship", Order = 2, MaxLevel = 5, BaseCost = 50, PerLevel = 0.15, Description = "-15% spread per level" },
	Damage = { Name = "Heavy Charge", Order = 3, MaxLevel = 5, BaseCost = 70, PerLevel = 0.12, Description = "+12% damage per level" },
	Health = { Name = "Toughness", Order = 4, MaxLevel = 5, BaseCost = 50, PerLevel = 25, Description = "+25 max health per level" },
	Speed = { Name = "Fleet Foot", Order = 5, MaxLevel = 3, BaseCost = 60, PerLevel = 2, Description = "+2 walk speed per level" },
} :: { [string]: UpgradeDef }

Config.Allies = {
	HireCost = 150,
	MaxPerPlayer = 4,
	-- Minutemen spread out in a loose ring around their player.
	FollowRadius = { 7, 15 },
	CatchUpSpeed = 26, -- when they fall far behind
	ShuffleTime = { 6, 12 }, -- seconds between picking a new spot
}

-- Boss generals: famous British commanders of the American War of
-- Independence. One rides out every `Every` waves, in this order (repeating).
Config.Boss = {
	Every = 10,
	HealthPerExtraPlayer = 0.5, -- +50% health for each player beyond the first
	PistolShots = 3,
	AuraRadius = 70, -- redcoats near the general reload faster
	AuraReloadMultiplier = 0.6,
	SummonEvery = 18, -- seconds between calls for reinforcements
	SummonCap = 90, -- no summons while this many redcoats are on the field
	ChargeEvery = 14,
	ChargeRange = 30,
	ChargeSpeed = 26,
	ChargeDamage = 40,
	KeepDistance = 35, -- backs away from militia closer than this
	DefeatBonus = 200, -- money and score for every player when he falls
	Generals = {
		{ Name = "General Thomas Gage", Title = "Governor of Massachusetts Bay", Quote = "Seize the rebels' powder!" },
		{ Name = "General Sir William Howe", Title = "Victor of Bunker Hill", Quote = "Fix bayonets and advance!" },
		{ Name = "General John Burgoyne", Title = "\"Gentleman Johnny\"", Quote = "This army must not retreat!" },
		{ Name = "General Sir Henry Clinton", Title = "Commander-in-Chief, North America", Quote = "Crush this rebellion!" },
		{ Name = "General Charles, Lord Cornwallis", Title = "The Earl", Quote = "Show these farmers no quarter!" },
	},
}

function Config.GetGeneral(wave: number): { Name: string, Title: string, Quote: string }?
	if wave < Config.Boss.Every or wave % Config.Boss.Every ~= 0 then
		return nil
	end
	local list = Config.Boss.Generals
	return list[((wave // Config.Boss.Every - 1) % #list) + 1]
end

-- Armed townsfolk respawned in the village every intermission.
Config.Townsfolk = {
	Roster = { "Townsman", "Townsman", "Townsman", "Townswoman", "Townswoman", "Townswoman", "Farmer" },
	-- Village bounds they wander within; StockadeZ is the line they defend.
	MinX = -85,
	MaxX = 85,
	MinZ = 95,
	MaxZ = 165,
	StockadeZ = 91,
	StockadeGaps = { -44, 0, 44 }, -- x positions of the openings in the stakes
	Shouts = { "For liberty!", "Get off my land!", "Huzzah!", "Leave us be!", "Not in my town!" },
}

-- Unit definitions shared by redcoats and hired militia.
export type UnitDef = {
	DisplayName: string,
	Team: string,
	Health: number,
	Speed: number,
	Attack: string, -- "Musket" | "Grenade" | "Sabre" | "Cannon"
	Damage: number,
	Range: number,
	Reload: number,
	Spread: number,
	AimTime: number,
	Bounty: number,
	CoatColor: Color3,
	Hat: string, -- "Tricorne" | "Bearskin" | "Helmet" | "Cap" | "MobCap" | "StrawHat" | "None"
	Scale: number?,
	Civilian: boolean?, -- armed townsfolk: stay in the village, defend from the stockade
	Boss: boolean?,
	Outfit: string?, -- civilians: "Man" | "Woman" | "Farmer"
}

Config.Units = {
	Regular = {
		DisplayName = "Redcoat",
		Team = "Red",
		Health = 100,
		Speed = 7,
		Attack = "Musket",
		Damage = 25,
		Range = 85,
		Reload = 5.5,
		Spread = 5,
		AimTime = 1.0,
		Bounty = 10,
		CoatColor = Color3.fromRGB(178, 34, 34),
		Hat = "Tricorne",
	},
	LightInfantry = {
		DisplayName = "Light Infantry",
		Team = "Red",
		Health = 70,
		Speed = 13,
		Attack = "Musket",
		Damage = 20,
		Range = 70,
		Reload = 4.0,
		Spread = 6,
		AimTime = 0.8,
		Bounty = 12,
		CoatColor = Color3.fromRGB(200, 60, 50),
		Hat = "Cap",
	},
	Grenadier = {
		DisplayName = "Grenadier",
		Team = "Red",
		Health = 200,
		Speed = 6,
		Attack = "Grenade",
		Damage = 45,
		Range = 55,
		Reload = 6.0,
		Spread = 0,
		AimTime = 0.6,
		Bounty = 25,
		CoatColor = Color3.fromRGB(150, 20, 25),
		Hat = "Bearskin",
		Scale = 1.15,
	},
	Officer = {
		DisplayName = "Officer",
		Team = "Red",
		Health = 130,
		Speed = 8,
		Attack = "Musket",
		Damage = 30,
		Range = 60,
		Reload = 3.0,
		Spread = 4,
		AimTime = 0.6,
		Bounty = 40,
		CoatColor = Color3.fromRGB(220, 20, 40),
		Hat = "Tricorne",
	},
	Dragoon = {
		DisplayName = "Dragoon",
		Team = "Red",
		Health = 160,
		Speed = 22,
		Attack = "Sabre",
		Damage = 35,
		Range = 5,
		Reload = 1.4,
		Spread = 0,
		AimTime = 0,
		Bounty = 30,
		CoatColor = Color3.fromRGB(170, 30, 30),
		Hat = "Helmet",
	},
	Cannon = {
		DisplayName = "Field Gun",
		Team = "Red",
		Health = 350,
		Speed = 0,
		Attack = "Cannon",
		Damage = 80,
		Range = 400,
		Reload = 9.0,
		Spread = 3,
		AimTime = 1.6,
		Bounty = 60,
		CoatColor = Color3.fromRGB(178, 34, 34),
		Hat = "None",
	},
	Militia = {
		DisplayName = "Minuteman",
		Team = "Blue",
		Health = 100,
		Speed = 14,
		Attack = "Musket",
		Damage = 50,
		Range = 90,
		Reload = 4.5,
		Spread = 4,
		AimTime = 0.5,
		Bounty = 0,
		CoatColor = Color3.fromRGB(32, 45, 100), -- Continental blue
		Hat = "Tricorne",
	},
	-- Boss: a mounted British general every Config.Boss.Every waves.
	General = {
		DisplayName = "General",
		Team = "Red",
		Health = 1500,
		Speed = 9,
		Attack = "Musket", -- fires a brace of pistols (3 quick shots)
		Damage = 22,
		Range = 70,
		Reload = 2.6,
		Spread = 7,
		AimTime = 0.6,
		Bounty = 500,
		CoatColor = Color3.fromRGB(205, 20, 35),
		Hat = "Tricorne",
		Boss = true,
	},
	-- Armed townsfolk who defend their homes.
	Townsman = {
		DisplayName = "Townsman",
		Team = "Blue",
		Health = 70,
		Speed = 7,
		Attack = "Musket",
		Damage = 35,
		Range = 75,
		Reload = 7,
		Spread = 6,
		AimTime = 0.8,
		Bounty = 0,
		CoatColor = Color3.fromRGB(110, 75, 50),
		Hat = "Tricorne",
		Civilian = true,
		Outfit = "Man",
	},
	Townswoman = {
		DisplayName = "Townswoman",
		Team = "Blue",
		Health = 70,
		Speed = 7,
		Attack = "Musket",
		Damage = 35,
		Range = 75,
		Reload = 7,
		Spread = 6,
		AimTime = 0.8,
		Bounty = 0,
		CoatColor = Color3.fromRGB(70, 90, 60),
		Hat = "MobCap",
		Civilian = true,
		Outfit = "Woman",
	},
	Farmer = {
		DisplayName = "Farmer",
		Team = "Blue",
		Health = 85,
		Speed = 7,
		Attack = "Musket",
		Damage = 40,
		Range = 75,
		Reload = 7.5,
		Spread = 5,
		AimTime = 0.8,
		Bounty = 0,
		CoatColor = Color3.fromRGB(150, 130, 100),
		Hat = "StrawHat",
		Civilian = true,
		Outfit = "Farmer",
	},
} :: { [string]: UnitDef }

-- Officers make nearby redcoats reload faster.
Config.OfficerAura = { Radius = 35, ReloadMultiplier = 0.75 }

-- Formations break and scatter when an enemy gets this close to any soldier
-- in the line, or when the line drops below BreakStrength of its starting size.
-- Scattered soldiers run for ScatterTime seconds, then fight on their own.
Config.Formation = {
	BreakDistance = 22,
	BreakStrength = 0.5,
	ScatterTime = { 1.5, 3 },
	ScatterSpeedMultiplier = 1.8,
}

-- Musket-armed soldiers stab with the bayonet when a foe is in arm's reach.
Config.Bayonet = { Range = 5, Damage = 20, Cooldown = 1.5 }

-- Early waves are gentle: redcoats hit softer, miss more, reload slower,
-- take longer to aim and have less health. They reach full strength at
-- FullStrengthWave. Values are multipliers (AimBonus is extra seconds).
Config.Difficulty = {
	FullStrengthWave = 8,
	FirstWave = { Damage = 0.35, Spread = 2.2, Reload = 1.6, Health = 0.6, AimBonus = 0.5 },
}

function Config.GetDifficulty(wave: number): { Damage: number, Spread: number, Reload: number, Health: number, AimBonus: number }
	local first = Config.Difficulty.FirstWave
	local t = math.clamp((wave - 1) / math.max(1, Config.Difficulty.FullStrengthWave - 1), 0, 1)
	local function lerp(a: number, b: number): number
		return a + (b - a) * t
	end
	-- Endless: past the campaign's last wave the Regulars keep getting tougher.
	local beyond = math.max(0, wave - Config.Rounds.FinalWave)
	local e = Config.Endless
	return {
		Damage = lerp(first.Damage, 1) * (1 + e.DamagePerWave * beyond),
		Spread = lerp(first.Spread, 1),
		Reload = lerp(first.Reload, 1) * math.max(e.MinReload, 1 - e.ReloadPerWave * beyond),
		Health = lerp(first.Health, 1) * (1 + e.HealthPerWave * beyond),
		AimBonus = lerp(first.AimBonus, 0),
	}
end

-- Endless mode: waves past FinalWave add units (up to the caps below, to keep
-- servers smooth) and scale redcoat stats per extra wave.
Config.Endless = {
	HealthPerWave = 0.06,
	DamagePerWave = 0.03,
	ReloadPerWave = 0.015,
	MinReload = 0.6,
	MaxFormations = 4,
	MaxLightInfantry = 22,
	MaxGrenadiers = 12,
	MaxDragoons = 12,
	MaxCannons = 4,
	SurviveScore = 25, -- score per wave survived (both modes)
	WaveNames = { "The King's Wrath", "No Quarter", "The Long Night", "Redcoat Tide", "Last Stand at Concord" },
}

-- Wave composition. Line infantry spawn as formations (ranks of Regulars);
-- everything else spawns individually across the north edge.
export type WaveDef = {
	Formations: { { Ranks: number, Files: number, Officer: boolean } },
	LightInfantry: number,
	Grenadier: number,
	Dragoon: number,
	Cannon: number,
	Name: string?,
}

function Config.GetWave(wave: number, endless: boolean?): WaveDef
	local e = Config.Endless
	local beyond = math.max(0, wave - Config.Rounds.FinalWave)
	local formations = {}
	local formationCount = math.min(1 + math.floor((wave - 1) / 4), 3)
	if beyond > 0 then
		formationCount = math.min(3 + math.floor(beyond / 5), e.MaxFormations)
	end
	for i = 1, formationCount do
		table.insert(formations, {
			Ranks = if wave >= 11 then 2 else 1,
			Files = if wave >= 11 then 7 else math.min(3 + wave, 9),
			Officer = wave >= 3 and (i % 2 == 1),
		})
	end

	local def: WaveDef = {
		Formations = formations,
		LightInfantry = math.floor(wave * 0.8),
		Grenadier = if wave >= 4 then math.floor((wave - 1) / 3) else 0,
		Dragoon = if wave >= 5 then math.floor((wave - 2) / 3) else 0,
		Cannon = if wave >= 7 then 1 + math.floor((wave - 7) / 4) else 0,
	}
	if beyond > 0 then
		def.LightInfantry = math.min(def.LightInfantry, e.MaxLightInfantry)
		def.Grenadier = math.min(def.Grenadier + math.floor(beyond / 3), e.MaxGrenadiers)
		def.Dragoon = math.min(def.Dragoon + math.floor(beyond / 3), e.MaxDragoons)
		def.Cannon = math.min(def.Cannon, e.MaxCannons)
	end

	if wave == 1 then
		def.Name = "The Regulars Are Coming!"
	elseif wave == 5 then
		def.Name = "The King's Dragoons"
	elseif Config.GetGeneral(wave) then
		def.Name = (Config.GetGeneral(wave) :: any).Name .. " Takes the Field"
	elseif wave == Config.Rounds.FinalWave and not endless then
		def.Name = "The Final Push"
		def.Grenadier += 2
		def.Dragoon += 2
	elseif endless and wave >= Config.Rounds.FinalWave and wave % 5 == 0 then
		def.Name = e.WaveNames[((wave // 5) % #e.WaveNames) + 1]
	end

	return def
end

return Config
