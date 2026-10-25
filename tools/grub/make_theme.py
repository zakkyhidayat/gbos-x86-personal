#!/usr/bin/env python3
"""Generate the "googlebook-m3" GRUB theme: Material 3 (dark, blue scheme) with M3 Expressive shapes, for a 1920x1200 panel.

  python3 tools/grub/make_theme.py [OUTDIR]        (default tools/grub/googlebook-m3)

Static text (title, subtitle, key hints) is drawn into the background with Adwaita Sans at real weights; only the menu
labels and the countdown use GRUB's own .pf2 fonts (made with grub2-mkfont). Needs Pillow, grub2-mkfont, Adwaita Sans.
"""
import math, os, struct, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 1200
SS = 4  # supersampling for smooth edges
FONT = "/usr/share/fonts/adwaita-sans-fonts/AdwaitaSans-Regular.ttf"
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "googlebook-m3")

# Material 3 dark scheme from a blue seed
C = dict(surface="#111318", container="#1D2024", container_high="#272A2F", primary="#AAC7FF", on_primary="#0A305F",
         primary_container="#284777", secondary_container="#3E4759", on_secondary_container="#DAE2F9",
         tertiary_container="#563E5C", on_surface="#E2E2E9", on_surface_variant="#C4C6D0", outline="#8E9099")

# Layout (px at 1920x1200)
CARD_W, CARD_H, CARD_R = 860, 620, 40
CX, CY = (W - CARD_W) // 2, (H - CARD_H) // 2
PAD = 48
# GRUB draws an item's pixmap box AROUND the item (padding = the corner images' size), so the visible row is
# ITEM_H + 2 * SEL_R tall; every item gets a transparent box of the same size so all rows are spaced alike.
ROW_H, ROW_GAP, SEL_R, ICON = 88, 12, 28, 48
ITEM_H = ROW_H - 2 * SEL_R
ITEM_GAP = ROW_H + ROW_GAP - ITEM_H
MENU_X, MENU_Y, MENU_W = CX + 32, CY + 196, CARD_W - 64
MENU_H = 3 * ROW_H + 2 * ROW_GAP + 8
FOOT_Y = CY + CARD_H - 72


