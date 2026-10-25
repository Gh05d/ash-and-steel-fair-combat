# Fair Combat – Design

Combat-Mod für **Of Ash and Steel** (UE 4.27, Steam-AppID 2893820), gespielt auf dem Steam Deck.
Stand 2026-10-25, Brainstorming mit Pascal. Legende: **(P)** = Pascal hat es so gesagt · **(C)** = Claudes Entscheidung oder Vermutung, von Pascal nicht ausdrücklich bestätigt.

## Absicht

Das Kampfsystem ist gut, aber Gruppenkämpfe sind unfair (P). Schon 2–3 Gegner bringen den Spieler in eine **endlose Taumel-Kette**: Jeder Treffer löst einen neuen Taumler aus, der nächste Gegner trifft, bevor man sich erholt hat, und man stirbt, ohne reagieren zu können (P). Dazu kommen unzuverlässige Treffer des Spielers, Gegner, die sich blitzschnell zurückdrehen, und Gegnerangriffe (v. a. Rapier) ohne lesbaren Vorlauf (P).

Ziel ist ein **Souls-artiger Kampfrhythmus** (P): schwer, aber fair, mit Luft zum Umpositionieren und Erholen. Schwierigkeit ist in Ordnung, Unfairness nicht (P).

Erfolg heißt (C): In Kämpfen gegen 2–3 Gegner gibt es keine Todeskombos mehr. Ein Taumler kostet höchstens den Folgetreffer seines Verursachers plus vereinzelte Treffer anderer, nie eine Kette. Pascal beurteilt das im Spiel.

## Ziele

### 1. Taumel-Kette beenden (Hauptziel, P)

- **Taumelfenster:** Nach jedem Taumler des Spielers gilt ein kurzes Fenster (Standard 1,5 s (C), einstellbar), in dem **kein neuer Taumler** ausgelöst wird, egal von wem, auch nicht durch Pfeile (P). Schaden kommt weiter an (P).
- **Belohnung für den Verursacher:** Der Gegner, der den Taumler ausgelöst hat, darf **genau einen Folgetreffer** landen (P: „das muss ja auch belohnt werden“). Danach greift er nicht mehr an, bis der Spieler sich erholt hat (P: „nur einmal angreifen und dann auf die Recovery warten“). Ein zweiter Folgetreffer desselben Gegners darf **nicht ankommen**, auch nicht aus einer schon laufenden Kombo (P: „mehrmals vom selben Gegner … falsch und zu hart“).
- „Erholt“ heißt (C): Ende des Taumelfensters plus kurzer Puffer (Standard 0,5 s, einstellbar).
- **Niederschläge (`Knock`) sind kein Taumler** (P: „wenn ich am Boden bin, kann ich ja nicht taumeln“) und lösen das Taumelfenster nicht aus. Aber der Spieler darf auch am Boden **nicht zu Tode gecombot werden** (P). Daher gilt für Boden und Aufstehen ein eigenes Schutzfenster (C): kein neuer Niederschlag und kein Taumler, jeder Gegner höchstens ein Treffer, der Verursacher wartet danach wie beim Taumler. Dauer: Bodenzeit plus Aufstehen plus Puffer, einstellbar.
- **Andere Gegner im Fenster:** Jeder andere Gegner darf den Spieler im Fenster höchstens **einmal** treffen (P, früh im Gespräch: „wenn ich beim Taumeln einmal getroffen werde ist ok, aber mehrmals … falsch“). Das Angriffsrecht darf deshalb sofort an den Gegner in Bereitschaft übergehen; er unterliegt derselben Ein-Treffer-Regel (C).

### 2. Souls-artiges Gegnerverhalten (P: „soulslike combat ist eine gute Idee“)

**Gilt für Menschen und Tiere** (P: Tiere „sind noch schlimmer als Menschen mit den Combos, besonders diese Wood-Käfer“). Tiere haben eigene Behavior Trees (`Characters/GS_Animals/**/GS_*_BT`, z. B. `GS_Forester_BT` – **Woodwalker/Zangenkäfer** (`gs_n_forester`), Pascals „Wood-Käfer“ (P, 2026-10-26) –, `GS_Wolf_New_BT` (Mauler, `gs_n_fanger`)) und eigene Kampfmodule. Ob es dort einen Hebel wie `DefenceMode?` gibt, ist ungeprüft. Die Käfer haben Vorrang (C, nach Pascals Beispiel).

