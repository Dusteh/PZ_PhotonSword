#!/usr/bin/env python3
"""Generates the photonsword 3D models, model textures, inventory icons, and model script.

    python3 tools/gen_models.py [--preview DIR]

Writes (under the mod's 42/media):
  models_X/weapons/PhotonSword_Hilt.x      inert hilt
  models_X/weapons/PhotonSword_Blade.x     hilt + ignited blade
  textures/weapons/PhotonSword_Hilt.png    hilt texture
  textures/weapons/PhotonSword_Blade_<Color>.png   one per palette color
  textures/Item_PhotonSwordHilt.png        32x32 icon, shared by the hilt and ignited blade
  scripts/models_photonsword.txt           model definitions (PhotonSword_Hilt, PhotonSword_Blade_<Color>)

Meshes follow vanilla Katana.x: DirectX text format, blade along +Y, grip at the origin, and
cross(v1 - v0, v2 - v0) pointing out of each face. Both meshes share one 256x256 texture layout:
the hilt uses the left half and the blade the right half, so each blade color is just a texture.
--preview also writes OBJ copies there for viewing in Blender. Needs numpy and Pillow.
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw

MEDIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                     "PhotonSword", "Contents", "mods", "PhotonSword", "42", "media")

# Must match PS.BLADE_COLORS / PS.COLORS in shared/PhotonSword/PS_Core.lua (same names, same
# order; these are 0-255). The first is the default, which the blade item script points at.
PALETTE = {
    "Blue": (64, 128, 255),
    "Green": (77, 255, 89),
    "Red": (255, 51, 38),
    "Purple": (178, 77, 255),
    "Yellow": (255, 230, 64),
    "Orange": (255, 140, 38),
    "Cyan": (51, 242, 255),
    "White": (242, 242, 255),
}

SEGMENTS = 12
TEX = 256
HILT_U = (0.0, 0.45)     # hilt surface
BUTTON_U = (0.46, 0.50)  # small patch for the activation button
BLADE_U = (0.5, 1.0)     # blade surface
HILT_Y = (-0.066, 0.125)
BLADE_Y = (0.12, 0.63)
THICKNESS = 0.85  # radial scale for the whole model; lengths along Y are unchanged


def hilt_profile(top_radius=0.0):
    """(y, radius) from the pommel up to the emitter. top_radius > 0 leaves an open ring for a blade."""
    p = [(-0.065, 0.0), (-0.065, 0.011), (-0.062, 0.015), (-0.050, 0.015), (-0.048, 0.0135)]
    y = -0.045
    while y < 0.055:  # grip ridges
        p += [(y, 0.0135), (y + 0.003, 0.0148), (y + 0.007, 0.0148), (y + 0.010, 0.0135)]
        y += 0.010
    p += [(0.058, 0.0135), (0.060, 0.0155), (0.088, 0.0155), (0.092, 0.0185), (0.122, 0.0185)]
    if top_radius:
        p += [(0.122, top_radius)]
    else:
        p += [(0.122, 0.012), (0.118, 0.008), (0.118, 0.0)]
    return p


BLADE_RADIUS = 0.0105
BLADE_PROFILE = [(0.122, BLADE_RADIUS), (0.600, BLADE_RADIUS), (0.612, 0.008), (0.620, 0.004), (0.623, 0.0)]


class Mesh:
    def __init__(self):
        self.verts, self.uvs, self.faces = [], [], []
        self.lathe_faces = []  # only these are checked by check_outward (a box's -X face faces the axis)

    def add(self, pos, uv):
        self.verts.append(pos)
        self.uvs.append(uv)
        return len(self.verts) - 1

    def lathe(self, profile, u_range, y_range):
        """Surface of revolution around +Y. The profile runs bottom to top along the outside,
        so a fixed winding faces every quad outward (including caps and ridge steps)."""
        u0, u1 = u_range
        rows = []
        for y, r in profile:
            v = (y - y_range[0]) / (y_range[1] - y_range[0])
            row = []
            for j in range(SEGMENTS + 1):  # the last column duplicates the first for the UV seam
                a = 2 * math.pi * j / SEGMENTS
                row.append(self.add((r * math.cos(a), y, r * math.sin(a)), (u0 + (u1 - u0) * j / SEGMENTS, v)))
            rows.append(row)
        for lo, hi in zip(rows, rows[1:]):
            for j in range(SEGMENTS):
                a, b, c, d = lo[j], lo[j + 1], hi[j + 1], hi[j]
                self.faces += [(a, c, b), (a, d, c)]
                self.lathe_faces += [(a, c, b), (a, d, c)]

    def box(self, lo, hi, u_range, v_range):
        """Axis-aligned box, all faces mapped to one texture patch."""
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        u0, u1 = u_range
        v0, v1 = v_range
        quads = [  # each listed so cross(v1-v0, v2-v0) points outward
            [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],  # +X
            [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],  # -X
            [(x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0)],  # +Y
            [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],  # -Y
            [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],  # +Z
            [(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)],  # -Z
        ]
        for q in quads:
            idx = [self.add(p, uv) for p, uv in zip(q, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])]
            self.faces += [(idx[0], idx[1], idx[2]), (idx[0], idx[2], idx[3])]

    def scale_radial(self, k):
        self.verts = [(x * k, y, z * k) for x, y, z in self.verts]
        return self

    def normals(self):
        """Smooth vertex normals from area-weighted face normals (welded by position)."""
        v = np.array(self.verts)
        acc = {}
        for a, b, c in self.faces:
            n = np.cross(v[b] - v[a], v[c] - v[a])
            for i in (a, b, c):
                key = tuple(np.round(v[i], 6))
                acc[key] = acc.get(key, 0) + n
        out = []
        for p in v:
            n = acc[tuple(np.round(p, 6))]
            length = np.linalg.norm(n)
            out.append(tuple(n / length) if length > 1e-12 else (0.0, 1.0, 0.0))
        return out

    def check_outward(self):
        """Every side face of a lathe should point away from the Y axis."""
        v = np.array(self.verts)
        bad = 0
        for a, b, c in self.lathe_faces:
            n = np.cross(v[b] - v[a], v[c] - v[a])
            center = (v[a] + v[b] + v[c]) / 3
            radial = np.array([center[0], 0, center[2]])
            if abs(n[1]) < 0.1 * np.linalg.norm(n) and np.dot(n, radial) < 0:
                bad += 1
        assert bad == 0, f"{bad} side faces point inward"


def build_hilt():
    m = Mesh()
    m.lathe(hilt_profile(), HILT_U, HILT_Y)
    m.box((0.0150, 0.070, -0.0035), (0.0185, 0.080, 0.0035), BUTTON_U, (0.0, 0.03))
    return m.scale_radial(THICKNESS)


def build_blade():
    m = Mesh()
    m.lathe(hilt_profile(top_radius=BLADE_RADIUS), HILT_U, HILT_Y)
    m.box((0.0150, 0.070, -0.0035), (0.0185, 0.080, 0.0035), BUTTON_U, (0.0, 0.03))
    m.lathe(BLADE_PROFILE, BLADE_U, BLADE_Y)
    return m.scale_radial(THICKNESS)


X_HEADER = """xof 0303txt 0032
template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x;
 FLOAT y;
 FLOAT z;
}

