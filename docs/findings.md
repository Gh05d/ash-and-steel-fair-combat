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
3. **Reaktion erkennen** (umgesetzt nach dem Review): Post-Hooks auf `Reaction`, `GitHit` und `Knock` des Spielers feuern vor dem `GotHit`-Post-Hook. `GitHit` → `stagger`, `Knock` → `knock`; ohne `Reaction` im selben Frame ist der Treffer nicht durchgekommen (Block, Ausweichen, Unverwundbarkeit) und zählt nicht. Montage-Namen taugen nicht: Rapier-Block (`Sword1h_Hit_Head_Front_Parry_Montage`) enthält auch `_Hit_`.

## Gegner (statisch)

- Ziel: Blackboard-Schlüssel `Target` (Actor). „Bekämpft den Spieler“ = `Status == 6` und `Target` ist der Spieler-Pawn.
- Fernkampf: Der BT nutzt `gs_checkrangeweapon` (Waffen `WeaponM`/`WeaponR`, `Distance` 750). Für den Mod: Overlay des Kampfmoduls (`CombatModule_AI_Humanoid:GetOverlayState` → `CombatOverlayState`, Enum `ALS_OverlayState`) auf Bogen/Armbrust prüfen. Enum-Werte noch nicht gecacht (`rekit ue enum ALS_OverlayState`, Deck nötig).
- Kombo: `AI_C_AttackCombo` startet nach `ComboAttackCounter >= 3` und setzt ihn zurück. Kombo-Ende im Takt erkennen: `ComboAttackCounter` fällt von ≥ 3 auf 0.

## Live-Messliste (nächste Spielsitzung)

Vorher fragen, ob Pascal spielt; Spielstände sichern; Mod mit `debug = true` deployen (`! scripts/deploy-deck.sh`).

1. Arena 1 gegen 1: `UE4SS.log` zeigt pro Treffer `hit by <Angreifer> reaction=<…>`. Stimmt die Erkennung (Taumler, Niederschlag, Block zählt nicht)? Feuern die Hooks in der erwarteten Reihenfolge?
2. Taumler im Fenster: Wird die Montage gestoppt, kann Pascal sofort wieder handeln, und steht `CombatState` danach auf Idle?
3. Folgetreffer: Kommt nach dem ersten Folgetreffer desselben Gegners noch etwas an?
4. Werte: `ue enum ALS_OverlayState`; `GetOverlayState` eines Bogenschützen lesen.

## Wartende Gegner (Task 6, statisch)

Live gesehen: Ein Gegner mit `DefenceMode?` = true läuft nur hinterher. Grund im BT: Kann er nicht angreifen, nimmt die Schleife den Zweig `MoveToTarget` (`Stamina > 0.2` und `DistanceToTarget >= 200`) → `AI_C_MoveToTarget` läuft auf den Spieler zu. Verspotten (Cooldown 10 s) und Umkreisen (`Stamina < 0.2` → `AI_C_Wait` 5 s mit Service `BB_Strafe`, Cooldown 20 s) sind meist gesperrt.

`BB_Strafe` strafet selbst: `AddMovementInput` seitlich/rückwärts, `AIController:K2_SetFocus(Target)`, Strafe-Montage, Blackboard-Bools (`Strafing?`, `StrafingNoObstacles?`). `AI_C_MoveToTarget`, `AI_C_TauntCustom`, `AI_C_Attack` und `BB_SetWalkSpeed` lesen `Strafing?`.

Kandidaten, live zu vergleichen (Brücke, Arena):
- **B:** `Strafing?` = true für gehaltene Gegner – vielleicht strafen `MoveToTarget`/`Taunt` dann statt zu laufen.
- **A:** eigener Bewegungsbefehl alle ~1 s: `AIController:MoveToLocation` auf einen Punkt im Ring (`ready` 250 cm, `wait` 400 cm) um den Spieler plus `K2_SetFocus(Spieler)`. Risiko: `AI_C_MoveToTarget` überschreibt den Befehl.
- **C:** Blackboard `Stamina` für gehaltene Gegner unter 0,2 setzen → der BT nimmt seine eigenen Zweige Umkreisen/Verspotten. Risiko: `BB_SetStaminaAndHP` überschreibt `Stamina` alle 0,1 s.

## Live-Test 2026-10-25 abends (Arena, 1 gegen 1, nach Fix 365bd75)