def rgba(hexc, a=255):
    hexc = hexc.lstrip("#")
    return tuple(int(hexc[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def shape(n, amp, r, cx, cy, rot=0.0, steps=720):
    """M3 Expressive "cookie"/"flower": a circle with n soft lobes."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        rr = r * (1 + amp * math.cos(n * (t + rot)))
        pts.append((cx + rr * math.cos(t), cy + rr * math.sin(t)))
    return pts


def background():
    im = Image.new("RGBA", (W * SS, H * SS), rgba(C["surface"]))
    deco = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    d.polygon([(x * SS, y * SS) for x, y in shape(12, 0.055, 520, 260, 170, 0.1)], fill=rgba(C["primary_container"], 150))
    d.polygon([(x * SS, y * SS) for x, y in shape(8, 0.11, 430, 1700, 1060, 0.3)], fill=rgba(C["tertiary_container"], 140))
    d.ellipse([(1580 * SS, 140 * SS), (1740 * SS, 300 * SS)], fill=rgba(C["secondary_container"], 120))
    im = Image.alpha_composite(im, deco)
    # card with a soft shadow
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([(CX * SS, (CY + 10) * SS), ((CX + CARD_W) * SS, (CY + CARD_H + 10) * SS)],
                                         CARD_R * SS, fill=(0, 0, 0, 120))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(28 * SS)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([(CX * SS, CY * SS), ((CX + CARD_W) * SS, (CY + CARD_H) * SS)], CARD_R * SS, fill=rgba(C["container"]))
    im = im.resize((W, H), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    d.text((CX + PAD, CY + 58), "Choose a system", font=font(46, 560), fill=rgba(C["on_surface"]))
    d.text((CX + PAD, CY + 124), "ThinkPad X13 Gen 2i", font=font(21, 420), fill=rgba(C["on_surface_variant"]))
    d.line([(CX + PAD, FOOT_Y - 20), (CX + CARD_W - PAD, FOOT_Y - 20)], fill=rgba(C["container_high"]), width=2)
    hints = [("↑ ↓", "choose"), ("Enter", "start"), ("e", "edit")]
    x = CX + CARD_W - PAD
    f_key, f_txt = font(18, 600), font(18, 400)
    for key, txt in reversed(hints):  # right-aligned key chips
        tw = d.textlength(txt, font=f_txt)
        x -= tw
        d.text((x, FOOT_Y + 2), txt, font=f_txt, fill=rgba(C["on_surface_variant"]))
        kw = d.textlength(key, font=f_key) + 22
        x -= 10 + kw
        d.rounded_rectangle([(x, FOOT_Y - 4), (x + kw, FOOT_Y + 30)], 10, fill=rgba(C["container_high"]))
        d.text((x + 11, FOOT_Y + 1), key, font=f_key, fill=rgba(C["on_surface"]))
        x -= 28
    return im.convert("RGB")


def row_slices(color, r=SEL_R, w=400, h=ROW_H):
    """GRUB 9-slice pixmaps (select_*.png, item_*.png) of a rounded row; color None = transparent."""
    big = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    if color:
        ImageDraw.Draw(big).rounded_rectangle([(0, 0), (w * SS - 1, h * SS - 1)], r * SS, fill=rgba(color))
    p = big.resize((w, h), Image.LANCZOS)
    boxes = dict(nw=(0, 0, r, r), n=(r, 0, r + 1, r), ne=(w - r, 0, w, r), w=(0, r, r, h - r), c=(r, r, r + 1, h - r),
                 e=(w - r, r, w, h - r), sw=(0, h - r, r, h), s=(r, h - r, r + 1, h), se=(w - r, h - r, w, h))
    return {k: p.crop(b) for k, b in boxes.items()}


def icon(kind):
    s = ICON * SS
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([(0, 0), (s - 1, s - 1)], fill=rgba(C["primary"]))
    g, lw = rgba(C["on_primary"]), int(2.6 * SS)
    u = s / 48
    if kind == "googlebook":  # laptop
        d.rounded_rectangle([(13 * u, 14 * u), (35 * u, 30 * u)], 2.5 * u, outline=g, width=lw)
        d.rounded_rectangle([(9 * u, 32 * u), (39 * u, 35.5 * u)], 1.8 * u, fill=g)
    elif kind == "fedora":  # terminal window
        d.rounded_rectangle([(11 * u, 13 * u), (37 * u, 35 * u)], 3 * u, outline=g, width=lw)
        d.line([(16 * u, 20 * u), (21 * u, 24 * u), (16 * u, 28 * u)], fill=g, width=lw, joint="curve")
        d.line([(24 * u, 29 * u), (31 * u, 29 * u)], fill=g, width=lw)
    else:  # settings gear
        cx = cy = 24 * u
        for i in range(8):
            a = i * math.pi / 4
            d.line([(cx + 8 * u * math.cos(a), cy + 8 * u * math.sin(a)), (cx + 13 * u * math.cos(a), cy + 13 * u * math.sin(a))],
                   fill=g, width=int(4.2 * SS))
        d.ellipse([(cx - 9.5 * u, cy - 9.5 * u), (cx + 9.5 * u, cy + 9.5 * u)], outline=g, width=lw)
        d.ellipse([(cx - 3.5 * u, cy - 3.5 * u), (cx + 3.5 * u, cy + 3.5 * u)], fill=g)
    return im.resize((ICON, ICON), Image.LANCZOS)


def mkfont(size, out):
    # Latin, Latin-1/Extended-A and arrows: what menu entries and GRUB's editor show; keeps the fonts small
    subprocess.run(["grub2-mkfont", "-s", str(size), "-r", "0x20-0x7e,0xa0-0x17f,0x2190-0x2193", "-o", out, FONT],
                   check=True, stderr=subprocess.DEVNULL)
    data = open(out, "rb").read()
    i = 0
    while i < len(data):  # PF2 sections: 4-byte name, 4-byte big-endian length, payload; NAME holds the font name
        sec, ln = data[i:i + 4], struct.unpack(">I", data[i + 4:i + 8])[0]
        if sec == b"NAME":
            return data[i + 8:i + 8 + ln].rstrip(b"\0").decode()
        if sec == b"DATA":
            break
        i += 8 + ln
    raise SystemExit("no NAME in " + out)


def main():
    os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)
    background().save(os.path.join(OUT, "background.png"), optimize=True)
    for k, p in row_slices(C["secondary_container"]).items():
        p.save(os.path.join(OUT, "select_%s.png" % k))
    for k, p in row_slices(None).items():
        p.save(os.path.join(OUT, "item_%s.png" % k))
    for name, kind in (("googlebook", "googlebook"), ("fedora", "fedora"), ("efi", "efi")):
        icon(kind).save(os.path.join(OUT, "icons", name + ".png"))
    item_font = mkfont(26, os.path.join(OUT, "item_26.pf2"))
    small_font = mkfont(18, os.path.join(OUT, "small_18.pf2"))
    theme = f"""# googlebook-m3: Material 3 GRUB theme for the ThinkPad X13 Gen 2i (1920x1200). Made by tools/grub/make_theme.py.
title-text: ""
desktop-image: "background.png"
desktop-color: "{C['surface']}"
terminal-font: "{small_font}"
terminal-left: "0"
terminal-top: "0"
terminal-width: "100%"
terminal-height: "100%"
terminal-border: "0"

+ boot_menu {{
  left = {MENU_X}
  top = {MENU_Y}
  width = {MENU_W}
  height = {MENU_H}
  item_font = "{item_font}"
  item_color = "{C['on_surface']}"
  selected_item_font = "{item_font}"
  selected_item_color = "{C['on_secondary_container']}"
  item_height = {ITEM_H}
  item_padding = 4
  item_icon_space = 22
  icon_width = {ICON}
  icon_height = {ICON}
  item_spacing = {ITEM_GAP}
  item_pixmap_style = "item_*.png"
  selected_item_pixmap_style = "select_*.png"
  scrollbar = false
}}

+ label {{
  id = "__timeout__"
  left = {CX + PAD}
  top = {FOOT_Y + 2}
  width = 360
  height = 28
  align = "left"
  font = "{small_font}"
  color = "{C['on_surface_variant']}"
  text = "Starting in %d s"
}}
"""
    open(os.path.join(OUT, "theme.txt"), "w").write(theme)
    print("theme in", OUT, "fonts:", item_font, "/", small_font)


if __name__ == "__main__":
    main()
