"""Remove only the connected exterior black background; preserve source RGB.

User explicitly authorized programmatic editing of these originals on 2026-09-11.
Requires Pillow. Example:
  python tools/prepare_bricks_club_badges.py --source-dir C:/Users/Pavel/Downloads
"""
import argparse
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw


def prepare(source: Path, target: Path) -> None:
    rgb = Image.open(source).convert("RGB")
    red, green, blue = rgb.split()
    # Flood-fill from corners, so interior black details are not removed.
    mask = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(
        lambda value: 255 if value < 65 else 0
    )
    for corner in [(0, 0), (rgb.width - 1, 0), (0, rgb.height - 1), (rgb.width - 1, rgb.height - 1)]:
        if mask.getpixel(corner) == 255:
            ImageDraw.floodfill(mask, corner, 128)
    output = rgb.convert("RGBA")
    output.putalpha(mask.point(lambda value: 0 if value == 128 else 255))
    assert output.convert("RGB").tobytes() == rgb.tobytes()
    target.parent.mkdir(parents=True, exist_ok=True)
    output.save(target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/currency/bricks_club"))
    args = parser.parse_args()
    for name, time in {"bc": "13-38-39", "bbc": "13-39-14", "pbc": "13-39-32", "tbc": "13-39-48"}.items():
        prepare(args.source_dir / f"photo_2026-09-06_{time}.jpg", args.output_dir / f"{name}.png")
        print(f"{name}: original RGB preserved, exterior made transparent")