- **Angriffsrecht:** Nur eine begrenzte Zahl von Nahkämpfern greift gleichzeitig an. Standard (C): **1 aktiver Angreifer, 1 weiterer in Bereitschaft** (nah, übernimmt, wenn der Platz frei wird), Rest hält Abstand. Einstellbar.
- **Wartende Gegner verhalten sich natürlich:** auf Abstand gehen, umkreisen, gelegentlich verspotten. Sie laufen dem Spieler **nicht nur stumm hinterher** – genau das passierte im Live-Test, als ein Gegner nur gesperrt war (siehe Befunde).
- **Nach einer Kombo** weicht der Gegner kurz zurück (C: etwa 1–2 s), statt nahtlos weiterzumachen.
- **Kein Wutausbruch danach:** Ein freigegebener Gegner holt nicht alles Aufgestaute auf einmal nach (C, nach Beobachtung „er hat mich überrollt“; Ursache ungeklärt).
- **Bogenschützen bleiben unverändert** (P): Sie dürfen weiter von hinten schießen, sie auszuschalten soll Priorität sein. Sie zählen nicht zum Angriffsrecht der Nahkämpfer. Einzige Ausnahme: Ihre Pfeile lösen im Taumelfenster keinen neuen Taumler aus (Schaden ja) (P: „passt“).

### 3. Treffer des Spielers zuverlässig machen (P)

- Pascal: Treffer zählen manchmal nicht, „wahrscheinlich wenn man zu nah ist“.
- **Erst messen, dann ändern (C):** Hiebe gegen tatsächliche Treffer, mit Abstand zum Gegner.
- Ziel: Wo die Klinge den Gegner sichtbar durchquert, zählt der Treffer. Gleicher Schaden pro Treffer, keine größere Reichweite als die Klinge (C).
- **Für beide Seiten** (P: „die Gegner sollten auch profitieren“): Auch Gegner-Treffer werden zuverlässiger, nach demselben Maßstab. Gegner-Traces laufen im `CombatModule_AI_Humanoid` (`Trace`/`EnableTrace`/`SelectAttackTrace`) bzw. in den Tier-Modulen; dort zuerst messen, ob sie dieselbe Lücke haben.

### 4. Gegner drehen sich nicht mehr blitzschnell zurück (P)

- Während Vorlauf und Angriff dreht sich ein Gegner langsamer zum Spieler (C). Wer seitlich ausweicht oder hinter ihn kommt, lässt ihn ins Leere schlagen. Außerhalb von Angriffen dreht er normal. Drehtempo einstellbar.

### 5. Lesbarer Vorlauf (Wind-up) bei Gegnerangriffen (P: „ja, denke schon“)

- Der Anfang von Gegnerangriffen läuft etwas langsamer bis kurz vor dem Trefferfenster, danach normales Tempo (C). Der Angriff wird lesbarer, nicht schwächer.
- Nur Angriffe mit sehr kurzem Vorlauf (v. a. Rapier), nicht alle (C). Schwelle und Faktor einstellbar.

## Nicht-Ziele

- **Neue oder geänderte Animationen** (mittlere Angriffsanimation des Spielers): zurückgestellt, eventuell **eigener Mod** (P). Vorlage wäre Nexus-Mod 44, nicht kopieren (P).
- Das Spiel leichter machen: kein höherer Spielerschaden, kein geringerer Gegnerschaden, keine längere Unverwundbarkeit (C, folgt aus „Schwierigkeit ist ok“).
- Bogenschützen schwächen (P).

## Anti-Ziele (wäre ein Fehlschlag, auch wenn es technisch läuft)

- Gegner, die stumm hinterherlaufen oder sichtbar „einfrieren“, während sie warten (C, aus dem Live-Test).
- Kämpfe, die sich zahnlos anfühlen, weil Gegner kaum noch angreifen (C).
- Abstürze oder Ruckler auf dem Deck (C, siehe UE4SS-Regeln).

## Rahmenbedingungen

