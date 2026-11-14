#!/usr/bin/env python3
"""Paints each Form manual's textures (media/textures/):

  Item_PSF_Manual_<n>.png      64x64 inventory icon
  PSF_Manual_<n>_Reading.png   512x512 for the game's held magazine mesh (Magazine)
  PSF_Manual_<n>_Ground.png    256x256 for the game's floor magazine mesh (WorldItems/Magazine)
  PSF_Manual_<n>_Cover.png     512x768 for the illustrated manual window (PSF_Manual.lua)

The meshes are the game's own, so only textures ship; the rectangles below are where each mesh's
UV islands sit. The held magazine shows the cover on three islands and an inner page on the fourth
(as the game's and Senator's magazines lay it out). Needs Pillow and the DejaVu fonts (only used
to paint; nothing is shipped but the PNGs).

    python3 tools/gen_manual.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "PhotonSwordForms/Contents/mods/PhotonSwordForms/42/media/textures"
FONT_DIR = Path("/usr/share/fonts/truetype/dejavu")

# Form number -> (subtitle, tagline). Each Form's manual item names its textures in
# scripts/item_photonswordforms.txt and models_photonswordforms.txt.
FORMS = {
    1: ("THE FOUNDATION", ["An elegant blade.", "Batteries not included."]),
}

PAPER = (231, 224, 204)
INK = (24, 26, 34)
NIGHT = (18, 26, 52)
BAND = (36, 58, 112)
BLADE = (80, 150, 255)

# UV islands as (left, top, right, bottom) fractions of the texture.
READING_COVERS = [(.05, .024, .39, .487), (.052, .517, .361, .949), (.402, .511, .711, .952)]
READING_PAGE = (.402, .024, .743, .488)
READING_EDGES = [(.807, .026, .863, .959), (.917, .026, .98, .959)]
GROUND_COVER = (.014, .014, .867, .989)
GROUND_EDGE = (.889, .029, .988, .963)


def font(size, bold=True):
    name = "DejaVuSansCondensed-Bold.ttf" if bold else "DejaVuSansCondensed.ttf"
    return ImageFont.truetype(str(FONT_DIR / name), size)


def fit(draw, text, width, size, bold=True):
    """The largest font no bigger than size that fits text in width."""
    while size > 6:
        f = font(size, bold)
        if draw.textlength(text, font=f) <= width:
            return f
        size -= 1
    return font(6, bold)


def centered(draw, y, text, f, fill, width):
    draw.text(((width - draw.textlength(text, font=f)) / 2, y), text, font=f, fill=fill)


def sword(size, angle):
    """An ignited photon sword on a transparent square: a glowing blade over a ridged hilt."""
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x, w = s // 2, s // 22
    hilt_top, hilt_bottom = int(s * .70), int(s * .92)
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((x - w * 2, s * .06, x + w * 2, hilt_top), w * 2, fill=BLADE + (255,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(w * 1.6)))
    d.rounded_rectangle((x - w, s * .08, x + w, hilt_top), w, fill=(225, 240, 255, 255))
    d.rectangle((x - w * 1.5, hilt_top, x + w * 1.5, hilt_bottom), fill=(70, 72, 80, 255))
    d.rectangle((x - w * 2, hilt_top, x + w * 2, hilt_top + w * 1.4), fill=(150, 152, 160, 255))
    for k in range(4):
        y = hilt_top + w * 2.6 + k * w * 1.6
        d.rectangle((x - w * 1.5, y, x + w * 1.5, y + w * .6), fill=(30, 30, 36, 255))
    d.rectangle((x - w * 1.2, hilt_bottom, x + w * 1.2, hilt_bottom + w), fill=(150, 152, 160, 255))
    return im.rotate(angle, resample=Image.BICUBIC).resize((size, size), Image.LANCZOS)


def cover(n, w, h):
    subtitle, tagline = FORMS[n]
    im = Image.new("RGBA", (w, h), PAPER + (255,))
    d = ImageDraw.Draw(im)
    m = w * .06
    d.rectangle((m, m, w - m, h - m), fill=NIGHT)
    inner = w - 2 * m
    title = fit(d, "PHOTON SWORD", inner * .9, int(h * .11))
    centered(d, m + h * .02, "PHOTON SWORD", title, PAPER, w)
    band_top = m + h * .15
    d.rectangle((m, band_top, w - m, band_top + h * .045), fill=BAND)
    centered(d, band_top + h * .006, "TRAINING NOTES", fit(d, "TRAINING NOTES", inner * .6, int(h * .034)), PAPER, w)
    # The art: a pale disc with the sword across it.
    r = min(inner * .36, h * .19)
    cx, cy = w / 2, band_top + h * .07 + r
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(38, 52, 92))
    art = sword(int(r * 2.3), -35)
    im.alpha_composite(art, (int(cx - art.width / 2), int(cy - art.height / 2)))
    d = ImageDraw.Draw(im)
    label = "FORM %d" % n
    form_font = fit(d, label, inner * .5, int(h * .09))
    y = cy + r + h * .015
    centered(d, y, label, form_font, BLADE, w)
    y += h * .095
    centered(d, y, subtitle, fit(d, subtitle, inner * .7, int(h * .035)), PAPER, w)
    y += h * .05
    f = fit(d, max(tagline, key=len), inner * .85, int(h * .04), False)
    for line in tagline:
        centered(d, y, line, f, (200, 205, 220), w)
        y += f.size * 1.2
    return im


def stick(d, x, y, s, pose):
    """A stick figure s tall with its feet at (x, y), holding a blade: 'ready', 'cut', or 'thrust'."""
    head = s * .12
    neck, hip = y - s * .78, y - s * .42
    d.ellipse((x - head, neck - head * 2, x + head, neck), outline=INK, width=2)
    d.line((x, neck, x, hip), fill=INK, width=2)
    d.line((x, hip, x - s * .18, y), fill=INK, width=2)
    d.line((x, hip, x + s * .18, y), fill=INK, width=2)
    hand = {"ready": (x + s * .12, y - s * .55), "cut": (x + s * .3, y - s * .72), "thrust": (x + s * .38, y - s * .62)}[pose]
    tip = {"ready": (hand[0] + s * .05, hand[1] - s * .5), "cut": (hand[0] + s * .45, hand[1] + s * .2),
           "thrust": (hand[0] + s * .55, hand[1])}[pose]
    d.line((x, neck + s * .08, hand[0], hand[1]), fill=INK, width=2)
    d.line((hand, tip), fill=BLADE, width=4)
    d.line((hand, tip), fill=(225, 240, 255), width=1)


def page(n, w, h):
    """The inner page: three drills."""
    im = Image.new("RGBA", (w, h), (243, 238, 224, 255))
    d = ImageDraw.Draw(im)
    m = w * .06
    heading = "FORM %d DRILLS" % n
    d.rectangle((m, m, w - m, m + h * .08), fill=NIGHT)
    centered(d, m + h * .012, heading, fit(d, heading, (w - 2 * m) * .9, int(h * .055)), PAPER, w)
    drills = [("ready", "Aim. Breathe.", "Look calm."), ("cut", "Swing at", "the problem."), ("thrust", "Point the glowy", "end at it.")]
    top, cell = m + h * .1, (h - m - (m + h * .1)) / 3
    for k, (pose, a, b) in enumerate(drills):
        y = top + k * cell
        d.rectangle((m, y + cell * .05, w - m, y + cell * .95), outline=INK, width=2)
        stick(d, m + w * .2, y + cell * .85, cell * .75, pose)
        f = fit(d, max(a, b, key=len), w * .45, int(cell * .2))
        d.text((w * .48, y + cell * .3), a, font=f, fill=INK)
        d.text((w * .48, y + cell * .3 + f.size * 1.15), b, font=f, fill=INK)
    return im


def place(tex, art, box, bleed=3):
    """Scales art over a UV island, a few pixels past its edges so filtering doesn't show seams."""
    W, H = tex.size
    l, t, r, b = int(box[0] * W) - bleed, int(box[1] * H) - bleed, int(box[2] * W) + bleed, int(box[3] * H) + bleed
    tex.alpha_composite(art.resize((r - l, b - t), Image.LANCZOS), (l, t))


