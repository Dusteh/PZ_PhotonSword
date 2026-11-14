#!/usr/bin/env python3
"""Paints the mods' stylized art: an ignited photon sword, drawn flat with a glowing blade.

    python3 tools/gen_art.py

Writes, for every mod in the repo:
  <Mod>/preview.png                     256x256 Workshop thumbnail (the poster, titled)
  <Mod>/Contents/mods/<Mod>/42/poster.png   256x256 mod list poster
  <Mod>/Contents/mods/<Mod>/42/icon.png     32x32 mod list icon (transparent)

Each mod has its own blade color, and its own emblem behind the sword: Forms an enso, its slash
trail; the patches the mod they patch, fused with the sword (A-Life a heartbeat the blade spikes,
shared with this repo's other A-Life patches; Bandits a masked bandit lit by the blade).
The hilt is the model's own silhouette (gen_models.hilt_profile) and paint bands, widened so it
reads at icon size. Everything is drawn upright at 4x, turned 45 degrees, and downscaled for clean
edges. Needs Pillow, numpy (for gen_models), and the DejaVu fonts (for the preview titles).
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_models import BLADE_PROFILE, BLADE_RADIUS, PALETTE, hilt_profile, mix  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
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


def glow_line(img, points, color, width, blur, core=True):
    """A glowing polyline on img (in place): a blurred halo in color, then a lighter core."""
    halo = Image.new("RGBA", img.size, color + (0,))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).line(points, fill=200, width=int(width * 3), joint="curve")
    halo.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    img.alpha_composite(halo)
    d = ImageDraw.Draw(img)
    d.line(points, fill=mix(color, (255, 255, 255), 0.35) + (255,), width=int(width), joint="curve")
    if core:
        d.line(points, fill=(255, 255, 255, 255), width=max(1, int(width * 0.35)), joint="curve")


def heartbeat(side, height=0.5):
    """A heartbeat trace across the canvas, its beat where the blade crosses it (the blade runs
    corner to corner, so at x = 1 - height)."""
    x0 = 1 - height
    shape = [(0, 0), (x0 - 0.22, 0), (x0 - 0.17, -0.035), (x0 - 0.12, 0), (x0 - 0.05, 0),
             (x0 - 0.02, 0.05), (x0 + 0.04, -0.27), (x0 + 0.10, 0.17), (x0 + 0.14, 0),
             (x0 + 0.22, 0), (x0 + 0.28, -0.06), (x0 + 0.34, 0), (1, 0)]
    return [(x * side, (height + y) * side) for x, y in shape]


def alife(img, color, side):
    """Project A-Life: a heartbeat in the blade's color, beating where the blade crosses it."""
    glow_line(img, heartbeat(side), color, side * 0.018, side * 0.02)


def enso(img, color, side):
    """Forms: a brushed enso round the sword, a slash trail that swells, then thins and fades."""
    cx = cy = side / 2
    radius, thick = side * 0.39, side * 0.08
    start, sweep, steps = math.radians(10), math.radians(300), 240  # ends behind the tip
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    light = mix(color, (255, 255, 255), 0.3)
    for i in range(steps):
        t0, t1 = i / steps, (i + 1) / steps
        t = (t0 + t1) / 2
        # The head of the stroke (t = 1) is thick and bright; the tail thins and fades out.
        w = thick * (0.08 + 0.92 * t ** 1.4) * min(1, (1 - t) * 14 + 0.25)
        alpha = int(255 * min(1, 0.1 + t ** 0.8))
        pts = []
        for tt, r in ((t0, radius + w / 2), (t1, radius + w / 2), (t1, radius - w / 2), (t0, radius - w / 2)):
            ang = start + sweep * tt
            pts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r))
        d.polygon(pts, fill=light + (alpha,))
    halo = Image.new("RGBA", img.size, color + (0,))
    halo.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(side * 0.025)).point(lambda v: v * 0.8))
    img.alpha_composite(halo)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(side * 0.002)))


