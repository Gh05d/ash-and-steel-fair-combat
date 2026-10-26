Fair Combat - No More Stunlocks (Of Ash and Steel)

Fights stay hard but fair: no more dying in an endless chain of hit reactions,
and group fights get a Souls-like rhythm.

REQUIREMENT
  UE4SS (experimental build, tested with v3.0.1-1181):
  https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest

INSTALL
  1. Put dwmapi.dll and the ue4ss folder from UE4SS into
     ofAshAndSteel\ofAshAndSteelGame\Binaries\Win64\
  2. Extract this mod into the game folder ofAshAndSteel\ so that it ends up in
     ofAshAndSteelGame\Binaries\Win64\ue4ss\Mods\FairCombat\
  3. enabled.txt in this folder turns the mod on.

  Steam Deck / Linux: add to the game's launch options in Steam
     WINEDLLOVERRIDES="dwmapi=n,b" %command%

WHAT IT DOES
  - After a stagger or knockdown you get a moment to recover. The enemy who
    hit you lands one follow-up, then waits. No more stunlock chains.
  - Only one melee enemy attacks at a time, the others guard and circle you.
  - Archers keep shooting; they just can't stagger you again right away.
  - Enemies commit to their attack direction, so side steps work.
  - The few near-instant enemy attacks get a readable wind-up.
  - Works for humans and animals.

SETTINGS
  Scripts/config.lua - every feature can be switched off there.
