#!/usr/bin/env python3
"""Draw a "Googlebook VM" launcher icon (install_launcher.sh WALLPAPER uses it; the shipped icon is googlebook-vm.png): a flat laptop with a wallpaper on its screen, 256x256, transparent background.
  python3 make_icon.py WALLPAPER OUT.png
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling for smooth edges
N = 256 * S


def box(x0, y0, x1, y1):
    return [x0 * S, y0 * S, x1 * S, y1 * S]


def main(wallpaper, out):
    icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(box(30, 182, 226, 196), 8 * S, fill=(0, 0, 0, 90))
    icon = Image.alpha_composite(icon, shadow.filter(ImageFilter.GaussianBlur(8 * S)))
    # screen: the wallpaper cropped to fill, rounded corners
    sx0, sy0, sx1, sy1 = 40, 60, 216, 172
    w, h = (sx1 - sx0) * S, (sy1 - sy0) * S
    wp = Image.open(wallpaper).convert("RGBA")
    k = max(w / wp.width, h / wp.height)
    wp = wp.resize((round(wp.width * k), round(wp.height * k)), Image.LANCZOS)
    left, top = (wp.width - w) // 2, (wp.height - h) // 2
    wp = wp.crop((left, top, left + w, top + h))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], 12 * S, fill=255)
    icon.paste(wp, (sx0 * S, sy0 * S), mask)
    # base with the lid notch
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle(box(22, 172, 234, 186), 6 * S, fill=(10, 37, 84, 255))
    d.rectangle(box(22, 172, 234, 178), fill=(10, 37, 84, 255))
    d.rounded_rectangle(box(104, 172, 152, 176), 2 * S, fill=(226, 236, 248, 255))
    icon.resize((256, 256), Image.LANCZOS).save(out, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
