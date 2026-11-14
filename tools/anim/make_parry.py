#!/usr/bin/env python3
"""Author PS_Parry, the photon sword meeting another photon sword: a one-pass block from the ready stance.

Played over the ready stance (PS_Ready, make_ready.py) when the guard blocks a photon sword's strike
(PS_Stance.lua sets PSParry for the clip's length). From the ready guard, both hands sweep the
sword up into a high cross-guard in front of the face: the hilt ahead of the sword shoulder, the
blade across the body toward the off side, rising, its edge turned out to meet a strike coming down
from ahead. The blades meet (IMPACT): the strike drives the sword back toward the face and the body
gives with it, rocking back off the front foot and sinking into the knees; then the guard pushes
back out, holds a beat, and settles back down into the ready stance, both fists on the hilt the
whole time and the feet planted. The breath runs on underneath, so the clip leaves the loop where
it joined it.

The keys use make_ready.py's own grips, arm IK (solve_arm: elbows bend only on their hinge), and
breath, so the clip starts and ends on PS_Ready's pose exactly.

In the model's space +X is the character's left, +Y up, -Z forward. The weapon's blade runs along
Prop1's +Y axis.

Usage: make_parry.py [--pz PATH_TO_projectzomboid]   (writes common/media/anims_X/PS/PS_Parry.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import DEFAULT_PZ, BREATH_SECONDS, Pose, _rodrigues, rotation_between, solve_leg, write
from make_guard import elbow
from make_ready import (BASE, OFF_ELBOW, REST, SWORD_AT, SWORD_ELBOW, arm_clearance, build, frame, grips, slerp,
                        slip, smooth, solve_arm, wrist)
from make_rest import ANIMS, GRIP_BASE, OUT

NAME = "PS_Parry"
SECONDS = 0.9
KEYS = 27               # keyframe intervals (30 a second)

# Phases (seconds): the sweep up to the guard, the blades meeting, the guard pushed back out, the
# hold, and the settle back to the ready stance.
RAISE_END = 0.16
IMPACT = 0.18
RECOIL_END = 0.36
SETTLE_START = 0.48

# The cross-guard: the middle of the sword fist relative to the head bone (out, up, forward: on the
# sword side, under and ahead of the chin), the blade's direction (across the face toward the off
# side, rising), and each elbow's pole. These and EDGE_ROLL were chosen together (a search over
# them) to keep both fists on the hilt, the wrists near their resting twist, the elbows bent, the
# arms clear of the torso, and the blade clear of the head.
GUARD_FIST = np.array([-0.10, -0.10, -0.18])
GUARD_BLADE = np.array([0.8, 0.5, 0.0])
GUARD_SWORD_ELBOW = np.array([-0.9, -0.3, 0.3])    # out to the sword side, a little down and back
GUARD_OFF_ELBOW = np.array([0.3, -0.9, 0.3])       # down
EDGE_ROLL = 20          # degrees the sword turns about the blade so its edge faces the strike

# The impact: how far the strike drives the sword back and down, how far it twists the blade back
# toward the face, and how the body gives (rock back about the hips, sink into the knees).
RECOIL = np.array([0.0, -0.035, 0.07])
RECOIL_TWIST = 8
BODY_ROCK = 5           # degrees back
BODY_SINK = 0.02

# On the way up and back down, the sword arcs out ahead of the straight path and the off elbow
# swings out, so the off forearm passes clear of the stomach (as the beckon's does).
PATH_ARC = 0.06
OFF_SWING_OUT = 0.8


def guard_sword(pose, ready_sword):
    """The weapon bone's world matrix in the cross-guard: ready's, turned onto GUARD_BLADE the short
    way (so the fists keep their grip on the hilt as they turned it), rolled EDGE_ROLL about the blade,
    with the sword fist's middle at GUARD_FIST from the head."""
    ready_blade = ready_sword[1, :3] / np.linalg.norm(ready_sword[1, :3])
    blade = GUARD_BLADE / np.linalg.norm(GUARD_BLADE)
    turn = rotation_between(ready_blade, blade) @ _rodrigues(ready_blade, np.radians(EDGE_ROLL))
    sword = ready_sword.copy()
    sword[:3, :3] = ready_sword[:3, :3] @ turn.T
    # As make_ready.py places it: the sword fist's middle sits SWORD_AT along the hilt from the bone.
    sword[3, :3] = pose.position("Bip01_Head") + GUARD_FIST - sword[1, :3] * SWORD_AT
    return sword


def bump(t, start, peak, end):
    """0 before start, rising to 1 at peak, falling back to 0 at end (smoothed)."""
    if t <= start or t >= end:
        return 0.0
    if t <= peak:
        return smooth((t - start) / (peak - start))
    return 1 - smooth((t - peak) / (end - peak))


