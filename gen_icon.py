#!/usr/bin/env python3
"""Rebuild the Apple app-icon asset catalog layout from a source artwork.

The artwork is external, so this script only ever *resizes* and *centre-crops*
it — it never composites, recolours or otherwise edits pixels. It is also
non-destructive: an image that already exists on disk is left untouched (some
of the checked-in crops were framed by hand and must be preserved). Pass
--force to re-derive every image from SOURCE. Contents.json files are always
rewritten.

It writes two asset groups inside Footballia/Footballia/Assets.xcassets:

  AppIcon.appiconset                      macOS ladder + the 1024px iOS icon.
  App Icon & Top Shelf Image.brandassets  tvOS layered icon + top shelf images.

tvOS notes (current Xcode/actool requirements):
  * The brandassets manifest uses a single role, "primary-app-icon", with the
    home-screen (400x240) and App Store (1280x768) stacks told apart by "size".
    The old "app-icon"/"app-icon-app-store" roles are rejected by modern actool.
  * A .imagestack needs at least two layers that have content, and the *last*
    layer with content must be a fully opaque bitmap. Since the artwork is a
    single flat image, it goes in the opaque Back layer and the Front layer is
    a fully transparent bitmap of the same size, which keeps the stack valid
    without inventing new artwork.
"""

import argparse
import json
import os

from PIL import Image

SOURCE = os.path.expanduser(
    "~/Desktop/ChatGPT Image Jul 30, 2026 at 11_25_48 PM.png"
)
ASSETS = "Footballia/Footballia/Assets.xcassets"
APPICONSET = os.path.join(ASSETS, "AppIcon.appiconset")
BRANDASSETS = os.path.join(ASSETS, "App Icon & Top Shelf Image.brandassets")

INFO = {"author": "xcode", "version": 1}

# tvOS home screen and App Store icons, as (stack directory, [(w, h, scale)]).
TV_STACKS = [
    ("App Icon.imagestack", [(400, 240, "1x"), (800, 480, "2x")]),
    ("App Icon - App Store.imagestack", [(1280, 768, "1x")]),
]

TOP_SHELF = [
    ("Top Shelf Image.imageset", [(1920, 720, "1x"), (3840, 1440, "2x")]),
    ("Top Shelf Image Wide.imageset", [(2320, 720, "1x"), (4640, 1440, "2x")]),
]

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def center_crop(img, target_w, target_h):
    """Crop img to the target aspect ratio from the centre, then resize."""
    w, h = img.size
    target_ratio = target_w / target_h
    img_ratio = w / h
    if img_ratio > target_ratio:
        new_w = int(h * target_ratio)
        x0 = (w - new_w) // 2
        img = img.crop((x0, 0, x0 + new_w, h))
    else:
        new_h = int(w / target_ratio)
        y0 = (h - new_h) // 2
        img = img.crop((0, y0, w, y0 + new_h))
    return img.resize((target_w, target_h), Image.LANCZOS)


def write_json(directory, payload):
    """Write Contents.json in Xcode's formatting (2-space, `"key" : value`)."""
    os.makedirs(directory, exist_ok=True)
    text = json.dumps(payload, indent=2, sort_keys=True, separators=(",", " : "))
    with open(os.path.join(directory, "Contents.json"), "w") as f:
        f.write(text + "\n")


def save(path, make, force):
    """Write an image via make() unless it already exists (and not forcing)."""
    if os.path.exists(path) and not force:
        print(f"  keep  {os.path.basename(path)}")
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    make().save(path, "PNG")
    print(f"  write {os.path.basename(path)}")


def build_appiconset(src, force):
    for px in MAC_SIZES:
        save(
            os.path.join(APPICONSET, f"icon_{px}.png"),
            lambda px=px: center_crop(src, px, px),
            force,
        )

    images = [
        {
            "filename": "icon_1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }
    ]
    # macOS wants an explicit ladder; each point size needs a 1x and a 2x asset.
    for pt in (16, 32, 128, 256, 512):
        images.append(
            {
                "filename": f"icon_{pt}.png",
                "idiom": "mac",
                "scale": "1x",
                "size": f"{pt}x{pt}",
            }
        )
        images.append(
            {
                "filename": f"icon_{pt * 2}.png",
                "idiom": "mac",
                "scale": "2x",
                "size": f"{pt}x{pt}",
            }
        )
    write_json(APPICONSET, {"images": images, "info": INFO})


def tv_icon_name(w, h):
    return "icon_tv_appstore_1280x768.png" if (w, h) == (1280, 768) else f"icon_tv_{w}x{h}.png"


def build_layer(stack_dir, layer, variants, artwork, src, force):
    """Write one .imagestacklayer, either the artwork or a transparent sheet."""
    layer_dir = os.path.join(stack_dir, f"{layer}.imagestacklayer")
    content_dir = os.path.join(layer_dir, "Content.imageset")
    write_json(layer_dir, {"info": INFO})

    images = []
    for w, h, scale in variants:
        if artwork:
            name = tv_icon_name(w, h)
            make = lambda w=w, h=h: center_crop(src, w, h).convert("RGB")
        else:
            name = f"transparent_{w}x{h}.png"
            make = lambda w=w, h=h: Image.new("RGBA", (w, h), (0, 0, 0, 0))
        save(os.path.join(content_dir, name), make, force)
        images.append({"filename": name, "idiom": "tv", "scale": scale})

    write_json(content_dir, {"images": images, "info": INFO})


def build_brandassets(src, force):
    for stack, variants in TV_STACKS:
        stack_dir = os.path.join(BRANDASSETS, stack)
        # Back holds the opaque artwork; Front is a transparent parallax sheet.
        build_layer(stack_dir, "Back", variants, True, src, force)
        build_layer(stack_dir, "Front", variants, False, src, force)
        write_json(
            stack_dir,
            {
                "info": INFO,
                "layers": [
                    {"filename": "Front.imagestacklayer"},
                    {"filename": "Back.imagestacklayer"},
                ],
            },
        )

    for imageset, variants in TOP_SHELF:
        directory = os.path.join(BRANDASSETS, imageset)
        wide = "Wide" in imageset
        images = []
        for w, h, scale in variants:
            name = f"icon_tv_topshelf_{'wide_' if wide else ''}{w}x{h}.png"
            save(
                os.path.join(directory, name),
                lambda w=w, h=h: center_crop(src, w, h).convert("RGB"),
                force,
            )
            images.append({"filename": name, "idiom": "tv", "scale": scale})
        write_json(directory, {"images": images, "info": INFO})

    write_json(
        BRANDASSETS,
        {
            "assets": [
                {
                    "filename": "App Icon.imagestack",
                    "idiom": "tv",
                    "role": "primary-app-icon",
                    "size": "400x240",
                },
                {
                    "filename": "App Icon - App Store.imagestack",
                    "idiom": "tv",
                    "role": "primary-app-icon",
                    "size": "1280x768",
                },
                {
                    "filename": "Top Shelf Image.imageset",
                    "idiom": "tv",
                    "role": "top-shelf-image",
                    "size": "1920x720",
                },
                {
                    "filename": "Top Shelf Image Wide.imageset",
                    "idiom": "tv",
                    "role": "top-shelf-image-wide",
                    "size": "2320x720",
                },
            ],
            "info": INFO,
        },
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-derive every image from SOURCE, overwriting hand-framed crops",
    )
    parser.add_argument("--source", default=SOURCE, help="source artwork path")
    args = parser.parse_args()

    src = Image.open(args.source).convert("RGB")
    build_appiconset(src, args.force)
    build_brandassets(src, args.force)
    print("Done.")


if __name__ == "__main__":
    main()