template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices;
 array DWORD faceVertexIndices[nFaceVertexIndices];
}

template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices;
 array Vector vertices[nVertices];
 DWORD nFaces;
 array MeshFace faces[nFaces];
 [...]
}

template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals;
 array Vector normals[nNormals];
 DWORD nFaceNormals;
 array MeshFace faceNormals[nFaceNormals];
}

template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u;
 FLOAT v;
}

template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords;
 array Coords2d textureCoords[nTextureCoords];
}

template ColorRGBA {
 <35ff44e0-6c7c-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
 FLOAT alpha;
}

template ColorRGB {
 <d3e16e81-7835-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
}

template Material {
 <3d82ab4d-62da-11cf-ab39-0020af71e433>
 ColorRGBA faceColor;
 FLOAT power;
 ColorRGB specularColor;
 ColorRGB emissiveColor;
 [...]
}

template MeshMaterialList {
 <f6f23f42-7686-11cf-8f52-0040333594a3>
 DWORD nMaterials;
 DWORD nFaceIndexes;
 array DWORD faceIndexes[nFaceIndexes];
 [Material <3d82ab4d-62da-11cf-ab39-0020af71e433>]
}

template TextureFilename {
 <a42790e1-7810-11cf-8f52-0040333594a3>
 STRING filename;
}

template FrameTransformMatrix {
 <f6f23f41-7686-11cf-8f52-0040333594a3>
 Matrix4x4 frameMatrix;
}

template Frame {
 <3d82ab46-62da-11cf-ab39-0020af71e433>
 [...]
}

