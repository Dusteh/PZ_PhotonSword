#!/usr/bin/env python3
"""Author PS_Guard, the photon sword's aiming stance, as a looped Project Zomboid animation.

A high guard after Obi-Wan Kenobi's: starts from vanilla's one-handed aim (Bob_IdleAim1Hand, frame
0), whose feet are already set for a fight, left foot forward, and turns the shoulders further so
the off shoulder leads (the head turns back to face ahead). The sword arm's upper arm is level
with the shoulders, reaching forward and out, and the forearm carries on forward and up from an elbow
bent about 30 degrees to a fist ahead of the face; the blade is held level above the shoulders, pointing ahead (the way the character faces while aiming, toward the cursor)
and across toward the off side, the palm turned out and down. It grips the hilt as the rests do
(make_rest.py: vanilla's one-handed fist, halfway along the hilt). The off arm reaches ahead toward
the target with the elbow relaxed, palm up, and beckons: the fingers curl in and open twice over
each loop, the wrist lifting with them. The pose breathes as a held pose does (animlib.py): the
chest rises, the shoulders lift, and the body sinks and rises a little on planted feet; the sword
and the off hand ride with it.

In the model's space +X is the character's left, +Y up, -Z forward. A hand bone's +X runs along its
fingers and its +Z is its palm's normal. The weapon's blade runs along Prop1's +Y axis.

Usage: make_guard.py [--pz PATH_TO_projectzomboid]   (writes common/media/anims_X/PS/PS_Guard.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import (DEFAULT_PZ, BREATH_SECONDS, CHEST_DEGREES, SHOULDER_DEGREES, SINK, Pose, _rodrigues,
                        rotation_between, solve_leg, solve_limb, write)
from make_rest import ANIMS, GRIP_AT, GRIP_BASE, OUT, grip_of

NAME = "PS_Guard"
BASE = "Bob_IdleAim1Hand"
KEYS = 26   # keyframes per loop (a tenth of a second apart, enough for the beckon)
TORSO_TURN = 30   # degrees the shoulders turn about Y, off shoulder forward (the head turns back to face ahead)

# The sword: the middle of the fist relative to the head bone (out, up, forward; the top of the head
# is about 0.155 above the head bone and the chin about level with it; the shoulder is about 0.05 below it), the blade's direction, where the palm faces, and the elbow's
# pole. The fist's grip ties the palm to the blade: with the forearm rising to the fist and the
# blade pointing ahead, the palm faces out. The reference turns it a little down, which these short
# arms (about 0.27 from shoulder to wrist) only manage with a straight-ish wrist if the blade swings
# further across toward the off side; turned further down, or the blade straighter ahead, the wrist
# bends past 45 degrees. Held level above the shoulders with the upper arm level and the elbow open
# (bent 30 to 40 degrees), the upper arm has to reach forward rather than out to the side, and the
# palm turns out and down. The fist sits out far enough that the hilt clears the head (see the printed
# wrist bend and head clearance).
FIST = np.array([-0.284, 0.077, -0.18])       # ahead and out, at eye height
BLADE = np.array([0.6, 0.0, -1.0])            # level, ahead and across toward the off side
SWORD_PALM = np.array([-1.0, -0.46, 0.34])    # out and down
SWORD_ELBOW = np.array([0.11, -1.13, 0.2])    # down (the upper arm comes out level)
HILT = (-0.065, 0.122)                        # the hilt's ends along +Y (PhotonSword_Hilt.x), for clearance
HILT_RADIUS = 0.016

# The off arm: the hand's direction from the shoulder (out, up, forward) and how far along the arm's
# full reach it sits (under 1 bends the elbow), the fingers' direction, and the elbow's pole. It
# reaches ahead, toward the target, from the leading shoulder.
REACH = np.array([0.35, 0.05, -1.0])
REACH_FRACTION = 0.92
OFF_FINGERS = np.array([0.35, 0.05, -1.0])    # along the reach
OFF_PALM = np.array([0.0, 1.0, 0.0])          # up
OFF_ELBOW = np.array([0.3, -1.0, 0.3])        # down, a little out and back

# The beckon: the loop's two curls of the fingers (degrees at the full curl), each over BECKON of the
# loop, then the hand rests open; the wrist lifts with each curl.
CURL_DEGREES = 75
WRIST_DEGREES = 15
BECKON = 0.25


def hand_frame(fingers, palm, position):
    """A hand bone's world matrix: +X along fingers, +Z along palm (made perpendicular), at position."""
    x = fingers / np.linalg.norm(fingers)
    z = palm - np.dot(palm, x) * x
    z /= np.linalg.norm(z)
    m = np.eye(4)
    m[0, :3], m[1, :3], m[2, :3], m[3, :3] = x, np.cross(z, x), z, position
    return m


