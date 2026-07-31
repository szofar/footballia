#!/usr/bin/env python3
"""Generate the Android launcher-icon set + Android TV banner from a source image.

Run from the repo root (same place as gen_icon.py):

    python3 gen_android_icon.py

Reads the square source artwork and writes:
  * adaptive icon (mipmap-anydpi-v26) + per-density foreground PNGs
  * legacy square + round launcher PNGs (mipmap-*dpi)
  * a sampled solid background colour (values/ic_launcher_background.xml)
  * the leanback TV banner (drawable-*dpi/banner.png) required by Android TV
"""
import os
from PIL import Image, ImageDraw

SOURCE = "/Users/nicholas/Desktop/ChatGPT Image Jul 30, 2026 at 11_25_48 PM.png"
RES = "android/app/src/main/res"

# --- load + centre-square crop ------------------------------------------------
src = Image.open(SOURCE).convert("RGBA")
w, h = src.size
side = min(w, h)
src = src.crop(((w - side) // 2, (h - side) // 2,
                (w + side) // 2, (h + side) // 2))


def sample_bg_color(img):
    """Most common colour along the border — usually the artwork's backdrop."""
    rgb = img.convert("RGB")
    n = rgb.width
    px = rgb.load()
    edge = []
    for i in range(0, n, max(1, n // 64)):
        edge += [px[i, 0], px[i, n - 1], px[0, i], px[n - 1, i]]
    # bucket to nearest 8 and take the mode
    from collections import Counter
    buck = Counter((r // 8, g // 8, b // 8) for r, g, b in edge)
    (r, g, b), _ = buck.most_common(1)[0]
    return (r * 8, g * 8, b * 8)


BG = sample_bg_color(src)
BG_HEX = "#%02X%02X%02X" % BG
print(f"sampled background colour: {BG_HEX}")


def rd(*parts):
    d = os.path.join(RES, *parts)
    os.makedirs(d, exist_ok=True)
    return d


def save(img, *parts):
    path = os.path.join(RES, *parts[:-1], parts[-1])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print(f"  wrote {os.path.relpath(path)}  ({img.width}x{img.height})")


# --- legacy square + round launcher icons ------------------------------------
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for dpi, px in LEGACY.items():
    sq = src.resize((px, px), Image.LANCZOS)
    save(sq.convert("RGBA"), f"mipmap-{dpi}", "ic_launcher.png")

    # round: circular alpha mask
    mask = Image.new("L", (px, px), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, px - 1, px - 1), fill=255)
    rnd = sq.convert("RGBA")
    rnd.putalpha(mask)
    save(rnd, f"mipmap-{dpi}", "ic_launcher_round.png")

# --- adaptive-icon foreground (image scaled into the 72dp safe zone) ---------
FG = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
SAFE = 0.62  # keep artwork inside the guaranteed-visible centre
for dpi, px in FG.items():
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    inner = int(px * SAFE)
    art = src.resize((inner, inner), Image.LANCZOS).convert("RGBA")
    off = (px - inner) // 2
    canvas.alpha_composite(art, (off, off))
    save(canvas, f"mipmap-{dpi}", "ic_launcher_foreground.png")

# --- adaptive-icon XML + background colour -----------------------------------
adaptive = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background" />\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
    '</adaptive-icon>\n'
)
d = rd("mipmap-anydpi-v26")
for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
    with open(os.path.join(d, name), "w") as f:
        f.write(adaptive)
    print(f"  wrote {os.path.join('mipmap-anydpi-v26', name)}")

d = rd("values")
with open(os.path.join(d, "ic_launcher_background.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{BG_HEX}</color>\n'
            '</resources>\n')
print("  wrote values/ic_launcher_background.xml")

# --- Android TV leanback banner (logo centred on sampled backdrop) -----------
BANNER = {"mdpi": (160, 90), "hdpi": (240, 135),
          "xhdpi": (320, 180), "xxhdpi": (480, 270)}
for dpi, (bw, bh) in BANNER.items():
    banner = Image.new("RGBA", (bw, bh), BG + (255,))
    logo = int(bh * 0.82)
    art = src.resize((logo, logo), Image.LANCZOS).convert("RGBA")
    banner.alpha_composite(art, ((bw - logo) // 2, (bh - logo) // 2))
    save(banner.convert("RGB").convert("RGBA"), f"drawable-{dpi}", "banner.png")

print("Done.")
