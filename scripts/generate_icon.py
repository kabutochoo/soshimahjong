#!/usr/bin/env python3
"""Generate the original Soshima icon (requires Pillow only)."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    destination = root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    scale = 3
    size = 1024
    background = Image.new("RGB", (size, size))
    drawing = ImageDraw.Draw(background)
    # Full square; iOS supplies the outer corner mask.
    for y in range(size):
        fraction = y / (size - 1)
        color = tuple(round(a + (b - a) * fraction) for a, b in zip((207, 36, 49), (173, 17, 33)))
        drawing.line((0, y, size, y), fill=color)
    image = background.resize((size * scale, size * scale))

    def rect(box):
        return tuple(int(coordinate * scale) for coordinate in box)

    shadow = Image.new("RGBA", image.size)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(rect((288, 188, 760, 884)), radius=67 * scale, fill=(65, 0, 10, 58))
    shadow = shadow.filter(ImageFilter.GaussianBlur(20 * scale))
    image = Image.alpha_composite(image.convert("RGBA"), shadow)
    draw = ImageDraw.Draw(image)

    # One original mahjong-tile silhouette with a restrained ivory edge.
    draw.rounded_rectangle(rect((268, 162, 756, 864)), radius=64 * scale, fill="#DDD7CC")
    draw.rounded_rectangle(rect((268, 150, 756, 836)), radius=64 * scale, fill="#FFFDF7")
    draw.rounded_rectangle(rect((282, 164, 742, 822)), radius=51 * scale, outline="#EEE8DF", width=2 * scale)

    # Circle-suit motif; the three marks below suggest score totals.
    red = "#C71A29"
    draw.ellipse(rect((408, 275, 616, 483)), fill=red)
    draw.ellipse(rect((442, 309, 582, 449)), fill="#FFFDF7")
    draw.ellipse(rect((485, 352, 539, 406)), fill=red)
    for left, right, y in ((386, 638, 580), (416, 608, 638), (448, 576, 696)):
        draw.rounded_rectangle(rect((left, y, right, y + 25)), radius=12 * scale, fill=red)

    image = image.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    image.save(destination, optimize=True)
    assert image.size == (1024, 1024)
    assert image.mode == "RGB"
    print(destination)


if __name__ == "__main__":
    main()