def parry_frame(held, hands, t):
    """The parry at t seconds."""
    pose = frame(held, hands, t / BREATH_SECONDS % 1)
    ready = pose.world["Bip01_Prop1"].copy()
    guard = guard_sword(pose, ready)

    # How far into the guard: up by RAISE_END, held, back down from SETTLE_START.
    up = smooth(t / RAISE_END) * (1 - smooth((t - SETTLE_START) / (SECONDS - SETTLE_START)))
    hit = bump(t, IMPACT - 0.02, IMPACT + 0.03, RECOIL_END)

    # The body gives with the hit: rock back about the hips and sink, feet planted.
    if hit > 0:
        feet = {side: pose.world[f"Bip01_{side}_Foot"].copy() for side in "RL"}
        root = pose.world["Bip01"].copy()
        root[3, 1] -= BODY_SINK * hit
        pose.set_world("Bip01", root)
        # The legs hang from the spine, so put the feet back after rocking it.
        pose.rotate_world("Bip01_Spine", _rodrigues(np.array([1.0, 0, 0]), np.radians(-BODY_ROCK * hit)))
        for side in "RL":
            solve_leg(pose, side, feet[side])
        guard = guard_sword(pose, ready)

    sword = np.eye(4)
    sword[:3, :3] = slerp(ready[:3, :3], guard[:3, :3], up)
    swing = np.sin(np.pi * up)   # 0 at either end of the sweep, 1 halfway
    sword[3, :3] = ready[3, :3] + (guard[3, :3] - ready[3, :3]) * up + np.array([0, 0, -PATH_ARC]) * swing
    # The strike drives the guard back toward the face, twisting the blade back a little.
    if hit > 0:
        # Turned about the axis across the blade and the line back to the body: the tip tips back.
        blade = sword[1, :3] / np.linalg.norm(sword[1, :3])
        axis = np.cross(blade, np.array([0, 0, 1.0]))
        sword[:3, :3] = sword[:3, :3] @ _rodrigues(axis / np.linalg.norm(axis), np.radians(RECOIL_TWIST * hit)).T
        sword[3, :3] = sword[3, :3] + RECOIL * hit
    solve_arm(pose, "R", hands["R"] @ sword, SWORD_ELBOW + (GUARD_SWORD_ELBOW - SWORD_ELBOW) * up)
    solve_arm(pose, "L", hands["L"] @ sword,
              OFF_ELBOW + (GUARD_OFF_ELBOW - OFF_ELBOW) * up + np.array([OFF_SWING_OUT, 0, 0]) * swing)
    pose.set_world("Bip01_Prop1", sword)
    return pose


def head_gap(clip, pose):
    """The closest the blade's first 0.4 (model units) comes to the head's skin (negative: through it)."""
    near = sorted({i for bone, indices, weights, _ in clip.skins if bone in ("Bip01_Head", "Bip01_Neck")
                   for i in indices[weights > 0.3]})
    verts = clip.skinned(pose.world)[near]
    prop = pose.world["Bip01_Prop1"]
    a, b = prop[3, :3] + prop[1, :3] * 0.12, prop[3, :3] + prop[1, :3] * 0.52
    t = np.clip((verts - a) @ (b - a) / np.dot(b - a, b - a), 0, 1)
    return float(np.min(np.linalg.norm(verts - (a + t[:, None] * (b - a)), axis=1)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT / f"{NAME}.x")
    args = parser.parse_args()

    def load(name):
        return xfile.XFile(args.pz / ANIMS / f"{name}.x")

    base, rest, clip = load(GRIP_BASE), Pose(load(REST)), load(BASE)
    hands = grips(base)
    held = build(clip, base, hands)
    frames = [(round(i / KEYS * SECONDS * clip.ticks), parry_frame(held, hands, i / KEYS * SECONDS))
              for i in range(KEYS + 1)]
    guard = frames[round(KEYS * (IMPACT - 0.01) / SECONDS)][1]
    start, end = frames[0][1], frames[-1][1]
    ready_start, ready_end = frame(held, hands, 0), frame(held, hands, SECONDS / BREATH_SECONDS % 1)
    joins = max(max(np.abs(start.world[n] - ready_start.world[n]).max() for n in start.world),
                max(np.abs(end.world[n] - ready_end.world[n]).max() for n in end.world))
    slide = max(np.linalg.norm(p.position(f"Bip01_{s}_Foot") - held.position(f"Bip01_{s}_Foot"))
                for _, p in frames for s in "RL")
    print(f"{len(frames)} keys over {SECONDS}s; joins the ready loop within {joins:.2g}; feet slide {slide:.2g}; "
          f"hands slip {max(slip(p, hands) for _, p in frames):.2g}; arms clear the torso by "
          f"{min(arm_clearance(clip, p, 'R') for _, p in frames):.3f} (sword), "
          f"{min(arm_clearance(clip, p, 'L') for _, p in frames):.3f} (off); blade clears the head by "
          f"{min(head_gap(clip, p) for _, p in frames):.3f}; in the guard "
          + "; ".join("{} wrist twist {:.0f}, swing {:.0f}, elbow {:.0f}".format(name, *wrist(guard, rest, s), elbow(guard, s))
                      for name, s in (("sword", "R"), ("off", "L"))) + " degrees")
    write(clip, frames, args.out, NAME)


if __name__ == "__main__":
    main()
