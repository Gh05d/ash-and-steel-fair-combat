# Fair Combat – Mod für Of Ash and Steel

Pascals Combat-Mod: Taumel-Ketten beenden und Gegnern einen Souls-artigen Kampfrhythmus geben (Menschen und Tiere), dazu zuverlässigere Treffer (beide Seiten), langsameres Zurückdrehen, lesbarer Wind-up und Treffer-Feedback (Ziel 6: Trefferstopp 60 ms, Treffer-Sounds 90 %, Liste in `hitsounds.lua`).

- **Design (freigegeben 2026-10-25):** `docs/superpowers/specs/2026-10-25-fair-combat-design.md`. Was dort mit (P) markiert ist, hat Pascal gesagt; (C) ist Claudes Entscheidung.
- **Plan Phase 1** (Ziel 1 + Ziel 2 für Menschen): `docs/superpowers/plans/2026-10-25-fair-combat-phase1.md`. Fortschritt im git-ignorierten Ledger `.superpowers/sdd/…/progress.md`.
- **Live-Befunde:** `docs/findings.md`.
- **v1.0.0 released 2026-10-26, am 2026-10-28 mit Treffer-Feedback neu veröffentlicht** (altes Release + Tag gelöscht, `release.sh` neu) auf GitHub `Gh05d/ash-and-steel-fair-combat` (öffentlich, Branch `master`, MIT); Push per SSH ging. Der erste Nexus-Upload-Run ist erwartungsgemäß fehlgeschlagen: Pascal legt die Nexus-Seite an und lädt das erste Zip von Hand hoch, danach Repo-Variable `NEXUSMODS_FILE_ID` + Secret `NEXUSMODS_API_KEY` (Secrets setzen blockt der Classifier → Pascal). Den gescheiterten Run nicht neu starten. Texte: `README.md`, `docs/nexus-description.bbcode`; Bilder: `docs/nexus-art-prompts.md` → `scripts/make_nexus_images.py`. Ziel 3 gemessen, kein Handlungsbedarf (eigene Treffer < 1 m: 23/24). Für 1.0.1 zurückgestellt: siehe Ledger („minor (deferred)“).

## Aufbau

- `mod/FairCombat/Scripts/main.lua`: UE4SS-Adapter (Hooks, Takt, Blackboards). `VERSION` steht hier.
- `mod/FairCombat/Scripts/policy.lua`: reine Regelmaschine ohne Unreal-Aufrufe, Zeit in Sekunden wird übergeben.
- `mod/FairCombat/Scripts/config.lua`: alle Einstellungen für Nutzer (englisch kommentiert).
- Tests: `tests/run.sh` (legt `tests/.venv` mit `lupa` = echtes Lua 5.4 und `luaparser` an; testet `policy.lua` und die Syntax aller Scripts).
- Aufs Deck: `scripts/deploy-deck.sh` (schaltet `debug` ein; `DEBUG=0` = Release-Fassung), dann im Spiel Strg+R. Claude deployt nach dem Commit selbst (Freigabe von Pascal); blockt der Classifier, macht es Pascal per `! scripts/deploy-deck.sh`.
- Paket: `scripts/package.py` → `dist/FairCombat-<version>.zip` (bricht ab, wenn `debug = true`).

## Regeln

- UE4SS-Regeln, Deck-Regeln, SSH-Wege und Release-Ablauf wie in `../camp-everywhere/CLAUDE.md`: kein `LoopAsync`/`ExecuteWithDelay` (erlaubt: `LoopInGameThreadWithDelay`, `ExecuteInGameThreadWithDelay`), keine Hooks auf häufig feuernde BP-Funktionen, Hooks über `ClientRestart` registrieren; vor jeder Änderung im Spielordner fragen, ob Pascal spielt; vor Tests Spielstände sichern.
- **UE4SS v3.0.1-1181 ruft Hooks auf Blueprint-Funktionen erst nach der Funktion auf** (live gemessen 2026-10-25): ein Treffer lässt sich im Hook nicht mehr verhindern, nur der nächste.
- Keine Spieldaten aus `../research/` in dieses Repo (öffentlich, sobald veröffentlicht). Namen, Pfade, kurze Ausschnitte sind ok.
- Pascal testet selbst im Spiel; Claude startet nichts und drückt keine Tasten.

## Werkzeuge

- Asset-Recherche: Skill `game-re-unreal` (`rekit`, Konfiguration `../rekit.toml`). Gegner-KI: `rekit ue bt BaseNPC_AI_Controller`, Enums: `rekit ue enum Character_CombatState`.
- Laufzeit: RekitBridge (`rekit ue bridge send …`, `trace hook …`) – ist auf dem Deck installiert. Gegner-Controller `GS_AI_NPCController_C`, Blackboard über `.Blackboard`, Werte per `GetValueAsBool(FName("…"))`/`SetValueAsBool`.
- Brücken-Experimente: Lua-Datei ohne `--`-Kommentare schreiben (wird zu einer Zeile), senden mit `rekit ue bridge send "lua $(tr '\n' ' ' < datei.lua)"`; Zustand in eine globale Tabelle (`FC_X = FC_X or {}`), damit erneutes Senden nur Funktionen ersetzt. `bridge send ping` hängt, wenn das Spiel aus ist → immer mit `timeout 20`. Vor dem Deploy das Experiment abschalten (Hooks überleben bis Strg+R).
- Spiel-Sounds anhören: `.uasset`/`.uexp` per repak auf dem Deck entpacken (wie `../tools/oas-extract.sh`), der Ogg-Vorbis-Stream liegt direkt in der `.uexp` (ab `OggS`, keine `.ubulk`). Ergebnisse nur nach `../research/`, nie veröffentlichen.
