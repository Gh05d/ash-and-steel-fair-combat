#!/usr/bin/env python3
"""Builds the Nexus release zip: dist/FairCombat-<version>.zip.
Layout starts at the game folder, so extracting into ofAshAndSteel/ puts the mod into ue4ss/Mods/."""
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod" / "FairCombat"
PREFIX = "ofAshAndSteelGame/Binaries/Win64/ue4ss/Mods/FairCombat/"

main = (MOD / "Scripts" / "main.lua").read_text(encoding="utf-8")
version = re.search(r'local VERSION = "([^"]+)"', main).group(1)
if re.search(r"debug = true", (MOD / "Scripts" / "config.lua").read_text(encoding="utf-8")):
    raise SystemExit("debug is on in config.lua - turn it off before packaging")

out = ROOT / "dist" / f"FairCombat-{version}.zip"
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(MOD.rglob("*")):
        if f.is_file():
            z.write(f, PREFIX + f.relative_to(MOD).as_posix())
print(out)
with zipfile.ZipFile(out) as z:
    for i in z.infolist():
        print(f"  {i.file_size:6d}  {i.filename}")
