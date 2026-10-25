# Fair Combat – Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Taumel-Kette beenden (Ziel 1) und menschlichen Gegnern einen Souls-artigen Angriffsrhythmus geben (Ziel 2, Menschen).

**Architecture:** UE4SS-Lua-Mod `FairCombat`. Eine reine Lua-Regelmaschine (`policy.lua`, ohne UE-Aufrufe, Zeit wird hineingereicht) entscheidet Taumelfenster, Treffer-Budgets, Sperren und Angriffsrecht; sie ist mit Lua 5.4 über Python/`lupa` unit-getestet. `main.lua` ist der Adapter: Hook auf `CombatModule_Player:GotHit` (feuert nach der Funktion), ein 100-ms-Takt im Spiel-Thread, der kämpfende Gegner einsammelt und `DefenceMode?` an ihren Blackboards setzt.

**Tech Stack:** UE4SS v3.0.1-1181 (Lua 5.4), Python 3.12 + `lupa` für Tests, `luaparser` für die Syntaxprüfung, rekit + RekitBridge für Messungen.

**Spec:** `docs/superpowers/specs/2026-10-25-fair-combat-design.md`

Folgepläne (nicht hier): Tiere, Drehung, Wind-up, Treffer-Zuverlässigkeit, Release.

## Global Constraints

- Kein `LoopAsync`, kein `ExecuteWithDelay`; nur `LoopInGameThreadWithDelay` / `ExecuteInGameThreadWithDelay`.
- Keine Hooks auf häufig feuernde BP-Funktionen (nichts pro Frame / pro Trace-Tick). Erlaubt: `GotHit`, `Reaction`, `Knock` des Spielers (einmal pro Treffer).
- Hooks auf Spiel-Blueprints über `RegisterHook("/Script/Engine.PlayerController:ClientRestart", …)` registrieren, plus direkter Versuch beim Laden (Strg+R).
- Keine Spieldaten aus `../research/` im Repo. Namen, Pfade, kurze Ausschnitte ok.
- Englische Kommentare/Texte im Mod (Nexus). Jedes Ziel einzeln abschaltbar in `config.lua`.
- Deck: vor jeder Änderung im Spielordner fragen, ob Pascal spielt; vor Tests Spielstände sichern. Claude startet das Spiel nicht und drückt keine Tasten.
- Deploy aufs Deck blockt der Auto-Mode-Classifier bei Claude („Remote Shell Writes“) → Pascal führt `! scripts/deploy-deck.sh` aus.

## Review Focus

1. Gegner stirbt, flieht oder verlässt den Kampf, während er gesperrt ist → `DefenceMode?` wird zurückgesetzt; kein NPC bleibt dauerhaft passiv (auch beim Abschalten des Mods / Strg+R). Test: `test_forget_releases_lock` (Task 2), Rückbau in Task 4.
2. Gegner, die nicht den Spieler bekämpfen (Wachen gegen Banditen, Arena-Zuschauer) werden nicht angefasst. Test: `test_roles_ignore_non_player_targets` (Task 2).
3. 1 gegen 1 wird nicht schwächer als nötig: ein einzelner Nahkämpfer hat immer das Angriffsrecht, sofern nicht gesperrt. Test: `test_single_enemy_attacks` (Task 2).
4. Angriffsrecht flackert nicht zwischen gleich weit entfernten Gegnern hin und her. Test: `test_attack_slot_is_sticky` (Task 2).
5. Laden eines Spielstands / Tod des Spielers mitten im Fenster → Zustand leer, keine Fehler aus ungültigen Objekten. Test: `test_reset_clears_everything` (Task 2), `IsValid`-Prüfungen in Task 4.

---

### Task 1: Repo-Gerüst und Test-Harness

**Files:**
- Create: `mod/FairCombat/enabled.txt`, `mod/FairCombat/Scripts/main.lua`, `mod/FairCombat/Scripts/config.lua`, `mod/FairCombat/Scripts/policy.lua` (Stub), `mod/FairCombat/README.txt`
- Create: `scripts/deploy-deck.sh`, `scripts/package.py`, `tests/run.sh`, `tests/requirements.txt`, `tests/test_policy.py`, `CLAUDE.md`

**Interfaces:**
- Produces: `config.lua` gibt eine Tabelle zurück (Werte unten); `policy.lua` gibt ein Modul mit `Policy.new(cfg)` zurück. `tests/run.sh` legt `tests/.venv` an (gitignored) und führt `python -m unittest discover -s tests` aus. Test-Helfer `load_policy(cfg_overrides)` in `tests/test_policy.py` lädt `policy.lua` über `lupa.lua54.LuaRuntime`.

