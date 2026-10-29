# Fair Combat: No More Stunlocks

A UE4SS mod for **Of Ash and Steel** that keeps fights hard but fair. No more dying in an endless chain of hit reactions, and group fights get a Souls-like rhythm.

Download: [Nexus Mods](https://www.nexusmods.com/ofashandsteel/mods/62) or the [GitHub releases](https://github.com/Gh05d/ash-and-steel-fair-combat/releases).

## What it changes

- **No stunlock chains.** After a stagger you can't be staggered again for a moment (damage still applies). The enemy who staggered you gets **one** follow-up hit, then waits until you have recovered, even if it was in the middle of a combo. After the window there is a short breather in which nothing can stagger or knock you down again. Knockdowns work the same way: you can't be combo'd to death while you get up.
- **Attack rights.** Only one melee enemy attacks you at a time, a second one waits close by and takes over. The others raise their guard and circle you at a distance instead of crowding you. After a combo an enemy backs off for a moment.
- **Archers stay dangerous.** Ranged enemies keep shooting, from behind too. Taking them out first is up to you. Their arrows just can't stagger you again inside the protection window.
- **Enemies commit to their attacks.** Humans aim briefly and then commit to a direction, so a side step at the right moment makes them miss. Attacking animals turn slower while they bite or charge.
- **Readable wind-ups.** The few enemy attacks whose hit comes almost instantly (some rapier and two-handed attacks, 0.15-0.3 s) start a little slower, so you can actually see them coming. The swing itself keeps its speed.
- **Parry out of a stagger.** Once a stagger has run for about half a second (0.55 s), pressing parry ends it and you parry. Earlier presses are lost, as in the game. Attacking and dodging still wait until the stagger is over, and knockdowns are not affected.
- **Hits that land.** Your melee hits stop you and the enemy for a split second (60 ms hit stop), and the game's own hit sounds play louder: it mixes them at 15-50 % volume, the mod plays them at 90 %. Swords sound like they cut instead of brushing past.
- **Humans and animals.** Bandits, guards, cursed warriors, Woodwalkers, Maulers, Tunnel Beasts, Rovers and others that use the game's combat AI.

Nothing in the game's files is replaced: the mod steers the game's own combat AI and sounds at runtime, so it works next to pak mods.

## Installation

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest) (experimental build, tested with v3.0.1-1181): `dwmapi.dll` and the `ue4ss` folder go into `ofAshAndSteel/ofAshAndSteelGame/Binaries/Win64/`.
2. Extract the release zip into the game folder `ofAshAndSteel/`. The mod ends up in `ofAshAndSteelGame/Binaries/Win64/ue4ss/Mods/FairCombat/`.
3. Steam Deck / Linux (Proton): add `WINEDLLOVERRIDES="dwmapi=n,b" %command%` to the game's launch options.

All values are in `Scripts/config.lua`, every feature can be switched off there.

## Development

- `tests/run.sh` runs the rule engine tests (`policy.lua`, real Lua 5.4 via lupa) and a syntax check of all scripts.
- `scripts/deploy-deck.sh` copies the mod to the Steam Deck (with debug log on; `DEBUG=0` for the release build). Reload in game with Ctrl+R.
- `scripts/package.py` builds `dist/FairCombat-<version>.zip`; `./release.sh` tags, creates the GitHub release and triggers the Nexus upload.
- `scripts/make_nexus_images.py` builds the Nexus header and thumbnail from `docs/art/`.

## License

MIT
