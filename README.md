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
| Mouse | Aim (your soldier faces the cursor) |
| Left click | Fire. Hold it to keep firing as soon as you're loaded |
| R | Reload (it also starts automatically when you're empty) |
| F / Right click | Hatchet swing (melee) |
| 1-4 | Switch between the firearms you own |
| B | Open the shop (between waves only) |
| Mouse wheel | Zoom the camera |

- **Muskets are slow.** Each shot is followed by a long reload, and you walk slower
  while loading. Firing on the move adds spread.
- **Dodge volleys.** Redcoats raise their muskets (a "!" appears, and the officer shouts
  "Present!") and fire about a second later in the direction they aimed. Moving
  sideways makes them miss.
- **Use cover.** Stone walls, trees, rocks and houses stop musket balls.
- **Watch for red markers.** A red circle on the ground means a grenade is about to
  land there. A red line means a field gun is about to fire along it.
- **Defend the powder stores.** Redcoats that have nobody else to shoot at fire on the
  stores. You lose if the stores are destroyed or if every player is down. Fallen
  players come back at the start of the next wave.

### Enemies

| Unit | Notes |
| --- | --- |
| Redcoat (line infantry) | Marches in formation and fires synchronized volleys |
| Officer | Leads a formation and makes nearby troops reload faster. Kill him first |
| Light Infantry | Fast skirmishers that fight on their own |
| Grenadier | Tough. Throws grenades over cover |
| Dragoon | Cavalry that rides down players with sabres |
| Field Gun | Stationary artillery. Its roundshot pierces through anything in its line |

### Shop (between waves)

- **Firearms:** Musket (starting weapon), Brace of Pistols (2 shots), Blunderbuss
  (shotgun spread), Long Rifle (long-range sniper).
- **Training:** Quick Loading, Marksmanship, Heavy Charge, Toughness, Fleet Foot.
- **Reinforcements:** hire up to 4 Minutemen who follow you and shoot redcoats, or
  repair the powder stores.

## Project layout

```
src/shared/Config.luau            All tuning: weapons, units, upgrades, wave composition
src/server/GameServer.server.luau Round loop: intermission → wave → win/lose
src/server/MapBuilder.luau        Procedural battlefield, village and powder stores
src/server/Units.luau             Redcoat and militia models, formations and AI
src/server/PlayerManager.luau     Player weapons, reloading, melee, shop and upgrades
src/server/FX.luau                Sends visual-effect events to clients
src/client/Client.client.luau     Top-down camera, mouse aiming, input
src/client/Interface.luau         HUD, announcements, crosshair and shop UI
src/client/Effects.luau           Musket smoke, tracers, grenades and cannon fire
tools/build_place.py              Builds RedcoatInvasion.rbxlx from src/
```

To rebalance the game, edit `src/shared/Config.luau`. `Config.GetWave` controls what
spawns in each wave.