def sword_target(pose, grip):
    """The weapon bone's world matrix: blade along BLADE, the palm turned toward SWORD_PALM."""
    blade = BLADE / np.linalg.norm(BLADE)
    fist = pose.position("Bip01_Head") + FIST
    # The hand's turn about the blade comes from the grip; spin the weapon so the palm lands on SWORD_PALM.
    prop = np.eye(4)
    prop[:3, :3] = rotation_between(np.array([0, 1.0, 0]), blade).T
    palm = (np.linalg.inv(grip) @ prop)[2, :3]
    want = SWORD_PALM - np.dot(SWORD_PALM, blade) * blade
    spin = rotation_between(palm - np.dot(palm, blade) * blade, want)
    prop[:3, :3] = prop[:3, :3] @ spin.T
    prop[3, :3] = fist - blade * GRIP_AT
    return prop


def off_target(pose):
    shoulder = pose.position("Bip01_L_UpperArm")
    reach = (np.linalg.norm(pose.position("Bip01_L_Forearm") - shoulder)
             + np.linalg.norm(pose.position("Bip01_L_Hand") - pose.position("Bip01_L_Forearm")))
    direction = REACH / np.linalg.norm(REACH)
    return hand_frame(OFF_FINGERS, OFF_PALM, shoulder + direction * reach * REACH_FRACTION)


def build(clip, grip):
    pose = Pose(clip)
    # Turn the shoulders, off shoulder leading, and turn the head back to face ahead.
    for bone in ("Bip01_Spine", "Bip01_Spine1"):
        pose.rotate_world(bone, _rodrigues(np.array([0, 1.0, 0]), np.radians(TORSO_TURN / 2)))
    pose.rotate_world("Bip01_Neck", _rodrigues(np.array([0, 1.0, 0]), np.radians(-TORSO_TURN)))
    prop = sword_target(pose, grip)
    solve_limb(pose, "Bip01_R_UpperArm", "Bip01_R_Forearm", "Bip01_R_Hand", np.linalg.inv(grip) @ prop, SWORD_ELBOW)
    pose.set_world("Bip01_Prop1", prop)
    solve_limb(pose, "Bip01_L_UpperArm", "Bip01_L_Forearm", "Bip01_L_Hand", off_target(pose), OFF_ELBOW)
    return pose


def beckon(phase):
    """The fingers' curl (0 open, 1 closed) at phase (0-1) of the loop."""
    for start in (0.0, BECKON):
        t = (phase - start) / BECKON
        if 0 <= t < 1:
            return np.sin(np.pi * t) ** 2
    return 0.0


def frame(held, grip, phase):
    """The guard at phase (0-1) of the loop: a breath and the beckon."""
    inhale = 0.5 - 0.5 * np.cos(2 * np.pi * phase)   # 0 at rest, 1 at the top of the breath
    pose = held.copy()
    feet = {side: held.world[f"Bip01_{side}_Foot"].copy() for side in "RL"}
    sword, off = held.world["Bip01_Prop1"].copy(), held.world["Bip01_L_Hand"].copy()
    drop = -SINK * (1 - inhale)

    root = pose.world["Bip01"].copy()
    root[3, 1] += drop
    pose.set_world("Bip01", root)
    for side in "RL":
        solve_leg(pose, side, feet[side])

    chest = np.radians(CHEST_DEGREES * inhale)
    pose.rotate_world("Bip01_Spine1", _rodrigues(np.array([1.0, 0, 0]), chest))
    pose.rotate_world("Bip01_Head", _rodrigues(np.array([1.0, 0, 0]), -chest))
    for side, sign in (("L", 1), ("R", -1)):
        pose.rotate_world(f"Bip01_{side}_Clavicle",
                          _rodrigues(np.array([0, 0, 1.0]), np.radians(sign * SHOULDER_DEGREES * inhale)))

    sword[3, 1] += drop
    solve_limb(pose, "Bip01_R_UpperArm", "Bip01_R_Forearm", "Bip01_R_Hand", np.linalg.inv(grip) @ sword, SWORD_ELBOW)
    pose.set_world("Bip01_Prop1", sword)

    # The off hand settles with the body, and its wrist lifts and fingers curl toward the palm.
    curl = beckon(phase)
    off[3, 1] += drop
    lift = _rodrigues(off[1, :3], -np.radians(WRIST_DEGREES * curl))
    off[:3, :3] = off[:3, :3] @ lift.T
    solve_limb(pose, "Bip01_L_UpperArm", "Bip01_L_Forearm", "Bip01_L_Hand", off, OFF_ELBOW)
    finger = pose.world["Bip01_L_Finger1"]
    axis = np.cross(finger[0, :3], pose.world["Bip01_L_Hand"][2, :3])
    pose.rotate_world("Bip01_L_Finger1", _rodrigues(axis / np.linalg.norm(axis), np.radians(CURL_DEGREES * curl)))
    return pose