- [ ] Step 1: Test `test_policy_module_loads` (lädt `policy.lua`, `Policy.new(cfg)` liefert eine Tabelle) und `test_lua_syntax` (alle `Scripts/*.lua` parsen mit `luaparser`) schreiben.
- [ ] Step 2: `tests/run.sh` → FAIL (Modul fehlt).
- [ ] Step 3: Gerüst anlegen. `config.lua`-Standardwerte (aus dem Spec): `staggerWindow = 1.5`, `recoverBuffer = 0.5`, `knockWindow = 3.0` (vorläufig, in Task 3 gemessen), `attackers = 1`, `ready = 1`, `comboBackoff = 1.5`, `tickMs = 100`, Schalter `antiStunlock = true`, `attackRights = true`, `debug = false`. `main.lua` nach Muster `../camp-everywhere/mod/CampEverywhere/Scripts/main.lua` (VERSION `0.1.0`, `log`/`dbg`, `require("config")`, `require("policy")`). `deploy-deck.sh`/`package.py` nach Camp-Everywhere-Muster mit Mod-Namen `FairCombat`.
- [ ] Step 4: `tests/run.sh` → PASS.
- [ ] Step 5: Commit `feat: FairCombat skeleton and Lua test harness`.

### Task 2: Regelmaschine `policy.lua`

**Files:** Modify `mod/FairCombat/Scripts/policy.lua`; Test `tests/test_policy.py`

**Interfaces (Produces):**
- `Policy.new(cfg) -> p`
- `p:hit(now, attacker, reaction, ranged)` – `attacker` ist ein String-Schlüssel (voller Objektname des Controllers), `reaction` ∈ `"stagger"|"knock"|"none"`, `ranged` bool. Meldet einen Treffer, der beim Spieler angekommen ist.
- `p:protection(now) -> "stagger"|"knock"|nil` – aktives Schutzfenster.
- `p:mayHit(now, attacker, ranged) -> bool` – darf ein weiterer Treffer dieses Angreifers jetzt ankommen (Budget im Fenster; Fernkämpfer immer true).
- `p:mayStagger(now) -> bool` – false im Fenster.
- `p:comboEnded(now, attacker)` – Gegner muss `cfg.comboBackoff` Sekunden warten.
- `p:roles(now, enemies) -> {[id] = "attack"|"ready"|"wait"|"free"}` – `enemies` = Liste `{id=, dist=, ranged=, targetsPlayer=}`. Fernkämpfer → `"free"`; nicht den Spieler bekämpfend → kein Eintrag.
- `p:forget(id)`, `p:reset()`.

Regeln (Spec Ziel 1/2): Taumler bei `t` → Fenster bis `t + staggerWindow`; Verursacher hat 1 Folgetreffer; nach dem Folgetreffer (oder ohne ihn) gesperrt bis Fensterende `+ recoverBuffer`; jeder andere Nahkämpfer 1 Treffer im Fenster; Knock analog mit `knockWindow`. Angriffsrecht: höchstens `attackers` mit `"attack"`, `ready` mit `"ready"`, Rest `"wait"`, nach Abstand; gesperrte/zurückweichende Gegner nie `"attack"`; ein Inhaber behält seinen Platz, bis er gesperrt wird, zurückweicht oder verschwindet.

- [ ] Step 1: Tests schreiben: `test_stagger_opens_window` (hit 0.0 A stagger → protection(1.0)=="stagger", protection(1.6)==nil, mayStagger(1.0)==false), `test_causer_gets_one_followup` (A stagger 0.0, mayHit(0.5,A)==true, hit(0.5,A,"none"), mayHit(0.8,A)==false), `test_causer_locked_until_recovered` (danach roles bei 1.9 ≠ attack, bei 2.1 == attack), `test_other_enemy_one_hit_in_window`, `test_ranged_not_budgeted` (mayHit für ranged im Fenster immer true, roles → "free"), `test_knock_window` (knock → protection=="knock" bis 3.0), `test_roles_by_distance` (3 Nahkämpfer → attack/ready/wait), `test_attack_slot_is_sticky`, `test_single_enemy_attacks`, `test_roles_ignore_non_player_targets`, `test_combo_backoff` (comboEnded 0.0 → nicht attack bis 1.5), `test_forget_releases_lock`, `test_reset_clears_everything`.
- [ ] Step 2: `tests/run.sh` → FAIL.
- [ ] Step 3: `policy.lua` implementieren.
- [ ] Step 4: `tests/run.sh` → PASS.
- [ ] Step 5: Commit `feat(policy): stagger windows, hit budgets, attack rights`.

### Task 3: Messung und Mechanismus (live, mit Pascal)

**Files:** Create `docs/findings.md`

