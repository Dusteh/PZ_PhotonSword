#!/usr/bin/env python3
"""Author PSF_DodgeLeft, PSF_DodgeRight, and PSF_DodgeBack: the photon sword's dodges, a leap away
with the extinguished hilt held in the sword hand.

Starts from vanilla's one-handed aim (Bob_IdleAim1Hand, frame 0), the pose a hilt is aimed in. Each
dodge crouches to load, leaps (the root travels DISTANCE along the dodge's direction on an arc, the
feet tucked up and carried over, the body leaning into the leap and the off arm thrown out for
balance), lands on bent knees, and rises back to the aim. The weapon bone (Bip01_Prop1) hangs off
the root, not the hand, so every key puts it back on the sword hand as in the vanilla pose, keeping
the hilt in the fist.

The root's travel is the clip's root motion (the AnimSet node uses deferred movement on Bip01, as
Martial Arts Core's Pak Mei dodges do), and the clip matches their length (26 frames at 30 fps) and
distance, so Core's dodge (nativeRoot, distance) times and measures it the same way.

Usage: make_dodge.py [--pz PATH_TO_projectzomboid]   (writes common/media/anims_X/PSF/PSF_Dodge*.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import DEFAULT_PZ, Pose, _rodrigues, rotation_between, solve_leg, write

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "PhotonSwordForms/Contents/mods/PhotonSwordForms/common/media/anims_X/PSF"
BASE = "media/anims_X/Bob/Bob_IdleAim1Hand.x"

# The model's space: +X is the character's left, +Y up, -Z forward.
DODGES = {
    "PSF_DodgeLeft": np.array([1.0, 0.0, 0.0]),
    "PSF_DodgeRight": np.array([-1.0, 0.0, 0.0]),
    "PSF_DodgeBack": np.array([0.0, 0.0, 1.0]),
}
DISTANCE = 1.23        # root travel in model units (~2 tiles, as Core's Pak Mei dodges)
TICKS = 4160           # clip length: 26 frames at 30 fps (4800 ticks a second)
KEYS = 26              # keyframe intervals over the clip

# Phases, as fractions of the clip.
TAKEOFF, LANDING = 0.20, 0.60
# The root's height over the standing pose through the dodge: (fraction, model units). Crouch to
# load, arc up through the leap, absorb the landing, rise.
HEIGHT = [(0.0, 0.0), (0.14, -0.07), (0.22, 0.0), (0.40, 0.10), (0.58, 0.01), (0.68, -0.09),
          (0.82, -0.04), (0.96, 0.0), (1.0, 0.0)]
# How much of the distance the root has covered: a little in the crouch, most in the air, the rest
# sliding out of the landing.
TRAVEL = [(0.0, 0.0), (0.14, 0.04), (TAKEOFF, 0.10), (LANDING, 0.90), (0.80, 1.0), (1.0, 1.0)]
FOOT_LIFT = 0.13       # how high the feet tuck up at the top of the leap
LEAN = {"side": 14.0, "back": 10.0}   # degrees the torso leans into the leap at its height
OFF_ARM = 40.0         # degrees the off arm swings out for balance at the leap's height


def curve(points, u):
    """Eased curve through (fraction, value) points: smoothstep between each pair."""
    for (u0, v0), (u1, v1) in zip(points, points[1:]):
        if u <= u1:
            f = (u - u0) / (u1 - u0)
            return v0 + (v1 - v0) * f * f * (3 - 2 * f)
    return points[-1][1]


def bump(u, start, peak, end):
    """0 outside start-end, rising smoothly to 1 at peak."""
    if u <= start or u >= end:
        return 0.0
    f = (u - start) / (peak - start) if u < peak else (end - u) / (end - peak)
    return f * f * (3 - 2 * f)


def tilt(direction, degrees):
    """Column-vector rotation tipping up (+Y) toward direction by degrees."""
    a = np.radians(degrees)
    return rotation_between(np.array([0, 1.0, 0]), np.array([0, np.cos(a), 0]) + direction * np.sin(a))


def frame(base, holds, direction, u):
    pose = base.copy()
    step = direction * DISTANCE
    side = "back" if direction[2] > 0 else "side"

    # The root along its path and arc.
    root = base.world["Bip01"].copy()
    root[3, :3] += step * curve(TRAVEL, u) + np.array([0, curve(HEIGHT, u), 0])
    pose.set_world("Bip01", root)

    # Lean into the leap, head held level. The thighs hang off the spine, so the legs are solved after.
    lean = LEAN[side] * bump(u, 0.10, 0.40, 0.75)
    q = tilt(direction, lean)
    pose.rotate_world("Bip01_Spine", q)
    pose.rotate_world("Bip01_Head", q.T)

    # Feet: planted until takeoff, carried over (tucked up) in the air, planted again on landing.
    air = min(1.0, max(0.0, (u - TAKEOFF) / (LANDING - TAKEOFF)))
    carry = air * air * (3 - 2 * air)
    for s in "RL":
        foot = base.world[f"Bip01_{s}_Foot"].copy()
        foot[3, :3] += step * carry + np.array([0, FOOT_LIFT * np.sin(np.pi * air), 0])
        solve_leg(pose, s, foot)

    # The off arm swings out to the side for balance.
    swing = OFF_ARM * bump(u, 0.12, 0.40, 0.80)
    arm = pose.world["Bip01_L_UpperArm"]
    hang = pose.position("Bip01_L_Forearm") - arm[3, :3]
    out = np.array([1.0, 0.0, 0.0])
    pose.rotate_world("Bip01_L_UpperArm", rotation_between(hang, hang * np.cos(np.radians(swing))
                                                           + np.linalg.norm(hang) * out * np.sin(np.radians(swing))))

    # The hilt stays in the sword fist, and Prop2 with the off hand, as in the vanilla pose.
    pose.set_world("Bip01_Prop1", holds["Bip01_Prop1"] @ pose.world["Bip01_R_Hand"])
    pose.set_world("Bip01_Prop2", holds["Bip01_Prop2"] @ pose.world["Bip01_L_Hand"])
    return pose


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()

    clip = xfile.XFile(args.pz / BASE)
    base = Pose(clip)
    holds = {"Bip01_Prop1": base.world["Bip01_Prop1"] @ np.linalg.inv(base.world["Bip01_R_Hand"]),
             "Bip01_Prop2": base.world["Bip01_Prop2"] @ np.linalg.inv(base.world["Bip01_L_Hand"])}
    for name, direction in DODGES.items():
        frames = [(round(TICKS * i / KEYS), frame(base, holds, direction, i / KEYS)) for i in range(KEYS + 1)]
        grip = max(np.linalg.norm((p.world["Bip01_Prop1"] @ np.linalg.inv(p.world["Bip01_R_Hand"]))[3, :3]
                                  - holds["Bip01_Prop1"][3, :3]) for _, p in frames)
        travel = frames[-1][1].position("Bip01") - frames[0][1].position("Bip01")
        low = min(min(p.position(f"Bip01_{s}_Foot")[1] for s in "RL") for _, p in frames)
        print(f"{name}: root travels {np.round(travel, 3)}, hilt slips {grip:.2g} from the fist, "
              f"lowest foot {low:.3f}")
        write(clip, frames, args.out / f"{name}.x", name)


if __name__ == "__main__":
    main()