def bend(pose, side):
    """Degrees between a forearm and its hand's fingers."""
    arm = pose.position(f"Bip01_{side}_Hand") - pose.position(f"Bip01_{side}_Forearm")
    fingers = pose.world[f"Bip01_{side}_Hand"][0, :3]
    return np.degrees(np.arccos(np.clip(np.dot(arm / np.linalg.norm(arm), fingers), -1, 1)))


def elbow(pose, side):
    """Degrees the elbow bends (0 straight)."""
    upper = pose.position(f"Bip01_{side}_Forearm") - pose.position(f"Bip01_{side}_UpperArm")
    fore = pose.position(f"Bip01_{side}_Hand") - pose.position(f"Bip01_{side}_Forearm")
    return np.degrees(np.arccos(np.clip(np.dot(upper, fore) / np.linalg.norm(upper) / np.linalg.norm(fore), -1, 1)))


def head_clearance(clip, pose):
    """The closest the hilt's surface comes to the head and neck's skin (negative: it passes through)."""
    near = sorted({i for bone, indices, weights, _ in clip.skins if bone in ("Bip01_Head", "Bip01_Neck")
                   for i in indices[weights > 0.3]})
    verts = clip.skinned(pose.world)[near]
    prop = pose.world["Bip01_Prop1"]
    a, b = prop[3, :3] + HILT[0] * prop[1, :3], prop[3, :3] + HILT[1] * prop[1, :3]
    t = np.clip((verts - a) @ (b - a) / np.dot(b - a, b - a), 0, 1)
    return np.min(np.linalg.norm(verts - (a + t[:, None] * (b - a)), axis=1)) - HILT_RADIUS


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT / f"{NAME}.x")
    args = parser.parse_args()

    def load(name):
        return xfile.XFile(args.pz / ANIMS / f"{name}.x")

    grip = grip_of(load(GRIP_BASE))
    clip = load(BASE)
    held = build(clip, grip)
    frames = [(round(i / KEYS * BREATH_SECONDS * clip.ticks), frame(held, grip, (i % KEYS) / KEYS))
              for i in range(KEYS + 1)]
    slide = max(np.linalg.norm(p.position(f"Bip01_{s}_Foot") - held.position(f"Bip01_{s}_Foot"))
                for _, p in frames for s in "RL")
    slip = max(np.linalg.norm((grip @ p.world["Bip01_R_Hand"])[3, :3] - p.world["Bip01_Prop1"][3, :3])
               for _, p in frames)
    fist = held.world["Bip01_Prop1"][3, :3] + held.world["Bip01_Prop1"][1, :3] * GRIP_AT
    print(f"{len(frames)} keys over {BREATH_SECONDS}s; feet slide {slide:.2g}, sword hand slips {slip:.2g}; "
          f"fist {fist[1] - held.position('Bip01_Head')[1]:.2f} above the head bone; "
          f"hilt clears the head by {min(head_clearance(clip, p) for _, p in frames):.3f}; "
          f"sword wrist bend {bend(held, 'R'):.0f}, elbow {elbow(held, 'R'):.0f}; "
          f"off wrist bend {bend(held, 'L'):.0f}, elbow {elbow(held, 'L'):.0f} degrees")
    write(clip, frames, args.out, NAME)


if __name__ == "__main__":
    main()
