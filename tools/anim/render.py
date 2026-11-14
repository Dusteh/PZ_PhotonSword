"""Render a Project Zomboid .x animation pose to PNGs with Blender, for checking a pose by eye.

    blender -b --python tools/anim/render.py -- CLIP.x OUT_PREFIX [--tick N] [--axes] [--blade AXIS] [--zoom]
                                                  [--prop MESH.x]

Writes OUT_PREFIX_front.png, _side.png, _three.png, and _quarter.png: the skinned body (a grey figure) and,
on Bip01_Prop1 (the bone a two-handed weapon attaches to), either RGB sticks for its X/Y/Z axes
(--axes) or a blade along one signed axis (--blade -y, say). --prop draws a weapon mesh (a static .x
model such as PhotonSword_Hilt.x) on Bip01_Prop1, as the game attaches it with no attachment offset.
"""

import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xfile  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
clip, prefix = args[0], args[1]
tick = int(args[args.index("--tick") + 1]) if "--tick" in args else 0
blade = args[args.index("--blade") + 1] if "--blade" in args else None
axes = "--axes" in args
zoom = "--zoom" in args  # close-up on the grip
prop_mesh = args[args.index("--prop") + 1] if "--prop" in args else None

x = xfile.XFile(clip)
world = x.world_matrices(x.local_matrices(tick))
verts = x.skinned(world)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def to_blender(v):
    # .x space is Y-up; Blender is Z-up. Mirror X too, since .x is left-handed.
    return (-v[0], v[2], v[1])


mesh = bpy.data.meshes.new("Body")
mesh.from_pydata([to_blender(v) for v in verts], [], x.faces)
mesh.update()
body = bpy.data.objects.new("Body", mesh)
scene.collection.objects.link(body)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    return mat


body.data.materials.append(material("skin", (0.75, 0.72, 0.68, 1)))


def stick(start, end, color, radius=0.008):
    start, end = Vector(to_blender(start)), Vector(to_blender(end))
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=(end - start).length, location=(start + end) / 2)
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = (end - start).to_track_quat("Z", "Y")
    obj.data.materials.append(material("c%s" % len(bpy.data.materials), color))


prop = world["Bip01_Prop1"]
origin = prop[3, :3]
if axes:
    for i, color in enumerate([(1, 0, 0, 1), (0, 0.8, 0, 1), (0, 0.3, 1, 1)]):
        stick(origin, origin + prop[i, :3] * 0.3, color)
if blade:
    sign = -1 if blade.startswith("-") else 1
    axis = prop["xyz".index(blade[-1]), :3] * sign
    stick(origin - axis * 0.12, origin, (0.2, 0.2, 0.2, 1), 0.012)      # grip
    stick(origin, origin + axis * 0.5, (0.3, 0.8, 1.0, 1), 0.01)        # blade

if prop_mesh:
    weapon = xfile.XFile(prop_mesh)
    placed = np.hstack([weapon.vertices, np.ones((len(weapon.vertices), 1))]) @ prop
    mesh = bpy.data.meshes.new("Prop")
    mesh.from_pydata([to_blender(v) for v in placed[:, :3]], [], weapon.faces)
    mesh.update()
    obj = bpy.data.objects.new("Prop", mesh)
    scene.collection.objects.link(obj)
    obj.data.materials.append(material("prop", (0.25, 0.25, 0.3, 1)))

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = False
scene.render.resolution_x = scene.render.resolution_y = 480
world_bg = bpy.data.worlds.new("bg")
scene.world = world_bg
world_bg.color = (0.12, 0.12, 0.14)

center = Vector(to_blender(world["Bip01_Prop1"][3, :3] + [0, 0.05, 0])) if zoom else \
    Vector(to_blender(verts.mean(0))) + Vector((0, 0, 0.1))
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 0.55 if zoom else 1.5
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

# The model faces -Z in .x space, which is -Y in Blender after to_blender.
views = {"front": Vector((0, -3, 0)), "side": Vector((3, 0, 0)), "three": Vector((2.2, -2.2, 1.2)),
         "quarter": Vector((1.6, -2.6, 0.6))}   # front, from the sword side
for name, offset in views.items():
    cam.location = center + offset
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (-offset).to_track_quat("-Z", "Y")
    scene.render.filepath = f"{prefix}_{name}.png"
    bpy.ops.render.render(write_still=True)
