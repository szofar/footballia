#!/usr/bin/env python3
"""Resize source image into all AppIcon sizes and update Contents.json."""
import os, json
from PIL import Image

SOURCE = "/Users/nicholas/Desktop/ChatGPT Image Jul 30, 2026 at 11_25_48 PM.png"
APPICONSET = "Footballia/Footballia/Assets.xcassets/AppIcon.appiconset"

# pixel sizes needed
SIZES = sorted({16, 32, 64, 128, 256, 512, 1024})

src = Image.open(SOURCE).convert("RGB")
# Ensure square crop from centre just in case
w, h = src.size
side = min(w, h)
src = src.crop(((w - side) // 2, (h - side) // 2,
                (w + side) // 2, (h + side) // 2))

os.makedirs(APPICONSET, exist_ok=True)

for px in SIZES:
    out = src.resize((px, px), Image.LANCZOS)
    fname = f"icon_{px}.png"
    out.save(os.path.join(APPICONSET, fname), "PNG")
    print(f"  wrote {fname} ({px}x{px})")

contents = {
  "images": [
    {"idiom": "universal", "platform": "ios", "size": "1024x1024",
     "filename": "icon_1024.png", "scale": "1x"},
    {"idiom": "mac", "scale": "1x", "size": "16x16",   "filename": "icon_16.png"},
    {"idiom": "mac", "scale": "2x", "size": "16x16",   "filename": "icon_32.png"},
    {"idiom": "mac", "scale": "1x", "size": "32x32",   "filename": "icon_32.png"},
    {"idiom": "mac", "scale": "2x", "size": "32x32",   "filename": "icon_64.png"},
    {"idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128.png"},
    {"idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_256.png"},
    {"idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256.png"},
    {"idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_512.png"},
    {"idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512.png"},
    {"idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_1024.png"},
  ],
  "info": {"author": "xcode", "version": 1}
}

with open(os.path.join(APPICONSET, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)
    f.write("\n")

print("Done.")
