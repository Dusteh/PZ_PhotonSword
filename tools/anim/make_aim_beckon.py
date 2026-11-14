#!/usr/bin/env python3
"""Author PS_AimBeckon: the ready stance's beckon for aiming an extinguished hilt.

An unlit hilt is a one-handed weapon, so aiming it plays vanilla's one-handed aim (Bob_IdleAim1Hand),
the off hand free at the side. Now and then (PS_Stance.lua picks when, as for PS_ReadyBeckon) this
plays in its place: vanilla's aim carries on, and the off hand lifts ahead palm up, beckons twice, and
drops back to the side. The lift, curls, and return keep PS_ReadyBeckon's timing and target
(make_ready.py's BECKON_*); the hand starts from and returns to where vanilla's aim holds it.

Usage: make_aim_beckon.py [--pz PATH_TO_projectzomboid]   (writes common/media/anims_X/PS/PS_AimBeckon.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import DEFAULT_PZ, Pose, write
from make_guard import elbow
from make_ready import (BECKON_ARC, BECKON_CURL, BECKON_CURL_SECONDS, BECKON_CURLS, BECKON_ELBOW, BECKON_LIFT,
                        BECKON_RETURN, BECKON_SECONDS, BECKON_SWING_OUT, FINGERS, MIRROR_Y, REST, arm_clearance,
                        beckon_target, slerp, smooth, solve_arm, wrist)
from make_rest import ANIMS, GRIP_BASE, OUT

NAME = "PS_AimBeckon"
BASE = "Bob_IdleAim1Hand"
EASE = 0.3   # the arm eases from vanilla's onto the solved one over this much of the lift
ARM = ("UpperArm", "Forearm", "Hand")


def pose_at(clip, seconds):
    """The base clip's pose at seconds, looping."""
    ticks = max(t for keys in clip.keys.values() for kind in keys.values() for t, _ in kind)
    pose = Pose(clip)
    pose.local = clip.local_matrices(round(seconds * clip.ticks) % ticks if ticks else 0)
    pose.update()
    return pose


def home_pole(pose):
    """The direction the off elbow points off the shoulder-to-wrist line in pose."""
    shoulder, elbow_, hand = (pose.position(f"Bip01_L_{b}") for b in ("UpperArm", "Forearm", "Hand"))
    reach = (hand - shoulder) / np.linalg.norm(hand - shoulder)
    out = elbow_ - shoulder
    return out - np.dot(out, reach) * reach


def beckon_frame(clip, fingers, t):
    """The beckon at t seconds over vanilla's aim. fingers: the off hand's finger rotations (open, fist)."""
    pose = pose_at(clip, t)
    home_fingers = {f: pose.local[f"Bip01_L_{f}"][:3, :3].copy() for f in FINGERS}
    lift = smooth(t / BECKON_LIFT) * (1 - smooth((t - BECKON_RETURN) / BECKON_LIFT))
    if lift <= 0:
        return pose
    home, out = pose.world["Bip01_L_Hand"].copy(), beckon_target(pose)
    target = np.eye(4)
    target[:3, :3] = slerp(home[:3, :3], out[:3, :3], lift)
    target[3, :3] = home[3, :3] + (out[3, :3] - home[3, :3]) * lift + np.array([0, 0, -BECKON_ARC]) * np.sin(np.pi * lift)
    start = home_pole(pose)
    start /= np.linalg.norm(start)
    pole = start + (BECKON_ELBOW - start) * lift + np.array([BECKON_SWING_OUT, 0, 0]) * np.sin(np.pi * lift)
    vanilla = {b: pose.local[f"Bip01_L_{b}"][:3, :3].copy() for b in ARM}
    solve_arm(pose, "L", target, pole)
    # The solved arm sits a little off vanilla's even at the start, so ease from one to the other.
    ease = smooth(lift / EASE)
    for b in ARM:
        pose.local[f"Bip01_L_{b}"][:3, :3] = slerp(vanilla[b], pose.local[f"Bip01_L_{b}"][:3, :3], ease)
    # The relaxed hand opens as it lifts; then the fingers curl in and open, and it relaxes as it drops.
    curl = BECKON_CURL * sum(np.sin(np.pi * smooth((t - s) / BECKON_CURL_SECONDS)) ** 2 for s in BECKON_CURLS)
    for finger in FINGERS:
        open_, fist = fingers[finger]
        beckoning = slerp(open_, fist, curl if finger == "Finger1" else 0)
        pose.local[f"Bip01_L_{finger}"][:3, :3] = slerp(home_fingers[finger], beckoning, lift)
    pose.update()
    return pose


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT / f"{NAME}.x")
    args = parser.parse_args()

    def load(name):
        return xfile.XFile(args.pz / ANIMS / f"{name}.x")

    clip = load(BASE)
    rest = Pose(load(REST))
    fist = Pose(load(GRIP_BASE))
    fingers = {f: (rest.local[f"Bip01_L_{f}"][:3, :3],
                   MIRROR_Y @ fist.local[f"Bip01_R_{f}"][:3, :3] @ MIRROR_Y) for f in FINGERS}
    keys = round(BECKON_SECONDS * 10)
    frames = [(round(i / keys * BECKON_SECONDS * clip.ticks), beckon_frame(clip, fingers, i / keys * BECKON_SECONDS))
              for i in range(keys + 1)]
    top = frames[round(keys * (BECKON_LIFT + 0.1) / BECKON_SECONDS)][1]
    # Where the solved arm leaves vanilla's at the smallest lift: how far the elbow jumps.
    first = next(p for _, p in frames[1:])
    jump = np.linalg.norm(first.position("Bip01_L_Forearm") - pose_at(clip, BECKON_SECONDS / keys).position("Bip01_L_Forearm"))
    resting = min(arm_clearance(clip, pose_at(clip, t / 10), "L") for t in range(25))
    print(f"vanilla's off arm clears the torso by {resting:.3f}")
    print(f"{NAME}: {len(frames)} keys over {BECKON_SECONDS}s; elbow off vanilla's at the first lifted key "
          f"{jump:.3f}; off arm clears the torso by {min(arm_clearance(clip, p, 'L') for _, p in frames):.3f}; "
          f"beckoning wrist twist {{:.0f}}, swing {{:.0f}}, elbow {elbow(top, 'L'):.0f} degrees".format(*wrist(top, rest, "L")))
    write(clip, frames, args.out, NAME)


if __name__ == "__main__":
    main()
