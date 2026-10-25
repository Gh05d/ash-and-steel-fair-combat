# Befunde für Fair Combat

Statisch mit rekit (`../rekit.toml`), live mit der RekitBridge. Datum, wenn nicht anders angegeben: 2026-10-25.

## Spieler-Treffer (statisch)

- `CombatModule_Player:GotHit(ImpactPoint, Damage, StaminaBurn, StaggerChance, Direction, Attacker, Crit?, ShouldBreachBlock?, Combo, CombatStance, HeavyAttack?, AttackFromBack?, HeavyKick?, Shield?, Kick?, DeathStrike?, WeaponType, Poison?, Bleed?, Decease?, …)` – Bridge-Hook `owner=p6` = Angreifer. Live: p6 ist der Gegner-**Controller** (`GS_AI_NPCController_C`).
- Abbruch vorne in `GotHit`: `invincibleFrame?` gesetzt, `CombatState == 3` (DodgeBackward), `AC Stats.CombatStatus` 11/12. Mit gesetztem `invincibleFrame?` passiert nichts: kein Schaden, keine Reaktion.
- Danach u. a. `UpdateHealth` (setzt `FinishingHit = HP <= 0`), `UpdateStamina`, dann `Reaction`.
- `Reaction`: überspringt die Treffer-Montage, wenn `FinishingHit` (tödlicher Treffer). Sonst `Knock` (bei `HeavyAttack?`/`ShouldBeKnocked?`) oder `GitHit`, dann `PlayAnimMontage(FinalGotHit)`.
  - `FinishingHit` lässt sich **nicht** vorab setzen: `UpdateHealth` überschreibt es vor `Reaction`.
- `GitHit` wählt die Montage nach Richtung/Waffe: `Sword1h_Hit_*_Montage`, `Longs_Hit_*_Montage`; bei `StaggerChance → notStagger` (und kein Krit) oder `CombatState == 14` die leichte `Sword1h_Hit_light_Montage`.
- `Knock` spielt `Sword1h_Knockdown_{Front,Left,Right}_Montage` bzw. `Sword1h_Hit_Back_Montage`.
- Sperrdauer laut Notify `isAttackingState` (`Combat State`):
  - `Sword1h_Hit_Torso_Front_Montage`: WasHit (9) für **1,04 s** (Montage 1,53 s)
  - `Sword1h_Hit_light_Montage`: WasHit für **0,90 s** – auch der „leichte“ Treffer sperrt fast so lange, er ist also keine Lösung für „Schaden ja, Taumler nein“.
  - `Sword1h_Knockdown_Front_Montage`: TempKnocked (5) für **3,41 s** → `knockWindow` Standard 3,5 s.
- Live-Kette (Arena): Taumler im Abstand 1,2 s und 2,1 s. Nach 1,04 s Sperre hatte Pascal also 0,16 s, bevor der nächste traf.

## Mechanismus (Hypothesen, live zu bestätigen)

UE4SS ruft BP-Hooks **nach** der Funktion auf. Die Reaktion eines Treffers läuft also schon, wenn der Mod davon erfährt.

1. **Treffer ganz blockieren** (Budget verbraucht): `invincibleFrame?` am `CombatModule_Player_C` setzen, solange kein Angreifer im Fenster mehr ein Budget hat; danach zurücksetzen. Genauer pro Angreifer: im Post-Hook auf dessen `CombatModule_AI_Humanoid:EnableTrace` (einmal pro Hieb) den Spieler in seine `HitActors` eintragen – die KI trifft dasselbe Ziel pro Hieb nur einmal (`AtackingEnemyChecks` prüft `HitActors`). Ob UE4SS 3.0.1 TMaps aus Lua beschreiben kann, ist offen.
2. **Schaden ja, Taumler nein** (erlaubter Treffer im Fenster): im `GotHit`-Post-Hook die gerade gestartete Treffer-Montage am Spieler stoppen (`StopAnimMontage`). Das `isAttackingState`-NotifyState sollte beim Stoppen sein `NotifyEnd` bekommen und `CombatState` zurücksetzen – live prüfen, sonst `CombatState` selbst auf Idle (2) setzen.
3. **Reaktion erkennen**: im `GotHit`-Post-Hook die laufende Montage des Spielers lesen. Name enthält `Knockdown` → `knock`; `_Hit_` (auch `Hit_light`, `Hit_Back`) → `stagger`; keine neue Montage → `none`.

## Gegner (statisch)

- Ziel: Blackboard-Schlüssel `Target` (Actor). „Bekämpft den Spieler“ = `Status == 6` und `Target` ist der Spieler-Pawn.
- Fernkampf: Der BT nutzt `gs_checkrangeweapon` (Waffen `WeaponM`/`WeaponR`, `Distance` 750). Für den Mod: Overlay des Kampfmoduls (`CombatModule_AI_Humanoid:GetOverlayState` → `CombatOverlayState`, Enum `ALS_OverlayState`) auf Bogen/Armbrust prüfen. Enum-Werte noch nicht gecacht (`rekit ue enum ALS_OverlayState`, Deck nötig).
- Kombo: `AI_C_AttackCombo` startet nach `ComboAttackCounter >= 3` und setzt ihn zurück. Kombo-Ende im Takt erkennen: `ComboAttackCounter` fällt von ≥ 3 auf 0.

## Live-Messliste (nächste Spielsitzung)

Vorher fragen, ob Pascal spielt; Spielstände sichern; Mod mit `debug = true` deployen (`! scripts/deploy-deck.sh`).

1. Arena 1 gegen 1: `UE4SS.log` zeigt pro Treffer `hit <Angreifer> reaction=<…> montage=<…>`. Stimmt die Erkennung (Taumler, Niederschlag, Block)?
2. Taumler im Fenster: Wird die Montage gestoppt, kann Pascal sofort wieder handeln, und steht `CombatState` danach auf Idle?
3. Folgetreffer: Kommt nach dem ersten Folgetreffer desselben Gegners noch etwas an?
4. Werte: `ue enum ALS_OverlayState`; `GetOverlayState` eines Bogenschützen lesen.