- **UE4SS-Lua-Mod, keine ersetzten Spiel-Assets** (C, wie Camp Everywhere). Grund: verträgt sich mit Pak-Mods (RoadSigns `_94_P`, Choose What You Are Selling `_91_P`) und Spiel-Updates. Falls ein Ziel (z. B. Wind-up) nur per Asset-Änderung geht, ist das eine Rückfrage an Pascal, kein stiller Wechsel.
- **UE4SS-Regeln aus Camp Everywhere** (`../camp-everywhere/CLAUDE.md`): kein `LoopAsync`/`ExecuteWithDelay`, nur `LoopInGameThreadWithDelay`/`ExecuteInGameThreadWithDelay`; keine Hooks auf häufig feuernde BP-Funktionen (nichts, was pro Frame oder pro Trace-Tick läuft); Hooks auf Spiel-Blueprints erst nach dem Laden der Welt (`ClientRestart`).
- **UE4SS v3.0.1-1181:** Hooks auf Blueprint-Funktionen feuern **nach** der Funktion (live gemessen, siehe Befunde). Der Mod kann einen Treffer nicht vorab abfangen, nur danach reagieren.
- **Testen macht Pascal im Spiel** (P), auf dem Deck per Moonlight. Claude startet dort nichts und drückt keine Tasten. Vor jeder Änderung im Spielordner fragen, ob er spielt; vor Tests Spielstände sichern.
- **Keine Spieldaten öffentlich** (P): nichts aus `../research/` in dieses Repo oder Nexus-Uploads. Namen, Pfade und kurze Ausschnitte sind ok.
- **Veröffentlichung auf Nexus, wenn er gut funktioniert, und erst wenn alle fünf Ziele fertig sind** (P), keine Etappen-Releases. Englische Texte, eine Einstelldatei mit allen Werten, Release-Weg wie Camp Everywhere (GitHub-Release → Nexus-Upload).
- Jedes Ziel einzeln abschaltbar (C), damit Pascal vergleichen kann und Nutzer wählen können.
- Laptop: keine Dauer-Volllast; drosselt am USB-C-Netzteil.

## Befunde (Grundlage, mit rekit und der Laufzeit-Brücke)

Statisch (`rekit`, Cache `../research/rekit-cache`):

- **Gegner-KI** menschlicher NPCs ist der Behavior Tree `Characters/NPC/AI/BaseNPC_AI_Controller` (Name täuscht; `rekit ue bt BaseNPC_AI_Controller`). Controller-Klasse im Spiel: `GS_AI_NPCController_C`. Kampfschleife (Status `inCombat` = 6): erst ein Selector mit Abwehr, Ausweichen, Spezial, Verspotten (Cooldown 10 s), Umkreisen bei wenig Ausdauer (Cooldown 20 s), sonst 0,1 s warten; dann der **Angriffs-Selector** (Attack, nach 3 einfachen Angriffen `AI_C_AttackCombo`, dazu Heavy/Special/WithFake). Keine Abstimmung zwischen Gegnern, kein „wer hat zuletzt getroffen“.
- Der Angriffs-Selector hat den Decorator **„`DefenceMode?` is Not Set“**. Den Schlüssel schreibt in den gecachten Assets niemand (ungeprüft: ~2260 ungecachte Assets unter `Characters/**`).
- **Spieler-Treffer:** `CombatModule_Player:GotHit` (Parameter u. a. p2 Damage, p4 StaggerChance, p6 Attacker) bricht ab, wenn `invincibleFrame?` gesetzt ist (heute nur bei Perfect Parry, Finisher, Rush, Speerwurf). Sonst `Reaction` → `GitHit` (Montage) bzw. `Knock`; `StaggerChance` würfelt aus Gegner-Stat 26 minus Spieler-Stat 59.
- **Spieler-Trace:** `EnableTrace` startet einen 0,01-s-Timer auf `Trace`; `SelectAttackTrace` liefert eine Box (Halbgröße 25 cm) von Klingen-Socket `Socket` bis `Socket1` an der **momentanen** Klingenposition (`BoxTraceMultiForObjects`). Der Weg zwischen zwei Frames wird nicht geprüft. Bei 30–40 FPS auf dem Deck kann ein schneller Hieb durchrutschen. Zweiter Verdacht für „zu nah“: `TraceCheckObstacle` im `Trace` (ungeprüft).
- **Drehung:** Bei allen NPCs sind `bOrientRotationToMovement`, `bUseControllerDesiredRotation` und `bUseControllerRotationYaw` aus (RotationRate 360). Die Drehung kommt aus Blueprint-Code; Kandidaten: `Combat_RotateToTarget`, Notifies `RotateToPlayerAI`/`GS_RotateToEnemyAI`/`RotateToEnemyAnimation`, Service `BB_SetWalkSpeed` (`UseDistanceRotation?`), Decorator `BTDecorator_KeepInCone`.
- `Character_CombatState`: 0 Attacking, 1 Parry, 2 Idle, 3 DodgeBackward, 4 DodgeForward, 5 TempKnocked, 6 KO, 7 Strafe, 8 DefenceMode, 9 WasHit, 10 Taunting, 11 HeavyAttack, 12 SpecialAttack, 13 MovingToTarget, 14 DrawWeapon, 15 RotateToTarget, 16 Roaming.
- Beispiel Trefferfenster: `Attack_Move_med_Ldown_1_Montage` AttackTrace bei t=0,60 s, Dauer 0,18 s (`rekit ue notifies`).

