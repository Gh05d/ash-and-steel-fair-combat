# Nexus-Bilder: Astra-Prompts

Ablauf wie bei Camp Everywhere und Gothic Lockpicking:
1. Pascal erzeugt mit Astra zwei Bilder **ohne Text**. Sie kommen als `docs/art/header-art.png` (breit) und `docs/art/thumb-art.png` (16:9) ins Repo.
2. `python3 scripts/make_nexus_images.py` setzt den Titel „FAIR / COMBAT“ und den Untertitel „No More Stunlocks“ links ins Bild. Das ergibt `docs/nexus-header.png` (1920×720) und `docs/nexus-thumb.png` (900×506).
3. Der Titel steht **links**, die linke Bildhälfte muss also ruhig und dunkel bleiben. Das Motiv kommt nach rechts.

## Header (breit, Seitenverhältnis 8:3, z. B. 2400×900)

> Dark medieval fantasy, cinematic wide shot of a lone sword fighter in worn leather armor holding his ground against three bandits in a misty forest clearing at dusk. One bandit lunges with a rapier while the other two circle at a distance with raised weapons, waiting their turn. The hero is mid side-step, the rapier thrust missing him. Warm low sunlight from the right, cold blue mist, dust and sparks in the air. Gritty low-fantasy style like Gothic 2, Kingdom Come and Dark Souls, muted earthy colors, painterly realism, dynamic but readable composition. Fighters placed on the right half of the image, the left half is dark misty forest and shadow. No text, no letters, no watermark.

## Thumbnail (16:9, z. B. 1600×900)

> Dark medieval fantasy, close dramatic shot of a sword fighter in leather armor sidestepping a lunging rapier, the thin blade passing just past his shoulder, his own longsword raised for the counter. Bright rim light on both blades, deep shadows, sparks. Gritty low-fantasy style like Gothic 2 and Dark Souls, muted brown and amber tones with a touch of cold blue, painterly realism, strong contrast. Action on the right side of the image, the top left corner dark and calm for a title. No text, no letters, no watermark.

Negativ-Prompt (falls Astra einen hat): `text, letters, logo, watermark, modern, sci-fi, bright colors, cartoon, blurry, extra limbs`
