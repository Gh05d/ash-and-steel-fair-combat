#!/usr/bin/env python3
"""Builds the Nexus header (1920x720) and thumbnail (900x506) from the art in docs/art/.
Title style matches Pascal's other Nexus mods: cream-gold serif title with dark brown outline, italic subtitle."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
FONTS = Path("/usr/share/fonts/truetype/dejavu")
TITLE_FONT = FONTS / "DejaVuSerifCondensed-Bold.ttf"
SUB_FONT = FONTS / "DejaVuSerifCondensed-Italic.ttf"
FILL, OUTLINE, SUB = (252, 208, 128), (60, 12, 0), (230, 220, 200)
TITLE, SUBTITLE = ("FAIR", "COMBAT"), "No More Stunlocks"


def cover(img, w, h, y_bias=0.5):
    """Scale to cover w x h, then crop (y_bias 0 = keep top, 1 = keep bottom)."""
    s = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    x0 = (img.width - w) // 2
    y0 = round((img.height - h) * y_bias)
    return img.crop((x0, y0, x0 + w, y0 + h))


def draw_title(img, x, y, size, sub_size, line_gap, stroke):
    d = ImageDraw.Draw(img)
    tf, sf = ImageFont.truetype(str(TITLE_FONT), size), ImageFont.truetype(str(SUB_FONT), sub_size)
    right = 0
    for line in TITLE:
        d.text((x, y), line, font=tf, fill=FILL, stroke_width=stroke, stroke_fill=OUTLINE)
        right = max(right, d.textbbox((x, y), line, font=tf, stroke_width=stroke)[2])
        y += line_gap
    d.text((x + stroke, y + stroke), SUBTITLE, font=sf, fill=SUB, stroke_width=max(2, stroke // 3), stroke_fill=(20, 10, 5))
    return right


header = cover(Image.open(DOCS / "art" / "header-art.png").convert("RGB"), 1920, 720, y_bias=0.6)
r = draw_title(header, 80, 310, 122, 58, 130, 7)
header.save(DOCS / "nexus-header.png")
print("header title right edge:", r)

thumb = cover(Image.open(DOCS / "art" / "thumb-art.png").convert("RGB"), 900, 506)
r = draw_title(thumb, 30, 28, 70, 38, 76, 5)
thumb.save(DOCS / "nexus-thumb.png")
print("thumb title right edge:", r)
