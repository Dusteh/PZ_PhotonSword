#!/usr/bin/env python3
"""Author PSF_Block, the photon sword's block pose, as a looped Project Zomboid animation.

Starts from vanilla's two-handed aim (Bob_IdleAimBat, frame 0), squares the torso, moves the
weapon bone (Bip01_Prop1) to a center guard (two-handed, hilt in front of the body's middle,
blade held vertical), then solves both arms so each hand keeps its grip on the weapon as in the
vanilla pose. The held pose breathes: over each loop the chest rises and the shoulders lift, the
body sinks and rises a little on planted feet, and the sword rides along in both hands.
The weapon's blade runs along Prop1's +Y axis.

Also writes PSF_BlockParry, played once over the block when it stops another photon sword's strike
(PSF_Core.lua sets PSFParry for its length): the blades meet, the strike drives the guard back toward
the chest and down, knocking the tip out toward the off side, and the body gives with it, rocking
back and sinking into the knees on planted feet; then the guard pushes back out to the held pose.

Usage: make_block.py [--pz PATH_TO_projectzomboid]
       (writes common/media/anims_X/PSF/PSF_Block.x and PSF_BlockParry.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import (DEFAULT_PZ, BREATH_KEYS, BREATH_SECONDS, CHEST_DEGREES, SHOULDER_DEGREES,
                     SINK, Pose, _rodrigues, rotation_between, solve_leg, solve_limb, write)
from make_parry import head_gap

ROOT = Path(__file__).resolve().parents[2]
# Under common/, not 42/: the game only loads a mod's 42/media/anims_X if common/media/anims_X exists
# (ModelManager.loadHumanAnimations returns early otherwise), and clips aren't version-specific.
OUT = ROOT / "PhotonSwordForms/Contents/mods/PhotonSwordForms/common/media/anims_X/PSF/PSF_Block.x"
BASE = "media/anims_X/Bob/Bob_IdleAimBat.x"
NAME = "PSF_Block"

# The pose, in the model's space: +X is the character's left, +Y up, -Z forward.
GRIP = np.array([0.01, 0.58, -0.18])         # where the weapon bone (the grip) sits: centerline, mid-torso
BLADE = np.array([0.0, 1.0, -0.05])          # blade direction: straight up, tip a touch forward
TORSO_TURN = -45                              # degrees about Y to square the shoulders, split over the spine
ELBOW_POLE = {"R": np.array([-0.4, -1.0, 0.2]), "L": np.array([0.4, -1.0, 0.2])}  # elbows down, a little out
# Each hand's turn (degrees) around the hilt from its grip in the vanilla bat pose, chosen so the
# wrist lines up with the forearm (see --search).
GRIP_ROLL = {"R": 300.0, "L": 300.0}

# The breath (animlib.py's), plus:
SWORD_LIFT = 0.004     # the sword rises a touch on the inhale

# The parry (PSF_BlockParry): its length and keys (30 a second), when the blades meet, when the
# guard is back out; how far the strike drives the sword (back toward the chest and down) and knocks
# the blade over toward the off side (the blade stands in front of the face, so it can't tip back),
# and how the body gives (degrees back about the hips, sink into the knees).
PARRY_NAME = "PSF_BlockParry"
PARRY_SECONDS = 0.5
PARRY_KEYS = 15
PARRY_IMPACT = 0.06
PARRY_RECOVER = 0.42
PARRY_RECOIL = np.array([0.0, -0.03, 0.04])
PARRY_KNOCK = 14
PARRY_ROCK = 5
PARRY_SINK = 0.02


def solve_arm(pose, side, hand_world):
    solve_limb(pose, *(f"Bip01_{side}_{b}" for b in ("UpperArm", "Forearm", "Hand")), hand_world, ELBOW_POLE[side])


def build(clip):
    """The held block pose, plus what each breath frame needs to rebuild it."""
    pose = Pose(clip)
    prop = pose.world["Bip01_Prop1"].copy()
    # Each hand's grip and Prop2 (the off-hand prop) relative to the weapon, from the vanilla pose.
    grips = {side: pose.world[f"Bip01_{side}_Hand"] @ np.linalg.inv(prop) for side in "RL"}
    for side in "RL":
        # Turning the grip about the weapon's own Y axis keeps the hand wrapped on the hilt.
        roll = np.eye(4)
        roll[:3, :3] = _rodrigues(np.array([0, 1.0, 0]), np.radians(GRIP_ROLL[side])).T
        grips[side] = grips[side] @ roll
    prop2 = pose.world["Bip01_Prop2"] @ np.linalg.inv(pose.world["Bip01_L_Hand"])

    for bone in ("Bip01_Spine", "Bip01_Spine1"):
        pose.rotate_world(bone, _rodrigues(np.array([0, 1.0, 0]), np.radians(TORSO_TURN / 2)))

    target = prop.copy()
    target[:3, :3] = prop[:3, :3] @ rotation_between(prop[1, :3], BLADE).T
    target[3, :3] = GRIP
    pose.set_world("Bip01_Prop1", target)
    for side in "RL":
        solve_arm(pose, side, grips[side] @ target)
    pose.set_world("Bip01_Prop2", prop2 @ pose.world["Bip01_L_Hand"])
    return pose, grips, prop2


def breathe(held, grips, prop2, phase):
    """The held pose at phase (0-1) of a breath."""
    inhale = 0.5 - 0.5 * np.cos(2 * np.pi * phase)   # 0 at rest, 1 at the top of the breath
    pose = held.copy()
    feet = {side: held.world[f"Bip01_{side}_Foot"].copy() for side in "RL"}
    sword = held.world["Bip01_Prop1"].copy()
    drop = -SINK * (1 - inhale)

    root = pose.world["Bip01"].copy()
    root[3, 1] += drop
    pose.set_world("Bip01", root)
    for side in "RL":
        solve_leg(pose, side, feet[side])

    # Chest up and back, head held level, shoulders lifted.
    chest = np.radians(CHEST_DEGREES * inhale)
    pose.rotate_world("Bip01_Spine1", _rodrigues(np.array([1.0, 0, 0]), chest))
    pose.rotate_world("Bip01_Head", _rodrigues(np.array([1.0, 0, 0]), -chest))
    for side, sign in (("L", 1), ("R", -1)):
        pose.rotate_world(f"Bip01_{side}_Clavicle",
                          _rodrigues(np.array([0, 0, 1.0]), np.radians(sign * SHOULDER_DEGREES * inhale)))

    sword[3, 1] += drop + SWORD_LIFT * inhale
    pose.set_world("Bip01_Prop1", sword)
    for side in "RL":
        solve_arm(pose, side, grips[side] @ sword)
    pose.set_world("Bip01_Prop2", prop2 @ pose.world["Bip01_L_Hand"])
    return pose


def parry_frame(held, grips, prop2, t):
    """PSF_BlockParry at t seconds: the held block, breathing, driven back by a strike and recovering."""
    pose = breathe(held, grips, prop2, t / BREATH_SECONDS % 1)
    if t <= 0 or t >= PARRY_RECOVER:
        return pose
    # Snaps back at the hit, eases out again.
    if t < PARRY_IMPACT:
        hit = (t / PARRY_IMPACT) ** 2
    else:
        u = (t - PARRY_IMPACT) / (PARRY_RECOVER - PARRY_IMPACT)
        hit = 1 - u * u * (3 - 2 * u)
    feet = {side: pose.world[f"Bip01_{side}_Foot"].copy() for side in "RL"}
    sword = pose.world["Bip01_Prop1"].copy()
    root = pose.world["Bip01"].copy()
    root[3, 1] -= PARRY_SINK * hit
    pose.set_world("Bip01", root)
    # The legs hang from the spine, so put the feet back after rocking it.
    pose.rotate_world("Bip01_Spine", _rodrigues(np.array([1.0, 0, 0]), np.radians(-PARRY_ROCK * hit)))
    for side in "RL":
        solve_leg(pose, side, feet[side])
    # The blade is knocked over about the grip, its tip out toward the off side (+X).
    knock = _rodrigues(np.array([0, 0, 1.0]), np.radians(PARRY_KNOCK * hit))
    sword[:3, :3] = sword[:3, :3] @ knock.T
    sword[3, :3] += PARRY_RECOIL * hit + np.array([0, -PARRY_SINK * hit, 0])
    pose.set_world("Bip01_Prop1", sword)
    for side in "RL":
        solve_arm(pose, side, grips[side] @ sword)
    pose.set_world("Bip01_Prop2", prop2 @ pose.world["Bip01_L_Hand"])
    return pose


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()

    clip = xfile.XFile(args.pz / BASE)
    held, grips, prop2 = build(clip)
    frames = []
    for i in range(BREATH_KEYS + 1):
        phase = (i % BREATH_KEYS) / BREATH_KEYS
        frames.append((round(i / BREATH_KEYS * BREATH_SECONDS * clip.ticks), breathe(held, grips, prop2, phase)))
    # How far the feet slide and the hands slip off the hilt over the loop (should be ~0).
    slide = max(np.linalg.norm(p.position(f"Bip01_{s}_Foot") - held.position(f"Bip01_{s}_Foot"))
                for _, p in frames for s in "RL")
    slip = max(np.linalg.norm((p.world[f"Bip01_{s}_Hand"] @ np.linalg.inv(p.world["Bip01_Prop1"]))[3, :3]
                              - grips[s][3, :3]) for _, p in frames for s in "RL")
    print(f"{len(frames)} keys over {BREATH_SECONDS}s; feet slide {slide:.2g}, hands slip {slip:.2g}")
    write(clip, frames, args.out, NAME)

    parry = [(round(i / PARRY_KEYS * PARRY_SECONDS * clip.ticks),
              parry_frame(held, grips, prop2, i / PARRY_KEYS * PARRY_SECONDS)) for i in range(PARRY_KEYS + 1)]
    slide = max(np.linalg.norm(p.position(f"Bip01_{s}_Foot") - held.position(f"Bip01_{s}_Foot"))
                for _, p in parry for s in "RL")
    slip = max(np.linalg.norm((p.world[f"Bip01_{s}_Hand"] @ np.linalg.inv(p.world["Bip01_Prop1"]))[3, :3]
                              - grips[s][3, :3]) for _, p in parry for s in "RL")
    joins = max(np.abs(parry[-1][1].world[n] - breathe(held, grips, prop2, PARRY_SECONDS / BREATH_SECONDS % 1).world[n]).max()
                for n in held.world)
    gap = min(head_gap(clip, p) for _, p in parry)
    print(f"{PARRY_NAME}: {len(parry)} keys over {PARRY_SECONDS}s; feet slide {slide:.2g}, hands slip {slip:.2g}, "
          f"rejoins the block within {joins:.2g}; blade clears the head by {gap:.3f} (held: {head_gap(clip, held):.3f})")
    write(clip, parry, args.out.with_name(f"{PARRY_NAME}.x"), PARRY_NAME)


if __name__ == "__main__":
    main()
