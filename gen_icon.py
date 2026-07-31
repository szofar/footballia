#!/usr/bin/env python3
"""Resize source image into all AppIcon sizes (macOS + tvOS) and update Contents.json."""
import os, json
from PIL import Image

SOURCE = "/Users/nicholas/Desktop/ChatGPT Image Jul 30, 2026 at 11_25_48 PM.png"
APPICONSET = "Footballia/Footballia/Assets.xcassets/AppIcon.appiconset"

src_orig = Image.open(SOURCE).convert("RGB")

def center_crop(img, target_w, target_h):
    """Crop img to target aspect ratio from the centre, then resize."""
    w, h = img.size
    target_ratio = target_w / target_h
    img_ratio = w / h
    if img_ratio > target_ratio:
        # image is wider than needed — crop sides
        new_w = int(h * target_ratio)
        x0 = (w - new_w) // 2
        img = img.crop((x0, 0, x0 + new_w, h))
    else:
        # image is taller than needed — crop top/bottom
        new_h = int(w / target_ratio)
        y0 = (h - new_h) // 2
        img = img.crop((0, y0, w, y0 + new_h))
    return img.resize((target_w, target_h), Image.LANCZOS)

def square(img, px):
    """Square center-crop + resize."""
    return center_crop(img, px, px)

os.makedirs(APPICONSET, exist_ok=True)

# ── macOS (square) ──────────────────────────────────────────────────────────
mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
for px in mac_sizes:
    out = square(src_orig, px)
    fname = f"icon_{px}.png"
    out.save(os.path.join(APPICONSET, fname), "PNG")
    print(f"  mac  {fname}")

# ── tvOS home screen (400×240) ───────────────────────────────────────────────
for px_w, px_h, label in [(400, 240, "tv_400x240"), (800, 480, "tv_800x480")]:
    out = center_crop(src_orig, px_w, px_h)
    fname = f"icon_{label}.png"
    out.save(os.path.join(APPICONSET, fname), "PNG")
    print(f"  tv   {fname}")

# ── tvOS top shelf (1920×720 wide banner) ────────────────────────────────────
for px_w, px_h, label in [(1920, 720, "tv_topshelf_1920x720"),
                           (3840, 1440, "tv_topshelf_3840x1440")]:
    out = center_crop(src_orig, px_w, px_h)
    fname = f"icon_{label}.png"
    out.save(os.path.join(APPICONSET, fname), "PNG")
    print(f"  tv   {fname}")

# ── Contents.json ────────────────────────────────────────────────────────────
contents = {
  "images": [
    # iOS / App Store
    {"idiom": "universal", "platform": "ios", "size": "1024x1024",
     "filename": "icon_1024.png"},
    # macOS
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
    # tvOS home screen icon
    {"idiom": "tv", "scale": "1x", "size": "400x240",  "filename": "icon_tv_400x240.png"},
    {"idiom": "tv", "scale": "2x", "size": "400x240",  "filename": "icon_tv_800x480.png"},
    # tvOS top shelf
    {"idiom": "tv-top-shelf", "scale": "1x", "size": "1920x720",
     "filename": "icon_tv_topshelf_1920x720.png"},
    {"idiom": "tv-top-shelf", "scale": "2x", "size": "1920x720",
     "filename": "icon_tv_topshelf_3840x1440.png"},
  ],
  "info": {"author": "xcode", "version": 1}
}

with open(os.path.join(APPICONSET, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)
    f.write("\n")

print("Done.")