def bandit(img, color, side):
    """Bandits: a masked bandit's head and shoulders behind the blade, lit from it."""
    s = side
    body = Image.new("L", img.size, 0)
    bd = ImageDraw.Draw(body)
    hx, hy, hr = 0.47 * s, 0.38 * s, 0.15 * s
    bd.ellipse([hx - hr, hy - hr * 1.12, hx + hr, hy + hr * 1.12], fill=255)
    bd.rectangle([hx - hr * 0.5, hy, hx + hr * 0.5, 0.64 * s], fill=255)
    bd.chord([0.1 * s, 0.6 * s, 0.84 * s, 1.5 * s], 180, 360, fill=255)
    # Lit from the blade, up and to the right: a soft rim on that side of the silhouette.
    shifted = Image.new("L", img.size, 0)
    shifted.paste(body, (-int(s * 0.014), int(s * 0.014)))
    rim_mask = Image.composite(body, Image.new("L", img.size, 0), shifted.point(lambda v: 255 - v))
    rim = Image.new("RGBA", img.size, mix(color, (255, 255, 255), 0.2) + (0,))
    rim.putalpha(rim_mask.filter(ImageFilter.GaussianBlur(s * 0.006)).point(lambda v: v * 0.85))
    img.paste(Image.new("RGBA", img.size, (30, 26, 34, 255)), (0, 0), body)
    img.alpha_composite(rim)
    d = ImageDraw.Draw(img)
    # The bandana over the lower face, its knot behind, and the eyes in the gap above it.
    cloth = mix(color, (30, 6, 8), 0.6) + (255,)
    fold = mix(color, (30, 6, 8), 0.75) + (255,)
    d.polygon([(hx - hr * 1.03, hy + hr * 0.02), (hx + hr * 1.03, hy + hr * 0.02),
               (hx + hr * 0.8, hy + hr * 0.7), (hx, hy + hr * 1.45), (hx - hr * 0.8, hy + hr * 0.7)], fill=cloth)
    d.line([(hx - hr * 0.7, hy + hr * 0.45), (hx, hy + hr * 0.95), (hx + hr * 0.7, hy + hr * 0.45)],
           fill=fold, width=int(hr * 0.08))
    for ex in (-0.4, 0.4):
        x, y = hx + ex * hr, hy - hr * 0.25
        d.ellipse([x - hr * 0.19, y - hr * 0.06, x + hr * 0.19, y + hr * 0.06], fill=(255, 236, 220, 255))


# Mod -> (blade color, emblem drawn behind the sword or None, preview title lines).
MODS = {
    "PhotonSword": (PALETTE["Blue"], None, ("PHOTON SWORD",)),
    "PhotonSwordForms": (PALETTE["Purple"], enso, ("PHOTON SWORD", "FORMS")),
    "PhotonSwordALife": (PALETTE["Green"], alife, ("PHOTON SWORD", "\u00d7 PROJECT A-LIFE")),
    "PhotonSwordBandits": (PALETTE["Red"], bandit, ("PHOTON SWORD", "\u00d7 BANDITS")),
}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def framed(size, color, emblem):
    img = background(size, color)
    if emblem:
        emblem(img, color, size * SS)
    img = Image.alpha_composite(img, render_sword(size, color, radial=1.9, glow=1.0, fill=0.8))
    return img.resize((size, size), Image.LANCZOS)


def titled(art, lines):
    """The poster with its title over a dark fade at the bottom, for the Workshop thumbnail."""
    img = art.copy()
    w, h = img.size
    fade = Image.linear_gradient("L").resize((w, h // 3))
    img.paste(Image.new("RGBA", fade.size, (4, 5, 10, 255)), (0, h - fade.height), fade.point(lambda v: v * 0.9))
    d = ImageDraw.Draw(img)
    y = h - 12
    for i in reversed(range(len(lines))):
        size = (22, 14)[min(i, 1)]
        font = ImageFont.truetype(FONT, size)
        while d.textlength(lines[i], font=font) > w - 20:  # shrink to fit the width
            size -= 1
            font = ImageFont.truetype(FONT, size)
        y -= font.size + 4
        d.text((w / 2, y), lines[i], font=font, fill=(240, 242, 250), anchor="mt",
               stroke_width=2, stroke_fill=(4, 5, 10))
    return img


def icon(color):
    # Chunkier and with a tighter halo than the poster, so it reads at 32 pixels.
    return render_sword(32, color, radial=3.2, glow=0.55, fill=0.86).resize((32, 32), Image.LANCZOS)


def main():
    argparse.ArgumentParser(description=__doc__.splitlines()[0]).parse_args()
    for mod, (color, emblem, lines) in MODS.items():
        poster = framed(256, color, emblem)
        titled(poster, lines).convert("RGB").save(os.path.join(ROOT, mod, "preview.png"), optimize=True)
        info_dir = os.path.join(ROOT, mod, "Contents", "mods", mod, "42")
        poster.convert("RGB").save(os.path.join(info_dir, "poster.png"), optimize=True)
        icon(color).save(os.path.join(info_dir, "icon.png"), optimize=True)
    print(f"Wrote preview.png (256), poster.png (256), and icon.png (32) for {len(MODS)} mods")


if __name__ == "__main__":
    main()
