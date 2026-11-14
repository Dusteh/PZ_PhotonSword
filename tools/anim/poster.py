"""Render the mod's poster art with Blender: a character in a stance holding a lit photon sword.

    blender -b --python tools/anim/poster.py -- CLIP.x HILT.x BLADE.x OUT.png [--size N] [--tick N]
                                              [--icon ICON.png]

The skinned body is a dark figure lit by a cool rim light; the hilt and blade meshes sit on
Bip01_Prop1 as the game attaches them, and the blade glows (a blurred bloom added after rendering).
--icon also writes a 32x32 close-up of the hands and blade for mod.info's icon.
"""

import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xfile  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
clip, hilt_mesh, blade_mesh, out = args[:4]
size = int(args[args.index("--size") + 1]) if "--size" in args else 512
tick = int(args[args.index("--tick") + 1]) if "--tick" in args else 0
icon = args[args.index("--icon") + 1] if "--icon" in args else None

BLADE_COLOR = (0.25, 0.6, 1.0)
BACKGROUND = (0.015, 0.018, 0.03)

x = xfile.XFile(clip)
world = x.world_matrices(x.local_matrices(tick))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def to_blender(v):
    # .x space is Y-up; Blender is Z-up. Mirror X too, since .x is left-handed.
    return (-v[0], v[2], v[1])


def add_mesh(name, verts, faces, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([to_blender(v) for v in verts], [], faces)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def surface(name, color, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def glow(name, color, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.remove(nodes["Principled BSDF"])
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*color, 1)
    emit.inputs["Strength"].default_value = strength
    mat.node_tree.links.new(emit.outputs[0], nodes["Material Output"].inputs["Surface"])
    return mat


add_mesh("Body", x.skinned(world), x.faces, surface("body", (0.32, 0.27, 0.22)))

prop = world["Bip01_Prop1"]
for path, mat in ((hilt_mesh, surface("hilt", (0.55, 0.55, 0.58), 0.3)),
                  (blade_mesh, glow("blade", BLADE_COLOR, 12))):
    weapon = xfile.XFile(path)
    placed = np.hstack([weapon.vertices, np.ones((len(weapon.vertices), 1))]) @ prop
    add_mesh(os.path.basename(path), placed[:, :3], weapon.faces, mat)


def light(name, kind, energy, color, location, size=1.0):
    data = bpy.data.lights.new(name, kind)
    data.energy, data.color = energy, color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (Vector((0, 0, 1)) - Vector(location)).to_track_quat("-Z", "Y")
    scene.collection.objects.link(obj)


light("key", "AREA", 120, (1.0, 0.9, 0.8), (1.5, -2.0, 2.2), 1.5)
light("rim", "AREA", 250, (0.5, 0.7, 1.0), (-1.2, 2.0, 1.8), 1.0)

bg = bpy.data.worlds.new("bg")
bg.use_nodes = True
bg.node_tree.nodes["Background"].inputs["Color"].default_value = (*BACKGROUND, 1)
scene.world = bg

scene.render.engine = "CYCLES"
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Punchy"
scene.render.resolution_x = scene.render.resolution_y = size
scene.render.image_settings.color_mode = "RGB"

# Frame the figure and the blade from the front, a little to the sword side and above.
verts = x.skinned(world)
low, high = verts.min(0), verts.max(0)
center = Vector(to_blender((low + high) / 2 + [0, 0.03 * (high - low)[1], 0]))
cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 70
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
offset = Vector((-0.35, -1.0, 0.12)) * (high - low)[1] * 2.8
cam.location = center + offset
cam.rotation_mode = "QUATERNION"
cam.rotation_quaternion = (-offset).to_track_quat("-Z", "Y")

scene.render.filepath = out
bpy.ops.render.render(write_still=True)

# Bloom: blur the bright pixels and add them back.
image = bpy.data.images.load(out)
w, h = image.size
pixels = np.array(image.pixels[:]).reshape(h, w, 4)[:, :, :3]
bright = np.clip(pixels - 0.6, 0, None) * np.array(BLADE_COLOR)


def blur(a, radius):
    for axis in (0, 1):
        for _ in range(3):
            pad = [(0, 0)] * 3
            pad[axis] = (radius, radius)
            c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
            c = np.insert(c, 0, 0, axis=axis)
            a = (np.take(c, range(2 * radius + 1, c.shape[axis]), axis=axis)
                 - np.take(c, range(0, c.shape[axis] - 2 * radius - 1), axis=axis)) / (2 * radius + 1)
    return a


bloom = blur(bright, max(1, size // 64)) * 1.5 + blur(bright, max(1, size // 20)) * 1.2
result = np.clip(pixels + bloom, 0, 1)
image.pixels[:] = np.dstack([result, np.ones((h, w))]).ravel()
image.filepath_raw = out
image.file_format = "PNG"
image.save()

if icon:
    # A square half the poster's width, centered between the grip and the blade's tip.
    hand = world_to_camera_view(scene, cam, Vector(to_blender(prop[3, :3] + prop[1, :3] * 0.15)))
    half = w // 4
    cx = min(max(int(hand.x * w), half), w - half)
    cy = min(max(int(hand.y * h), half), h - half)
    crop = result[cy - half:cy + half, cx - half:cx + half]
    small = bpy.data.images.new("icon", 2 * half, 2 * half)
    small.pixels[:] = np.dstack([crop, np.ones(crop.shape[:2])]).ravel()
    small.scale(32, 32)
    small.filepath_raw = icon
    small.file_format = "PNG"
    small.save()