- Pascal: „hat sich gut angefühlt“.
- Log: Taumler 16:02:40,18 → Verursacher ab Fensterende gesperrt (`hold` 41,77–42,30), sein nächster Hieb um 42,18 geblockt (`block`/`unblock` 42,18–42,44), danach Kombo-Rückweichen 42,70–44,30.
- Niederschlag 16:03:05,32 → Sperre ab Fensterende (`hold` 08,98–09,38). `knockWindow` 3,5 s passt.
- Wichtig: `GotHit` p6 ist die **Spielfigur** des Angreifers, nicht der Controller (vorher falsch gelesen: `owner=p6` im Trace = Besitzer von p6). Ein Treffer kam mit Angreifer `PlayerCharacter_C` (Umgebung/eigene Wurfgegenstände) – zählt jetzt ohne Sperre.
- Noch nicht live geprüft: Angriffsrecht mit mehreren Gegnern, Rapier-Block, ob der abgebrochene Taumler die Figur kurz festhält.

## Live-Test 2026-10-25 ~23:30 (Arena 1 gegen 1, Variante G deployt)

- Warte-Varianten: A/B/C (Laufbefehl, `Strafing?`, Blackboard-Ausdauer) → Gegner folgt nur. D/E (echte Ausdauer, `SetDefenceMode`) → steht auf Abstand, tut nichts. F/G (dazu eigener Kreislauf per `MoveToLocation` + `K2_SetFocus`) → „sah gut aus, G am besten“ (Pascal). G ist eingebaut.
- Dolch-Gegner: Hieb während der Sperre lief sichtbar weiter, Treffer geblockt („kein Schaden“). Pascal: stört nicht, „er hat mich verfehlt“.
- Im 1 gegen 1 sind Sperren kurz (0,5 s Verursacher, 1,5 s Kombo-Rückweichen) – das Kreisen fällt kaum auf. Prüfen im Gruppenkampf (Banditen), wo Gegner in Bereitschaft/Warten länger gehalten werden.

## Live-Test 2026-10-26 morgens (verfluchte Krieger, Gruppe)

- Pascal: „hat sich gut angefühlt“.
- Angriffsrecht live bestätigt: von 2 Kriegern wurde einer 13 s gehalten (06:21:31–45 UTC), dann Rollentausch.
- Grenzfall: Hieb des Verursachers 0,1 s nach Sperrbeginn kam durch (Ausholen vor der Sperre → kein Block); Taumler wurde abgebrochen, nur Schaden.
- Tiere (Woodwalker, Mauler) mit der korrigierten Fassung noch nicht getestet.

## Drehung (Ziel 4), Stand 2026-10-26 nachmittags

- **Menschen:** Angriffs-Tasks (`AI_C_Attack*`) starten einen 0,01-s-Timer, der in der ersten Hälfte jeder Angriffs-Animation jeden Frame `Combat_RotateToTarget(Ziel, 1, 5)` aufruft (Base_NPC-Timeline 0,5 s, `RInterpTo` 5). Hook darauf feuert bis ~74×/s → verboten, `turnLimit` aus. Werte im Bytecode fest. Offener Weg: den `Timer`-Handle des Tasks pausieren (`K2_PauseTimerHandle`; `K2_ClearAndInvalidateTimerHandle` scheitert an Out-Parameter) – live noch nicht geprüft.
- **Tiere:** drehen über `CharacterMovement.RotationRate` (`bUseControllerDesiredRotation`; Woodwalker 90°/s, Tunnel Beast/`GS_CaveBug` 180°/s, Rover/`GS_Rhino` 90°/s) und die Task-Vorlage `GS_AI_Animal_RotateToTarget` (`Interp Speed`, nicht pro Tier instanziert).
  - 0,4 dauerhaft → Tiere bekommen dich nie in den Biss-Kegel (`GS_ConeCheck`) und greifen nicht mehr an (Pascal: „warum greifen die mich nicht mehr an?“).
  - **0,7 nur während des Angriffs** (CombatState 0/11/12), Original aus dem Klassen-CDO → Rover: „hat sich gut angefühlt“.
- Namen: Tunnel Beast = `GS_CaveBug`, Rover = `GS_Rhino`, Mauler = Wolf, Woodwalker = `GS_Forester`.
