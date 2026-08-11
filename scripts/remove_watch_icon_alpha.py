#!/usr/bin/env python3
"""Flatten watchOS app icon onto white background and save as opaque RGB PNG."""

from pathlib import Path

from PIL import Image

ICON_PATH = Path(__file__).resolve().parents[1] / (
    "ios/VigoLockWatch/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
)


def main() -> None:
    image = Image.open(ICON_PATH).convert("RGBA")
    background = Image.new("RGB", image.size, (255, 255, 255))
    background.paste(image, mask=image.split()[3])
    background.save(ICON_PATH, format="PNG")
    print(f"Saved opaque RGB icon: {ICON_PATH}")


if __name__ == "__main__":
    main()