Fragen, jeweils mit Brücke (`rekit ue bridge …`) und statisch (`rekit ue bp CombatModule_Player func …`):
1. Hook-Zeitpunkt: feuert der `RegisterHook`-Callback auf BP-Funktionen vor oder nach der Funktion? (Live-Befund: nach.) Endgültig prüfen mit `trace hook …:DisableInvincibleFrame` und Lesen von `invincibleFrame?` im Callback.
2. **Wie wird ein Taumler/Treffer verhindert?** Kandidaten: (a) `invincibleFrame?` am Spieler-Kampfmodul setzen, solange kein weiterer Treffer erlaubt ist – blockt `GotHit` ganz; (b) für „Schaden ja, Taumler nein“ den Taumelzweig in `Reaction` über einen Zustand umgehen (`ShouldBeKnocked?`, `FinishingHit`, `CombatState` lesen) oder die gerade gestartete Treffer-Montage sofort beenden (`StopAnimMontage` am Spieler, im `GotHit`-Post-Hook). Entscheidung: der Weg, der Schaden, Tod und Animation korrekt lässt.
3. Woran erkennt der Mod Taumler vs. Niederschlag im Post-Hook? (`Reaction` → `GitHit` vs. `Knock`; `CombatState` 5 TempKnocked/6 KO; welche Montage läuft.) Wie lange dauert Boden + Aufstehen (→ `knockWindow`)?
4. Ist der Angreifer ein Fernkämpfer? (Waffen-/Overlay-Zustand am Gegner, `gs_checkrangeweapon`-Logik.)
5. Kombo-Ende eines Gegners erkennen (Montage-Ende von `AI_C_AttackCombo`, `ComboAttackCounter` im Blackboard).
6. „Bekämpft den Spieler“: Blackboard `Target` == Spieler-Pawn.

- [ ] Step 1: Statische Antworten zu 2–6 vorbereiten und in `docs/findings.md` festhalten.
- [ ] Step 2: Pascal fragen, ob er spielt; Spielstände sichern; Messrunde in der Arena / mit Banditen nach Liste in `docs/findings.md`.
- [ ] Step 3: Entscheidungen in `docs/findings.md` eintragen (Mechanismus, `knockWindow`-Wert).
- [ ] Step 4: Commit `docs: live findings for stagger suppression`.

### Task 4: Adapter Ziel 1 (Taumel-Kette)

**Files:** Modify `mod/FairCombat/Scripts/main.lua`

**Interfaces:** Consumes `Policy` (Task 2), Mechanismus aus `docs/findings.md` (Task 3).

- [ ] Step 1: Post-Hook `GotHit` → `p:hit(...)` mit Reaktion aus Task-3-Erkennung; Schutz durchsetzen nach Task-3-Mechanismus; bei `mayHit == false` den nächsten Treffer dieses Angreifers verhindern.
- [ ] Step 2: Rückbau: beim Laden (`ClientRestart`) und Strg+R `p:reset()` und alle `DefenceMode?` des Mods zurücksetzen.
- [ ] Step 3: `tests/run.sh` (Syntax + Policy) → PASS.
- [ ] Step 4: Pascal deployt (`! scripts/deploy-deck.sh`), testet 2–3 Gegner: keine Kette, Verursacher landet höchstens 1 Folgetreffer, Schaden kommt an, Tod funktioniert. `debug = true` loggt jede Entscheidung in `UE4SS.log`.
- [ ] Step 5: Commit `feat: anti-stunlock windows`.

### Task 5: Adapter Ziel 2 (Angriffsrecht, Menschen)

**Files:** Modify `mod/FairCombat/Scripts/main.lua`

- [ ] Step 1: Takt `LoopInGameThreadWithDelay(cfg.tickMs)`: alle `GS_AI_NPCController_C` mit Blackboard `Status == 6` und Ziel = Spieler einsammeln (`IsValid` prüfen), Abstand, Fernkampf; `p:roles(...)`; `DefenceMode?` = true für `ready`/`wait`/gesperrt, false für `attack`/`free`; nur Werte schreiben, die der Mod selbst gesetzt hat.
- [ ] Step 2: Kombo-Ende (Task 3/5) → `p:comboEnded`.
- [ ] Step 3: `tests/run.sh` → PASS; Pascal testet: 3 Banditen, nur einer greift an, Wechsel nach Sperre/Kombo, 1 gegen 1 unverändert, Bogenschütze schießt frei.
- [ ] Step 4: Commit `feat: attack rights for human enemies`.

### Task 6: Natürliches Warten

**Files:** Modify `mod/FairCombat/Scripts/main.lua`; `docs/findings.md`

- [ ] Step 1: Mechanismus finden (statisch + Brücke): Blackboard `Strafing?`/`StrafingNoObstacles?`, Service `BB_Strafe`, `AIController:MoveToLocation` auf einen Punkt im Abstand `waitDistance = 400` (cm) seitlich zum Spieler, gelegentlich `AI_C_TauntCustom`-Verhalten.
- [ ] Step 2: Umsetzen für `ready` (nah, 250 cm) und `wait` (400 cm).
- [ ] Step 3: Pascal testet: Wartende kreisen/halten Abstand statt stumm zu folgen; kein „Überrollen“ nach Freigabe (Zähler `ComboAttackCounter`/`SimpleAttackCounter` beim Freigeben prüfen).
- [ ] Step 4: Commit `feat: waiting enemies circle and keep distance`.