template Matrix4x4 {
 <f6f23f45-7686-11cf-8f52-0040333594a3>
 array FLOAT matrix[16];
}
"""


def vec_list(items, fmt):
    return ",\n".join("  " + fmt(it) for it in items) + ";"


def write_x(path, name, mesh, texture_file):
    norms = mesh.normals()
    faces = vec_list(mesh.faces, lambda f: f"3;{f[0]},{f[1]},{f[2]};")
    out = [X_HEADER,
           f"Material {name}_Material {{\n 1.000000;1.000000;1.000000;1.000000;;\n 9.999999;\n"
           f" 0.000000;0.000000;0.000000;;\n 0.000000;0.000000;0.000000;;\n\n"
           f" TextureFilename {{\n  \"{texture_file}\";\n }}\n}}\n",
           f"Frame {name} {{\n\n FrameTransformMatrix {{\n"
           "  1.000000,0.000000,0.000000,0.000000,0.000000,1.000000,0.000000,0.000000,"
           "0.000000,0.000000,1.000000,0.000000,0.000000,0.000000,0.000000,1.000000;;\n }\n",
           f" Mesh {name} {{\n  {len(mesh.verts)};",
           vec_list(mesh.verts, lambda p: f"{p[0]:.6f};{p[1]:.6f};{p[2]:.6f};"),
           f"  {len(mesh.faces)};", faces,
           f"\n  MeshNormals {{\n  {len(norms)};",
           vec_list(norms, lambda n: f"{n[0]:.6f};{n[1]:.6f};{n[2]:.6f};"),
           f"  {len(mesh.faces)};", faces, "  }",
           f"\n  MeshMaterialList {{\n   1;\n   {len(mesh.faces)};",
           ",\n".join("   0" for _ in mesh.faces) + ";",
           f"   {{ {name}_Material }}\n  }}",
           f"\n  MeshTextureCoords {{\n   {len(mesh.uvs)};",
           vec_list(mesh.uvs, lambda t: f"{t[0]:.6f};{t[1]:.6f};"),
           "  }\n }\n}\n"]
    with open(path, "w") as f:
        f.write("\n".join(out))


def write_obj(path, mesh):
    with open(path, "w") as f:
        for p in mesh.verts:
            f.write(f"v {p[0]} {p[1]} {p[2]}\n")
        for u, v in mesh.uvs:
            f.write(f"vt {u} {1 - v}\n")  # OBJ's v runs up, DirectX's runs down
        for a, b, c in mesh.faces:
            f.write(f"f {a + 1}/{a + 1} {b + 1}/{b + 1} {c + 1}/{c + 1}\n")


def mix(c, target, t):
    return tuple(int(round(c[i] + (target[i] - c[i]) * t)) for i in range(3))


def paint_hilt(img):
    """Left half: hilt bands by height. Rows follow v, which maps linearly from HILT_Y."""
    px = img.load()
    rng = np.random.default_rng(7)
    x_end = int(HILT_U[1] * TEX)
    for row in range(TEX):
        y = HILT_Y[0] + (row + 0.5) / TEX * (HILT_Y[1] - HILT_Y[0])
        for x in range(x_end):
            u = x / x_end
            if y < -0.048:
                c = (78, 80, 88)  # pommel steel
            elif y < 0.058:
                ridge = 0.003 <= (y + 0.045) % 0.010 <= 0.007
                c = (58, 58, 64) if ridge else (26, 26, 30)  # rubber grip
            elif y < 0.090:
                c = (166, 169, 176)  # body
                if abs(y - 0.064) < 0.0012:
                    c = (60, 60, 66)  # seam
                if 0.62 < u < 0.86 and 0.066 < y < 0.084:
                    c = (34, 34, 40)  # control plate
            else:
                c = (206, 208, 214)  # emitter shroud
                if (u * 8) % 1 < 0.22 and 0.096 < y < 0.116:
                    c = (40, 40, 46)  # vent slots
            n = int(rng.integers(-6, 7))
            px[x, row] = tuple(max(0, min(255, ch + n)) for ch in c) + (255,)
    bx0, bx1 = int(BUTTON_U[0] * TEX), int(BUTTON_U[1] * TEX)
    for row in range(int(0.03 * TEX) + 1):
        for x in range(bx0, bx1):
            px[x, row] = (190, 30, 30, 255)  # activation button


def paint_blade(img, color):
    """Right half: the blade color lifted toward white, with brighter bands around the blade."""
    px = img.load()
    x0 = int(BLADE_U[0] * TEX)
    for x in range(x0, TEX):
        u = (x - x0) / (TEX - x0)
        core = 0.15 + 0.3 * (0.5 + 0.5 * math.cos(u * 2 * math.pi * 2))
        c = mix(color, (255, 255, 255), core)
        for row in range(TEX):
            px[x, row] = c + (255,)


def make_texture(blade_color=None):
    img = Image.new("RGBA", (TEX, TEX), (0, 0, 0, 255))
    paint_hilt(img)
    if blade_color:
        paint_blade(img, blade_color)
    return img


ICON_HI = 256  # icons are drawn large and downscaled for clean antialiasing


def draw_segment(draw, start, end, width, color):
    draw.line([start, end], fill=color, width=int(width))


def draw_hilt_icon(draw, start, end, scale=1.0):
    """Hilt along start->end: pommel, ridged grip, body with button, chrome emitter."""
    sx, sy = start
    ex, ey = end
    w = 26 * scale

    def at(t):
        return (sx + (ex - sx) * t, sy + (ey - sy) * t)

    draw_segment(draw, at(0.0), at(0.12), w * 1.05, (88, 90, 100))
    draw_segment(draw, at(0.12), at(0.62), w * 0.92, (30, 30, 34))
    for k in range(6):
        t = 0.16 + k * 0.08
        draw_segment(draw, at(t), at(t + 0.03), w * 0.98, (70, 70, 78))
    draw_segment(draw, at(0.62), at(0.80), w * 1.0, (172, 175, 184))
    draw_segment(draw, at(0.80), at(1.0), w * 1.22, (214, 216, 222))
    bx, by = at(0.70)
    draw.ellipse([bx - 5 * scale, by - 5 * scale, bx + 5 * scale, by + 5 * scale], fill=(200, 35, 35))


def make_icon():
    img = Image.new("RGBA", (ICON_HI, ICON_HI), (0, 0, 0, 0))
    draw_hilt_icon(ImageDraw.Draw(img), (40, 216), (216, 40), scale=1.5)
    return img.resize((32, 32), Image.LANCZOS)


MODEL_ATTACHMENTS = """        attachment world
        {
            offset = 0.0155 0.2859 0.015,
            rotate = -180.0 0.0 177.566,
        }
        attachment Bip01_Prop2
        {
            offset = -0.013 0.0001 0.0025,
            rotate = -23.8537 -86.6222 -22.0887,
        }"""


def model_block(name, mesh, texture):
    return (f"    model {name}\n    {{\n        mesh = {mesh},\n        texture = {texture},\n"
            f"{MODEL_ATTACHMENTS}\n    }}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", help="also write OBJ copies of the meshes to this directory")
    args = parser.parse_args()

    models_dir = os.path.join(MEDIA, "models_X", "weapons")
    tex_dir = os.path.join(MEDIA, "textures", "weapons")
    icon_dir = os.path.join(MEDIA, "textures")
    for d in (models_dir, tex_dir, icon_dir):
        os.makedirs(d, exist_ok=True)

    hilt, blade = build_hilt(), build_blade()
    for mesh in (hilt, blade):
        mesh.check_outward()
    write_x(os.path.join(models_dir, "PhotonSword_Hilt.x"), "PhotonSword_Hilt", hilt, "PhotonSword_Hilt.png")
    write_x(os.path.join(models_dir, "PhotonSword_Blade.x"), "PhotonSword_Blade", blade, "PhotonSword_Blade_Blue.png")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        write_obj(os.path.join(args.preview, "PhotonSword_Hilt.obj"), hilt)
        write_obj(os.path.join(args.preview, "PhotonSword_Blade.obj"), blade)

    make_texture().save(os.path.join(tex_dir, "PhotonSword_Hilt.png"))
    make_icon().save(os.path.join(icon_dir, "Item_PhotonSwordHilt.png"))
    blocks = [model_block("PhotonSword_Hilt", "weapons/PhotonSword_Hilt", "weapons/PhotonSword_Hilt")]
    for name, color in PALETTE.items():
        make_texture(color).save(os.path.join(tex_dir, f"PhotonSword_Blade_{name}.png"))
        blocks.append(model_block(f"PhotonSword_Blade_{name}", "weapons/PhotonSword_Blade",
                                  f"weapons/PhotonSword_Blade_{name}"))

    with open(os.path.join(MEDIA, "scripts", "models_photonsword.txt"), "w") as f:
        f.write("module Base\n{\n")
        f.write("    /* Generated by tools/gen_models.py; edit that and re-run instead of editing this file.\n"
                "       Attachments copy vanilla Katana, since the meshes share its grip origin and +Y blade. */\n\n")
        f.write("\n\n".join(blocks))
        f.write("\n}\n")
    print(f"hilt: {len(hilt.verts)} verts / {len(hilt.faces)} tris; blade: {len(blade.verts)} verts / "
          f"{len(blade.faces)} tris; {len(PALETTE)} blade colors")


if __name__ == "__main__":
    main()
