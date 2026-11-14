#!/usr/bin/env python3
"""Paints the mods' stylized art: an ignited photon sword, drawn flat with a glowing blade.

    python3 tools/gen_art.py [--color NAME]

Writes, for every mod in the repo (they share one look):
  <Mod>/preview.png                     256x256 Workshop thumbnail
  <Mod>/Contents/mods/<Mod>/42/poster.png   256x256 mod list poster
  <Mod>/Contents/mods/<Mod>/42/icon.png     32x32 mod list icon (transparent)

The hilt is the model's own silhouette (gen_models.hilt_profile) and paint bands, widened so it
reads at icon size; the blade is gen_models' default palette color unless --color picks another.
Everything is drawn upright at 4x, turned 45 degrees, and downscaled for clean edges. Needs Pillow
and numpy (for gen_models).
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_models import BLADE_PROFILE, BLADE_RADIUS, PALETTE, hilt_profile, mix  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MODS = ("PhotonSword", "PhotonSwordForms", "PhotonSwordALife", "PhotonSwordBandits")
SS = 4  # supersampling
POMMEL_Y = hilt_profile()[0][0]
TIP_Y = BLADE_PROFILE[-1][0]
EMITTER_Y = BLADE_PROFILE[0][0]
OUTLINE = (8, 10, 18)


def render_sword(size, color, radial, glow, fill=0.9):
    """The sword upright (tip up) on a transparent square canvas size*SS wide, then turned 45
    degrees so the tip points to the top right. radial widens the hilt and blade; glow scales the
    blade's halo."""
    side = size * SS
    k = fill * side * math.sqrt(2) / (TIP_Y - POMMEL_Y)  # px per meter along the blade
    mid = (POMMEL_Y + TIP_Y) / 2
    big = int(side * math.sqrt(2)) + 2  # room to turn without clipping
    cx = big / 2

    def row(y):
        return big / 2 - (y - mid) * k

    def across(r):
        return r * k * radial

    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    # Blade: a soft halo in the blade color, the blade itself lifted toward white, and a white core.
    blade_w = across(BLADE_RADIUS) * 2
    top, bottom = row(TIP_Y) + blade_w / 2, row(EMITTER_Y)

    def capsule(draw, width, fill_color):
        draw.line([(cx, top), (cx, bottom)], fill=fill_color, width=int(width))
        draw.ellipse([cx - width / 2, top - width / 2, cx + width / 2, top + width / 2], fill=fill_color)

    for width, blur, alpha in ((3.2, 0.9, 150), (1.9, 0.45, 210), (1.25, 0.18, 255)):
        halo = Image.new("RGBA", img.size, color + (0,))
        mask = Image.new("L", img.size, 0)
        capsule(ImageDraw.Draw(mask), blade_w * width * glow, alpha)
        mask = mask.filter(ImageFilter.GaussianBlur(blade_w * blur * glow))
        halo.putalpha(mask)
        img = Image.alpha_composite(img, halo)
    draw = ImageDraw.Draw(img)
    capsule(draw, blade_w, mix(color, (255, 255, 255), 0.45) + (255,))
    capsule(draw, blade_w * 0.5, (255, 255, 255, 255))

    # Hilt: the lathe profile as a silhouette, outlined, filled with the model's paint bands.
    profile = hilt_profile()
    outline_pts = [(cx + across(r), row(y)) for y, r in profile]
    outline_pts += [(cx - across(r), row(y)) for y, r in reversed(profile)]
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(outline_pts, fill=255)
    edge = max(3, int(across(0.0035)))
    ring = mask.filter(ImageFilter.MaxFilter(edge * 2 + 1))
    img.paste(Image.new("RGBA", img.size, OUTLINE + (255,)), (0, 0), ring)

    paint = Image.new("RGBA", img.size, (0, 0, 0, 255))
    pd = ImageDraw.Draw(paint)
    wide = across(0.03)

    def band(y0, y1, c, x0=-wide, x1=wide):
        pd.rectangle([cx + x0, row(y1), cx + x1, row(y0)], fill=c)

    band(POMMEL_Y, -0.048, (78, 80, 88))  # pommel steel
    band(-0.048, 0.058, (26, 26, 30))  # rubber grip
    y = -0.045
    while y < 0.055:
        band(y + 0.003, y + 0.007, (58, 58, 64))  # grip ridges
        y += 0.010
    band(0.058, 0.090, (166, 169, 176))  # body
    band(0.0635, 0.0645, (60, 60, 66))  # seam
    band(0.067, 0.085, (34, 34, 40), -across(0.007), across(0.007))  # control plate
    band(0.071, 0.081, (200, 35, 35), -across(0.0038), across(0.0038))  # activation button
    band(0.090, EMITTER_Y, (206, 208, 214))  # emitter shroud
    for i in range(-2, 3):
        x = across(0.0062) * i
        band(0.097, 0.115, (40, 40, 46), x - across(0.0016), x + across(0.0016))  # vent slots

    # Round shading: a highlight down the lit side, a shadow down the other, following the radius.
    shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for (y0, r0), (y1, r1) in zip(profile, profile[1:]):
        if y0 == y1:
            continue
        sd.polygon([(cx - across(r0) * 0.62, row(y0)), (cx - across(r0) * 0.28, row(y0)),
                    (cx - across(r1) * 0.28, row(y1)), (cx - across(r1) * 0.62, row(y1))],
                   fill=(255, 255, 255, 70))
        sd.polygon([(cx + across(r0) * 0.45, row(y0)), (cx + across(r0), row(y0)),
                    (cx + across(r1), row(y1)), (cx + across(r1) * 0.45, row(y1))],
                   fill=(0, 0, 0, 95))
    paint = Image.alpha_composite(paint, shade)
    img.paste(paint, (0, 0), mask)

    # A bloom where the blade leaves the emitter.
    bloom = Image.new("RGBA", img.size, (255, 255, 255, 0))
    bm = Image.new("L", img.size, 0)
    r = blade_w * 1.1 * glow
    ImageDraw.Draw(bm).ellipse([cx - r, bottom - r, cx + r, bottom + r], fill=150)
    bloom.putalpha(bm.filter(ImageFilter.GaussianBlur(r * 0.7)))
    img = Image.alpha_composite(img, bloom)

    img = img.rotate(-45, resample=Image.BICUBIC)
    off = (big - side) // 2
    return img.crop((off, off, off + side, off + side))