def edges(tex, box):
    """Page edges: thin stripes of paper."""
    W, H = tex.size
    l, t, r, b = int(box[0] * W) - 3, int(box[1] * H) - 3, int(box[2] * W) + 3, int(box[3] * H) + 3
    d = ImageDraw.Draw(tex)
    d.rectangle((l, t, r, b), fill=PAPER)
    for x in range(l, r, 3):
        d.line((x, t, x, b), fill=(205, 198, 178))


def icon(n):
    """Too small for the cover's words: the sword and the Form's number, painted large and scaled down."""
    s = 8
    im = Image.new("RGBA", (64 * s, 64 * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    l, t, r, b = 12 * s, 5 * s, 52 * s, 59 * s
    d.rectangle((l + 2 * s, t + 2 * s, r + 2 * s, b + 2 * s), fill=(0, 0, 0, 90))  # shadow
    d.rectangle((l + s, t + s, r + s, b + s), fill=PAPER + (255,))                # back pages
    d.rectangle((l, t, r, b), fill=PAPER + (255,))
    d.rectangle((l + 2 * s, t + 2 * s, r - 2 * s, b - 2 * s), fill=NIGHT + (255,))
    d.rectangle((l + 2 * s, t + 7 * s, r - 2 * s, t + 10 * s), fill=BAND + (255,))
    art = sword(32 * s, -35)
    im.alpha_composite(art, ((l + r) // 2 - art.width // 2, t + 9 * s))
    d = ImageDraw.Draw(im)
    f = font(14 * s)
    label = str(n)
    d.text((r - 3 * s - d.textlength(label, font=f), b - 18 * s), label, font=f, fill=BLADE + (255,))
    return im.resize((64, 64), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for n in FORMS:
        art = cover(n, 512, 680)
        reading = Image.new("RGBA", (512, 512), PAPER + (255,))
        for box in READING_COVERS:
            place(reading, art, box)
        place(reading, page(n, 512, 680), READING_PAGE)
        for box in READING_EDGES:
            edges(reading, box)
        ground = Image.new("RGBA", (256, 256), PAPER + (255,))
        place(ground, art, GROUND_COVER)
        edges(ground, GROUND_EDGE)
        files = {
            "Item_PSF_Manual_%d.png" % n: icon(n),
            "PSF_Manual_%d_Reading.png" % n: reading,
            "PSF_Manual_%d_Ground.png" % n: ground,
            "PSF_Manual_%d_Cover.png" % n: cover(n, 512, 768),
        }
        for name, im in files.items():
            im.save(OUT / name, optimize=True)
            print("wrote", OUT / name)


if __name__ == "__main__":
    main()