Live (Brücke RekitBridge, Arena 1 gegen 1, 2026-10-25):

- `SetValueAsBool(FName("DefenceMode?"), true)` am Blackboard des Gegners → er **greift nicht mehr an**; zurückgesetzt → er greift wieder an (P beobachtet). Währenddessen folgte er nur und tat nichts (P).
- Treffer-Protokoll: drei Treffer mit Taumler in 3,3 s (Abstände 1,2 s und 2,1 s) vom selben Gegner – die Kette, gemessen.
- `GotHit`-Parameter p6 (Attacker) ist direkt der **Gegner-Controller** (`GS_AI_NPCController_C`), also das Objekt mit dem Blackboard.
- Im Protokoll erscheint `Reaction` vor dem umschließenden `GotHit` → Hooks feuern nach der Funktion.

## Vom Design festgelegt

- UE4SS-Lua-Mod (C), Arbeitsname **Fair Combat**, Repo `ash-and-steel-mods/fair-combat` (C; Name für Nexus später mit Pascal).
- Angriffssperre der Gegner über den Blackboard-Schlüssel `DefenceMode?` (C, live bestätigt) – sofern nichts im Spiel den Schlüssel selbst nutzt.
- Bogenschützen unverändert bis auf „kein neuer Taumler im Fenster“ (P).
- Einstelldatei, englische Texte, Nexus-Release, wenn es gut läuft (P).

## Dem Builder überlassen

- Wie Taumelfenster und „kein zweiter Folgetreffer“ technisch durchgesetzt werden, obwohl Hooks erst nach `GotHit` feuern (z. B. Zustand nach dem ersten Treffer setzen, laufende Kombo-Montage des Gegners abbrechen, `invincibleFrame?` gezielt nutzen) – solange Schaden anderer Gegner weiter ankommt und nichts pro Frame gehookt wird.
- Wie wartende Gegner Abstand halten und umkreisen (BT-Schlüssel wie `Strafing?`, eigene Bewegungsbefehle, Verspotten auslösen).
- Wie das Angriffsrecht vergeben wird (wer zuerst, Nähe, Rotation) und wie Gegner erkannt werden, die gerade kämpfen (Blackboard `Status` = 6).
- Technik für Drehbremse, Wind-up und die Prüfung des Klingenwegs zwischen Frames; Messungen dafür über die Brücke.
- Reihenfolge der Umsetzung. Vorschlag (C): 1 Taumel-Kette → 2 Gegnerverhalten → 4 Drehung → 5 Wind-up → 3 Treffer, jedes Ziel als eigener Testschritt mit Pascal.
- Standardwerte; Pascal stimmt sie im Spiel ab.

## Offen / zu prüfen

- Schreibt eine ungecachte NPC-Klasse `DefenceMode?` selbst? (`rekit ue fetch 'Characters/**'` in Teilen, dann `refs`.)
- Warum der Gegner nach der Freigabe „überrollte“ (aufgestaute Zähler `ComboAttackCounter`/`SimpleAttackCounter`, Ausdauer, oder Zufall).
- Gilt der Behavior Tree für alle menschlichen Gegner (Banditen, Arena, Wachen) oder gibt es Varianten? Wie greifen die Tier-Trees an, und welcher Hebel sperrt dort einen Angriff?
- Bosse und geskriptete Kämpfe: Eine Angriffssperre darf ihre Abläufe nicht kaputt machen (C: Bosse zunächst ausnehmen, wenn erkennbar).
- Wie stark ein langsamerer Vorlauf das Timing von Parry/Perfect Parry verschiebt (Parry-Fenster hängt an Gegner-Notifies).
