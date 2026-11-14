"""Shared pieces of the photon sword's animation tools: the game's path, the breath every held
pose takes, a skeleton pose with world-space edits, two-bone IK, and writing a pose list as a
Project Zomboid .x clip (vanilla's skeleton and mesh, then the new animation).

Photon Sword Forms' make_block.py and make_dodge.py import these too.
"""

import re
from pathlib import Path

import numpy as np

import xfile

DEFAULT_PZ = Path.home() / ".local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid"
KNEE_POLE = {"R": np.array([-0.2, 0.0, -1.0]), "L": np.array([0.2, 0.0, -1.0])}   # knees forward

# The breath, one loop of the clip.
BREATH_SECONDS = 2.6   # length of one breath (the loop)
BREATH_KEYS = 20       # keyframes per loop
CHEST_DEGREES = 2.0    # chest lift on the inhale
SHOULDER_DEGREES = 3.0 # shoulders rise on the inhale
SINK = 0.012           # how far the body settles on the exhale (model units; ~2 cm)


def rotation_between(a, b):
    """Column-vector rotation matrix turning direction a onto b."""
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v, c = np.cross(a, b), np.dot(a, b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else -np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * ((1 - c) / np.dot(v, v))


def _rodrigues(axis, angle):
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(angle) * k + (1 - np.cos(angle)) * k @ k


class Pose:
    def __init__(self, clip):
        self.x = clip
        self.local = {name: m.copy() for name, m in clip.local_matrices(0).items()}
        self.update()

    def update(self):
        self.world = self.x.world_matrices(self.local)

    def parent_world(self, name):
        parent = self.x.bones[name].parent
        return self.world[parent.name] if parent else np.eye(4)

    def set_world(self, name, world):
        self.local[name] = world @ np.linalg.inv(self.parent_world(name))
        self.update()

    def rotate_world(self, name, q):
        """Applies column-vector world rotation q to a bone, keeping its position."""
        world = self.world[name].copy()
        world[:3, :3] = world[:3, :3] @ q.T
        self.set_world(name, world)

    def position(self, name):
        return self.world[name][3, :3].copy()

    def copy(self):
        pose = Pose.__new__(Pose)
        pose.x, pose.local = self.x, {name: m.copy() for name, m in self.local.items()}
        pose.update()
        return pose


def solve_limb(pose, upper, fore, hand, hand_world, pole_direction):
    """Two-bone IK: upper and fore put the end bone at hand_world, then it takes its rotation."""
    shoulder, target = pose.position(upper), hand_world[3, :3]
    a = np.linalg.norm(pose.position(fore) - shoulder)
    b = np.linalg.norm(pose.position(hand) - pose.position(fore))
    d = min(np.linalg.norm(target - shoulder), a + b - 1e-4)
    reach = (target - shoulder) / np.linalg.norm(target - shoulder)
    # Elbow: along the reach by the law of cosines, offset toward the pole.
    along = (a * a - b * b + d * d) / (2 * d)
    height = np.sqrt(max(a * a - along * along, 0))
    pole = pole_direction - np.dot(pole_direction, reach) * reach
    elbow = shoulder + reach * along + pole / np.linalg.norm(pole) * height
    pose.rotate_world(upper, rotation_between(pose.position(fore) - shoulder, elbow - shoulder))
    pose.rotate_world(fore, rotation_between(pose.position(hand) - pose.position(fore), target - pose.position(fore)))
    world = pose.world[hand].copy()
    world[:3, :3] = hand_world[:3, :3]
    pose.set_world(hand, world)


def solve_leg(pose, side, foot_world):
    solve_limb(pose, *(f"Bip01_{side}_{b}" for b in ("Thigh", "Calf", "Foot")), foot_world, KNEE_POLE[side])


def animation_set(frames, name):
    """frames: [(tick, Pose)] in order; the last should repeat the first for a seamless loop."""
    lines = [f"AnimationSet {name} {{"]
    first = frames[0][1]
    for name in first.x.bones:
        if name not in first.x.keys:
            continue
        keys = {"S": [], "R": [], "T": []}
        for tick, pose in frames:
            m = pose.local[name]
            scale = np.linalg.norm(m[:3, :3], axis=1)
            keys["S"].append((tick, scale))
            keys["R"].append((tick, xfile.matrix_quat(m[:3, :3] / scale[:, None])))
            keys["T"].append((tick, m[3, :3]))
        # Keep quaternions in one hemisphere so interpolation takes the short way.
        for i in range(1, len(keys["R"])):
            if np.dot(keys["R"][i][1], keys["R"][i - 1][1]) < 0:
                keys["R"][i] = (keys["R"][i][0], -keys["R"][i][1])
        lines += [" Animation {", f"  {{ {name} }}"]
        for kind, key_type in (("S", 1), ("R", 0), ("T", 2)):
            lines += [f"  AnimationKey {kind} {{", f"   {key_type};", f"   {len(keys[kind])};"]
            for i, (tick, v) in enumerate(keys[kind]):
                end = ";;;" if i == len(keys[kind]) - 1 else ";;,"
                lines.append(f"   {tick};{len(v)};" + ",".join(f"{c:.6f}" for c in v) + end)
            lines.append("  }")
        lines.append(" }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write(clip, frames, path, name):
    """Writes frames as clip name: base clip's skeleton and mesh, then the new animation."""
    start = re.search(r"^AnimationSet \w+", clip.text, re.M).start()
    text = clip.text[:start] + animation_set(frames, name)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="latin-1", newline="\r\n") as out:  # CRLF, as vanilla
        out.write(text)
    check = xfile.XFile(path)
    error = max(np.abs(check.world_matrices(check.local_matrices(tick))[n] - pose.world[n]).max()
                for tick, pose in frames for n in pose.world)
    print(f"Wrote {path} (round-trip error {error:.2g})")