def background(size, color):
    """Deep navy, lighter at the center, tinted toward the blade color."""
    side = size * SS
    grad = Image.radial_gradient("L").resize((side, side), Image.BICUBIC)  # 0 center, 255 edge
    inner = mix((22, 28, 52), color, 0.18)
    outer = (5, 6, 12)
    return Image.composite(Image.new("RGBA", (side, side), outer + (255,)),
                           Image.new("RGBA", (side, side), inner + (255,)), grad)


def framed(size, color):
    img = background(size, color)
    img = Image.alpha_composite(img, render_sword(size, color, radial=1.9, glow=1.0, fill=0.8))
    return img.resize((size, size), Image.LANCZOS)


def icon(color):
    # Chunkier and with a tighter halo than the poster, so it reads at 32 pixels.
    return render_sword(32, color, radial=3.2, glow=0.55, fill=0.86).resize((32, 32), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--color", default=next(iter(PALETTE)), choices=PALETTE)
    args = parser.parse_args()
    color = PALETTE[args.color]

    preview = poster = framed(256, color)
    small = icon(color)
    for mod in MODS:
        preview.save(os.path.join(ROOT, mod, "preview.png"), optimize=True)
        info_dir = os.path.join(ROOT, mod, "Contents", "mods", mod, "42")
        poster.save(os.path.join(info_dir, "poster.png"), optimize=True)
        small.save(os.path.join(info_dir, "icon.png"), optimize=True)
    print(f"Wrote preview.png (256), poster.png (256), and icon.png (32) for {len(MODS)} mods "
          f"({args.color} blade)")


if __name__ == "__main__":
    main()
