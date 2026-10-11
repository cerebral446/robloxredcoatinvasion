# Redcoat Invasion (Roblox)

A top-down musket shooter for Roblox, inspired by the Flash game *Redcoat Invasion*.
You are colonial militia defending the town's powder stores. Waves of British
Regulars march in from the north in formation, halt, and fire volleys. Survive 15
waves to win.

Everything, including the map, soldiers, UI and effects, is built from code. The game
needs no uploaded assets, models or plugins.

## Open it in Roblox Studio

### Option A: open the place file (easiest)

1. Download `RedcoatInvasion.rbxlx` from this repository.
2. In Roblox Studio choose **File → Open from File…** and pick `RedcoatInvasion.rbxlx`.
3. Press **Play** (F5). To test co-op, use **Test → Clients and Servers** with 2+ players.
4. To publish it, use **File → Publish to Roblox As…**.

### Option B: Rojo (live-sync while you edit the code)

1. Install [Rojo](https://rojo.space/) and its Studio plugin.
2. Run `rojo serve` in this folder.
3. In Studio, open a new **Baseplate** place and click **Connect** in the Rojo plugin.
   The map builder deletes the default baseplate when the game starts.

After you change files in `src/`, rebuild the place file with `python3 tools/build_place.py`.

## How to play

| Input | Action |
| --- | --- |
| WASD | Move |
| Shift (hold) | Sprint |
| Mouse | Aim (your soldier faces the cursor) |
| Left click | Fire. Hold it to keep firing as soon as you're loaded |
| R | Reload (it also starts automatically when you're empty) |
| F / Right click | Hatchet swing (melee) |
| 1-4 | Switch between the firearms you own |
| B | Open the shop (between waves only) |
| L | Show or hide the leaderboard |
| Mouse wheel | Zoom the camera |

- **The first waves are gentle.** Early redcoats hit softer, miss more, reload
  slower and fall to one musket ball. They reach full strength by wave 8
  (`Config.Difficulty`).
- **Muskets are slow.** Each shot is followed by a long reload, and you walk slower
  while loading. Firing on the move adds spread.
- **Dodge volleys.** Redcoats raise their muskets (a "!" appears, and the officer shouts
  "Present!") and fire about a second later in the direction they aimed. Moving
  sideways makes them miss.
- **Break their lines.** If you (or your minutemen) get within about 22 studs of a
  formation, or it loses half its men, the line breaks: the redcoats scatter, then
  each one fights on his own. Get too close and they'll use their bayonets.
- **Use cover.** Stone walls, trees, rocks and houses stop musket balls.
- **Watch for red markers.** A red circle on the ground means a grenade is about to
  land there. A red line means a field gun is about to fire along it.
- **Defend the powder stores.** Redcoats that have nobody else to shoot at fire on the
  stores. You lose if the stores are destroyed or if every player is down. Fallen
  players come back at the start of the next wave.

### Enemies

| Unit | Notes |
| --- | --- |
| Redcoat (line infantry) | Marches in formation and fires synchronized volleys. Scatters when you get close |
| Officer | Leads a formation and makes nearby troops reload faster. Kill him first |
| Light Infantry | Fast skirmishers that fight on their own |
| Grenadier | Tough. Throws grenades over cover |
| Dragoon | Cavalry that rides down players with sabres |
| Field Gun | Stationary artillery. Its roundshot pierces through anything in its line |
| **General (boss)** | Every 10th wave a famous British general rides out on a white charger (see below) |

### Boss generals

Every 10 waves a general takes the field, in this order (the list repeats
after wave 50):

| Wave | General |
| --- | --- |
| 10 | General Thomas Gage, Governor of Massachusetts Bay |
| 20 | General Sir William Howe, victor of Bunker Hill |
| 30 | General John Burgoyne, "Gentleman Johnny" |
| 40 | General Sir Henry Clinton, Commander-in-Chief |
| 50 | General Charles, Lord Cornwallis |

A general:

- hangs back behind his lines and fires a brace of pistols
- makes every redcoat within 70 studs reload faster
- calls up reinforcements every 18 seconds
- charges any player who gets within 30 studs

His health shows in a boss bar at the top of the screen. It grows with the
wave and with the number of players. When he falls, every formation on the
field breaks and scatters, and every player gets a bonus. Tune him in
`Config.Boss` and `Config.Units.General`.

### Shop (between waves)

- **Firearms:** Musket (starting weapon), Brace of Pistols (2 shots), Blunderbuss
  (shotgun spread), Long Rifle (long-range sniper).
- **Training:** Quick Loading, Marksmanship, Heavy Charge, Toughness, Fleet Foot.
- **Reinforcements:** hire up to 4 Minutemen who follow you and shoot redcoats, or
  repair the powder stores.

## Game modes and leaderboard

Before wave 1, players vote on the mode (panel at the top left):

- **Campaign:** survive 15 waves to win.
- **Endless:** the waves never stop. Past wave 15 the Regulars bring more
  troops (capped to keep servers smooth) and get tougher each wave: more
  health, harder hits and faster reloads (`Config.Endless`).

**Score** is the bounty for each redcoat you kill, plus a bonus for every wave
survived. The **live leaderboard** (L) ranks everyone in the current battle.
Below it is the **all-time Endless top 10**. Each player's best run is saved
(furthest wave first, then score) to an `OrderedDataStore`. Saving needs a
published place with **Game Settings → Security → Enable Studio Access to API
Services** turned on. Without that, the board shows the best runs on the
current server instead.

## Allies

- **Minutemen** (hired in the shop) spread out in a loose ring around you, take
  a new spot every few seconds, and run to catch up if you sprint away. They
  fire at any redcoat in range without leaving you.
- **Armed townsfolk** (townsmen, townswomen and a farmer) wander the village
  in peacetime. When the Regulars come within range they move up to the
  stockade, using the firing gaps, and shoot back with their own muskets.
  Redcoats can shoot them too. Fallen townsfolk are replaced each intermission.

## Atmosphere

- **Lighting:** golden-hour light with atmosphere, bloom and colour grading.
  The place file turns on `Future` lighting (Game Settings or the Lighting
  properties), so fires and lanterns cast shadows. If you use Rojo, set
  **Lighting → Technology** to *Future* yourself.
- **Fires:** campfires, a forge, braziers, burning haystacks, wagons and roofs
  with flickering light. Big explosions leave the ground burning for a while.
- **The British redoubt:** a stone fort with Union flags along the north edge.
- **Villagers:** children, a town crier with a bell, a blacksmith at the
  forge, a drummer boy and chickens wander and chat, then panic and take
  shelter during waves. They only exist on each player's screen, so they cost
  no network traffic and can't be hurt.
- **Walking:** soldiers and townsfolk swing their legs as they move. This is
  animated on each player's screen.
- **Uniforms:** players wear a Continental uniform (navy coat, buff breeches,
  white crossbelts and a gold-trimmed tricorne) and hold their weapon in
  their hands.

## Project layout

```
src/shared/Config.luau            All tuning: weapons, units, upgrades, wave composition
src/server/GameServer.server.luau Round loop: intermission → wave → win/lose
src/server/MapBuilder.luau        Procedural battlefield, village and powder stores
src/server/SetDressing.luau       Lighting, fires, lanterns, flags, redoubt, palisades, props
src/server/Units.luau             Redcoat and militia models, formations and AI
src/server/PlayerManager.luau     Player weapons, reloading, melee, shop and upgrades
src/server/Leaderboard.luau       All-time Endless leaderboard (OrderedDataStore + fallback)
src/server/FX.luau                Sends visual-effect events to clients
src/client/Client.client.luau     Top-down camera, mouse aiming, input
src/client/Interface.luau         HUD, announcements, crosshair and shop UI
src/client/Effects.luau           Musket smoke, tracers, grenades, cannon fire, light flicker
src/client/LeaderboardUI.luau     Live leaderboard panel and the mode vote
src/client/UnitAnimator.luau      Leg animation for soldiers and townsfolk
src/client/Townsfolk.luau         Cosmetic villagers and chickens (client-side only)
tools/build_place.py              Builds RedcoatInvasion.rbxlx from src/
```

To rebalance the game, edit `src/shared/Config.luau`. `Config.GetWave` controls what
spawns in each wave.
