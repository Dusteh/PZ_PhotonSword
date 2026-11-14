#!/usr/bin/env python3
"""Author the photon sword's resting stances and walks as Project Zomboid animations.

Rests (looped, held still): PS_Rest (standing) and PS_RestSneak (sneaking) each start from a
vanilla one-handed idle (Bob_IdleNoAim1Hand, Bob_IdleSneak; frame 0): the sword hand holds the
hilt at the right side and the off hand hangs relaxed at the left. The hilt tilts a little in the
sword hand, held halfway along it, and the wrist turns the blade from vanilla's level point to
angle a little down, forward and out, and the hand comes a little forward so the blade
clears the leg. The held pose breathes as a held pose does (animlib.py): the chest rises, the
shoulders lift, and the body sinks and rises a little on planted feet; the sword stays put in the
hand while the off arm rides with the chest.

Walks (PS_Walk*, PS_WalkSneak*): vanilla's one-handed walks (Bob_Walk*, Bob_WalkSneak*), whose
arms swing freely, with the sword wrist turned on every frame so the blade keeps the rest's low
angle, following WALK_SWING of the arm's swing, and the same grip on the hilt.

Turning in place plays vanilla's turn on the legs, pelvis, and lower spine under the rest (the
turn's bone weights), so the script checks how far the hilt (a child of Bip01, not the hand)
drifts from the hand over each turn.

The weapon's blade runs along Prop1's +Y axis.

Usage: make_rest.py [--pz PATH_TO_projectzomboid]   (writes common/media/anims_X/PS/PS_Rest*.x, PS_Walk*.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import (DEFAULT_PZ, BREATH_SECONDS, BREATH_KEYS, CHEST_DEGREES, SHOULDER_DEGREES, SINK,
                        Pose, _rodrigues, rotation_between, solve_leg, solve_limb, write)

OUT = Path(__file__).resolve().parents[2] / "PhotonSword/Contents/mods/PhotonSword/common/media/anims_X/PS"
ANIMS = "media/anims_X/Bob"
GRIP_BASE = "Bob_IdleNoAim1Hand"   # the one-handed grip every clip holds the hilt with
BLADE_LENGTH = 0.5                 # for the floor and leg checks (model units)

# The pose, in the model's space: +X is the character's left, +Y up, -Z forward.
# Degrees the hilt turns in the fist, tip toward the fingers, off the line of vanilla's fist. A tilt
# takes up part of the blade's angle so the wrist needn't bend it all (see wrist bend), but the hilt
# then leaves the fist's channel: past about 10 it pokes out under the wrist in game.
GRIP_TILT = 0
# Where along the hilt (+Y, from the model's origin) the middle of the fist closes: halfway along the
# hilt, which runs from -0.065 (pommel) to 0.122 (emitter) in PhotonSword_Hilt.x. Vanilla's grip puts
# the fist's middle about 0.045 up, against the emitter.
GRIP_AT = 0.028
ELBOW_POLE = np.array([-0.3, 0.0, 1.0])       # sword elbow back and a little out
# Per rest: the vanilla idle it starts from; the blade's angle below level (down) and out to the
# sword side from forward (out), in degrees; the sword hand's move from vanilla (out, up, forward);
# and vanilla's turns in place that play under it.
RESTS = {
    "PS_Rest": dict(base="Bob_IdleNoAim1Hand", down=15, out=15, shift=[-0.02, 0.02, -0.04],
                     turns=["Bob_IdleTurn90R", "Bob_IdleTurn90L"]),
    "PS_RestSneak": dict(base="Bob_IdleSneak", down=10, out=15, shift=[-0.02, 0.02, -0.04],
                          turns=["Bob_IdleSneak_Turn90R", "Bob_IdleSneak_Turn90L"]),
}
# Per walk: the vanilla one-handed walk it's made from, and the rest whose blade angle it keeps.
WALKS = {
    "PS_Walk": ("Bob_Walk", "PS_Rest"),
    "PS_WalkSlow": ("Bob_WalkSlow", "PS_Rest"),
    "PS_WalkLightLimpR": ("Bob_WalkLightLimpR", "PS_Rest"),
    "PS_WalkLightLimpL": ("Bob_WalkLightLimpL", "PS_Rest"),
    "PS_WalkHeavyLimpR": ("Bob_WalkHeavyLimpR", "PS_Rest"),
    "PS_WalkHeavyLimpL": ("Bob_WalkHeavyLimpL", "PS_Rest"),
    "PS_WalkSneak": ("Bob_WalkSneak", "PS_RestSneak"),
    "PS_WalkSneak_Slow": ("Bob_WalkSneak_Slow", "PS_RestSneak"),
}
WALK_SWING = 0.0   # how much of the forearm's swing the blade follows while walking (0-1)
# The bones vanilla's turn in place (turn.xml) takes over; the rest plays on the others.
TURN_BONES = {"Bip01": False, "Translation_Data": False, "Bip01_Pelvis": False, "Bip01_Spine": False,
              "Bip01_L_Thigh": True, "Bip01_R_Thigh": True, "Bip01_BackPack": True,
              "Bip01_DressFront": True, "Bip01_DressBack": True}


def grip_of(clip):
    """The weapon in the sword hand (its world matrix relative to the hand's): vanilla's grip, tilted
    by GRIP_TILT and slid along the hilt so the fist's middle is at GRIP_AT."""
    pose = Pose(clip)
    hand, prop = pose.world["Bip01_R_Hand"], pose.world["Bip01_Prop1"].copy()
    axis = np.cross(prop[1, :3], pose.position("Bip01_R_Finger1") - pose.position("Bip01_R_Hand"))
    prop[:3, :3] = prop[:3, :3] @ _rodrigues(axis / np.linalg.norm(axis), np.radians(GRIP_TILT)).T
    prop[3, :3] += prop[1, :3] * (fist_middle(clip, pose.world, prop) - GRIP_AT)
    return prop @ np.linalg.inv(hand)


def fist_middle(clip, world, prop):
    """How far along prop's +Y the sword hand's skin (the vertices the hand and fingers carry) is centered."""
    hand = set()
    for bone, indices, weights, _ in clip.skins:
        if bone in ("Bip01_R_Hand", "Bip01_R_Finger0", "Bip01_R_Finger1"):
            hand.update(indices[weights > 0.5])
    verts = clip.skinned(world)[sorted(hand)]
    return float(np.mean((verts - prop[3, :3]) @ prop[1, :3]))


def pose_at(clip, tick):
    pose = Pose(clip)
    pose.local = clip.local_matrices(tick)
    pose.update()
    return pose


def aim_hand(pose, grip, blade):
    """Turns the sword hand at the wrist so the blade points along blade; the hilt follows."""
    hand = pose.world["Bip01_R_Hand"].copy()
    hand[:3, :3] = hand[:3, :3] @ rotation_between((grip @ hand)[1, :3], blade).T
    pose.set_world("Bip01_R_Hand", hand)
    pose.set_world("Bip01_Prop1", grip @ pose.world["Bip01_R_Hand"])


def build(clip, grip, rest):
    """The resting pose: the base idle with the sword hand turned to point the blade."""
    pose = Pose(clip)
    hand = pose.world["Bip01_R_Hand"].copy()
    down, out = np.radians(rest["down"]), np.radians(rest["out"])
    blade = np.array([-np.sin(out) * np.cos(down), -np.sin(down), -np.cos(out) * np.cos(down)])
    hand[:3, :3] = hand[:3, :3] @ rotation_between((grip @ hand)[1, :3], blade).T
    hand[3, :3] += rest["shift"]
    solve_arm(pose, hand)
    pose.set_world("Bip01_Prop1", grip @ pose.world["Bip01_R_Hand"])
    return pose


def solve_arm(pose, hand_world):
    solve_limb(pose, "Bip01_R_UpperArm", "Bip01_R_Forearm", "Bip01_R_Hand", hand_world, ELBOW_POLE)


def breathe(held, grip, phase):
    """The resting pose at phase (0-1) of a breath."""
    inhale = 0.5 - 0.5 * np.cos(2 * np.pi * phase)   # 0 at rest, 1 at the top of the breath
    pose = held.copy()
    feet = {side: held.world[f"Bip01_{side}_Foot"].copy() for side in "RL"}
    hand = held.world["Bip01_R_Hand"].copy()
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

    # The sword hand settles with the body; the off arm just rides on its shoulder.
    hand[3, 1] += drop
    solve_arm(pose, hand)
    pose.set_world("Bip01_Prop1", grip @ pose.world["Bip01_R_Hand"])
    return pose


def forearm(pose):
    direction = pose.position("Bip01_R_Hand") - pose.position("Bip01_R_Forearm")
    return direction / np.linalg.norm(direction)


def carry(walk, rest, grip):
    """The walk's keyframes with the sword wrist turned to hold the rest's blade angle."""
    rest_blade, rest_forearm = rest.world["Bip01_Prop1"][1, :3], forearm(rest)
    ticks = sorted({t for keys in walk.keys.values() for kind in keys.values() for t, _ in kind})
    frames = []
    for tick in ticks:
        pose = pose_at(walk, tick)
        # The blade follows part of the arm's swing: a slerp of the swing's rotation.
        swing = rotation_between(rest_forearm, forearm(pose))
        angle = np.arccos(np.clip((np.trace(swing) - 1) / 2, -1, 1))
        axis = np.cross(rest_forearm, forearm(pose))
        if np.linalg.norm(axis) > 1e-9:
            swing = _rodrigues(axis / np.linalg.norm(axis), angle * WALK_SWING)
        aim_hand(pose, grip, swing @ rest_blade)
        frames.append((tick, pose))
    return frames


def wrist_bend(pose):
    """Degrees between the sword forearm and its hand (toward the fingers)."""
    fingers = pose.position("Bip01_R_Finger1") - pose.position("Bip01_R_Hand")
    return np.degrees(np.arccos(np.clip(np.dot(forearm(pose), fingers) / np.linalg.norm(fingers), -1, 1)))


def _segment_distance(p1, q1, p2, q2, samples=24):
    """Closest approach of two segments (sampled; plenty for a clearance check)."""
    a = p1 + np.linspace(0, 1, samples)[:, None] * (q1 - p1)
    b = p2 + np.linspace(0, 1, samples)[:, None] * (q2 - p2)
    return np.min(np.linalg.norm(a[:, None] - b[None], axis=2))


def blade_checks(frames):
    """Lowest blade tip (above the floor), closest blade-to-sword-leg distance, and wrist bend range."""
    tips, legs, bends = [], [], []
    for _, pose in frames:
        prop = pose.world["Bip01_Prop1"]
        start, tip = prop[3, :3], prop[3, :3] + prop[1, :3] * BLADE_LENGTH
        tips.append(tip[1])
        legs.append(min(_segment_distance(start, tip, pose.position(a), pose.position(b))
                        for a, b in (("Bip01_R_Thigh", "Bip01_R_Calf"), ("Bip01_R_Calf", "Bip01_R_Foot"))))
        bends.append(wrist_bend(pose))
    return (f"blade tip {min(tips):.2f} above the floor, {min(legs):.3f} from the sword leg's bones; "
            f"wrist bend {min(bends):.0f}-{max(bends):.0f} degrees")


def turn_drift(rest, grip, turn):
    """Worst distance and angle between the hilt and the sword hand's grip, the rest over turn."""
    def subtree(name):
        return [name] + [b for b, bone in turn.bones.items() if bone.parent and bone.parent.name == name
                         for b in subtree(b)]
    turned = {b for name, descendants in TURN_BONES.items() if name in turn.bones
              for b in (subtree(name) if descendants else [name])}
    worst = (0.0, 0.0)
    ticks = sorted({t for keys in turn.keys.values() for kind in keys.values() for t, _ in kind})
    for tick in ticks:
        local = turn.local_matrices(tick)
        local.update({b: m for b, m in rest.local.items() if b not in turned})
        world = turn.world_matrices(local)
        held = grip @ world["Bip01_R_Hand"]
        gap = np.linalg.norm(world["Bip01_Prop1"][3, :3] - held[3, :3])
        cos = np.dot(world["Bip01_Prop1"][1, :3], held[1, :3])
        worst = max(worst[0], gap), max(worst[1], np.degrees(np.arccos(np.clip(cos, -1, 1))))
    return worst


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT, help="folder to write the clips to")
    args = parser.parse_args()

    def load(name):
        return xfile.XFile(args.pz / ANIMS / f"{name}.x")

    grip = grip_of(load(GRIP_BASE))
    held = {}
    for name, rest in RESTS.items():
        clip = load(rest["base"])
        held[name] = build(clip, grip, rest)
        frames = []
        for i in range(BREATH_KEYS + 1):
            phase = (i % BREATH_KEYS) / BREATH_KEYS
            frames.append((round(i / BREATH_KEYS * BREATH_SECONDS * clip.ticks), breathe(held[name], grip, phase)))
        slide = max(np.linalg.norm(p.position(f"Bip01_{s}_Foot") - held[name].position(f"Bip01_{s}_Foot"))
                    for _, p in frames for s in "RL")
        print(f"{name}: {len(frames)} keys over {BREATH_SECONDS}s; feet slide {slide:.2g}; {blade_checks(frames)}")
        for turn in rest["turns"]:
            gap, angle = turn_drift(held[name], grip, load(turn))
            print(f"  turning ({turn}): hilt drifts up to {gap:.3f} and {angle:.0f} degrees from the hand")
        write(clip, frames, args.out / f"{name}.x", name)

    for name, (base, rest) in WALKS.items():
        walk = load(base)
        frames = carry(walk, held[rest], grip)
        print(f"{name}: {len(frames)} keys from {base}; {blade_checks(frames)}")
        write(walk, frames, args.out / f"{name}.x", name)


if __name__ == "__main__":
    main()
