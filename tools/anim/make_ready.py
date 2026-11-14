#!/usr/bin/env python3
"""Author PS_Ready, the photon sword's aiming stance, as a looped Project Zomboid animation.

A two-handed ready guard after Obi-Wan Kenobi's: starts from vanilla's two-handed aim
(Bob_IdleAimBat, frame 0), whose feet are already set for a fight, left foot forward, then widens
the stance and settles the body onto bent knees, the shoulders square to the front (TORSO_TURN can
turn them side-on). Both fists hold the hilt low, the pommel a few inches
in front of the sword hip: the sword (back) hand at the bottom toward the pommel, its elbow out to
the side, and the off (fore) hand above it toward the emitter, its forearm across the stomach. The
arms are untwisted: the elbows bend only on their hinge, as vanilla's do (solve_arm), and each fist
is turned about the hilt so the wrist keeps close to its resting twist (wrist). Both arms clear the
body. The blade points straight ahead, its tip toward the cursor (the way the character faces while
aiming), rising 45 degrees. The sword hand grips the hilt as the rests do
(make_rest.py: vanilla's one-handed fist); the off hand's grip is its mirror image across the hilt,
turned by OFF_ROLL. The pose breathes as a held pose does (animlib.py): the chest rises, the
shoulders lift, and the body sinks and rises a little on planted feet; the sword rides with it in
both hands.

In the model's space +X is the character's left, +Y up, -Z forward. A hand bone's +X runs along its
fingers and its +Z is its palm's normal. The weapon's blade runs along Prop1's +Y axis.

Also writes PS_ReadyBeckon, played now and then in place of the loop: the off hand lets go of the
hilt, lifts ahead palm up, beckons twice, and returns to the hilt.

And PS_ReadyWalk, the stance played while walking in it: the game plays the stance's spine and
everything above it over vanilla's two-handed aiming walk (WALK_LEGS), whose pelvis tips forward,
so the upper body is leaned back by WALK_LEAN of its lean over those legs.

Usage: make_ready.py [--pz PATH_TO_projectzomboid]
       (writes common/media/anims_X/PS/PS_Ready.x, PS_ReadyBeckon.x, and PS_ReadyWalk.x)
"""

import argparse
from pathlib import Path

import numpy as np

import xfile
from animlib import (DEFAULT_PZ, BREATH_KEYS, BREATH_SECONDS, CHEST_DEGREES, SHOULDER_DEGREES, SINK, Pose,
                        _rodrigues, rotation_between, solve_leg, write)
from make_guard import elbow, hand_frame
from make_rest import ANIMS, GRIP_AT, GRIP_BASE, OUT, grip_of

NAME = "PS_Ready"
BASE = "Bob_IdleAimBat"
REST = "Bob_Idle"   # whose hands rest on the forearms as a relaxed wrist does, for the wrist measure

# The stance: how far the body sinks onto bent knees, and how much wider the feet are set (their
# spread about their midpoint, on the ground).
CROUCH = 0.04
WIDEN = 1.25
TORSO_TURN = 0   # degrees the shoulders turn about Y, off shoulder forward (the head turns back to face ahead)

# The sword: the middle of the sword fist relative to the head bone (out, up, forward; the shoulders
# are about 0.03 below the head bone and the hips about 0.31), the blade's direction, where the sword palm faces, and each
# elbow's pole. The fists sit next to each other on the short hilt (PhotonSword_Hilt.x runs from
# -0.065 at the pommel to 0.122 at the emitter): the sword fist's middle at SWORD_AT along the hilt,
# the off fist's SPACING from it. (With the hands the other way round, the off hand at the bottom, the
# sword elbow can't be drawn back: the off hand, below and behind it, would sit inside the belly.)
# These, OFF_ROLL, GRIP_TILT and TORSO_TURN were chosen together (an optimizer over them) to keep both
# wrists near their resting twist with the fingers in line with the forearm, the elbows not folded
# past about 100 degrees, the arms clear of the torso, the blade straight ahead (toward the cursor) and
# no steeper than 45 degrees, and the pommel 2 to 4 inches (0.03 to 0.055) from the sword hip's skin.
# The off wrist is the hardest: about 30 degrees of twist and swing, as far as vanilla's idles go.
FIST = np.array([-0.063, -0.241, 0.025])      # low, just ahead of the sword hip
BLADE = np.array([0.0, 1.0, -1.0])            # straight ahead, toward the cursor, rising 45 degrees
SWORD_PALM = np.array([0.92, 0.264, 0.291])   # in, toward the body
SWORD_ELBOW = np.array([-0.083, 0.073, 0.994])  # back
OFF_ELBOW = np.array([0.122, -0.985, -0.123])  # down
SWORD_AT = -0.02    # the sword (back) hand at the bottom, toward the pommel
SPACING = 0.085     # the off (fore) hand above it, toward the emitter
OFF_ROLL = 137      # degrees the off fist is turned about the hilt from the sword fist's mirror image
GRIP_TILT = -8      # degrees the hilt lies diagonally across both palms (make_rest.py: past about 10 it pokes out)

# The walking stance (PS_ReadyWalk, over WALK_LEGS in the aim-strafe state): the upper body's forward
# lean over the walking legs (pelvis to neck, from upright) is cut by WALK_LEAN.
WALK_NAME = "PS_ReadyWalk"
WALK_LEGS = "Bob_WalkAimBat"
WALK_LEAN = 0.25

# The beckon (PS_ReadyBeckon, played now and then in place of the ready loop; PS_Stance.lua picks when):
# the off hand lets go of the hilt and lifts ahead of its shoulder along BECKON_REACH, at
# BECKON_FRACTION of the arm's reach, palm up, over BECKON_LIFT seconds; its fingers curl in toward
# the palm and open (BECKON_CURL of a fist) once from each of BECKON_CURLS, over BECKON_CURL_SECONDS;
# from BECKON_RETURN it goes back to the hilt, and the clip ends in the ready pose.
BECKON_NAME = "PS_ReadyBeckon"
BECKON_SECONDS = 2.4
BECKON_LIFT = 0.45
BECKON_RETURN = 1.7
BECKON_CURLS = (0.55, 1.1)
BECKON_CURL_SECONDS = 0.5
BECKON_CURL = 0.9
BECKON_REACH = np.array([0.15, -0.1, -1.0])   # ahead, a little out to the off side and down
BECKON_FRACTION = 0.85
# Palm mostly up, a little in, with the elbow tucked in: turned up that way the wrist keeps its
# resting twist (palm straight up, it twists over 90 degrees).
BECKON_PALM = np.array([-0.5, 0.866, 0.0])
BECKON_ELBOW = np.array([-0.94, -0.6, -0.34])  # in toward the body, down and forward
BECKON_ARC = 0.06   # how far ahead of the straight path the hand swings on its way out and back
BECKON_SWING_OUT = 1.0   # how far the elbow's pole swings out to the off side on the way

ARM_RADIUS = 0.035   # about how thick the arm's skin is around its bones, for the torso clearance

# A left bone's frame is its right twin's mirrored across the body (X), with its Y axis reversed.
MIRROR_Y = np.diag([1.0, -1.0, 1.0])
FINGERS = ("Finger0", "Finger1")


def grips(base):
    """Each hand's world matrix relative to the weapon's (hand = grips[side] @ weapon)."""
    sword = np.linalg.inv(grip_of(base))
    # grip_of seats the fist's middle at GRIP_AT; slide the hand down the hilt to SWORD_AT.
    sword[3, :3] += np.array([0, SWORD_AT - GRIP_AT, 0])
    # Tilt the hilt in the fist about the palm's normal (diagonally across the palm), about the fist's middle.
    turn = _rodrigues(sword[2, :3], np.radians(GRIP_TILT)).T
    middle = np.array([0, SWORD_AT, 0])
    sword[:3, :3] = sword[:3, :3] @ turn
    sword[3, :3] = middle + (sword[3, :3] - middle) @ turn
    # The off hand: the sword hand mirrored across the plane through the hilt that its palm faces, so
    # it wraps the hilt from the other side, then slid ahead along the hilt.
    palm = sword[2, :3] - sword[2, 1] * np.array([0, 1.0, 0])
    palm /= np.linalg.norm(palm)
    flip = np.eye(3) - 2 * np.outer(palm, palm)
    off = np.eye(4)
    off[:3, :3] = MIRROR_Y @ sword[:3, :3] @ flip
    off[3, :3] = sword[3, :3] @ flip + np.array([0, SPACING, 0])
    # The off fist can wrap the hilt at any turn about it.
    roll = _rodrigues(np.array([0, 1.0, 0]), np.radians(OFF_ROLL)).T
    off[:3, :3] = off[:3, :3] @ roll
    off[3, :3] = off[3, :3] @ roll
    return {"R": sword, "L": off}


def curl_fingers(pose, base):
    """Both hands' fingers closed as the sword hand's are in the one-handed fist."""
    fist = Pose(base)
    for finger in FINGERS:
        right = fist.local[f"Bip01_R_{finger}"][:3, :3]
        pose.local[f"Bip01_R_{finger}"][:3, :3] = right
        pose.local[f"Bip01_L_{finger}"][:3, :3] = MIRROR_Y @ right @ MIRROR_Y
    pose.update()


def sword_target(pose, hands):
    """The weapon bone's world matrix: blade along BLADE, the sword palm turned toward SWORD_PALM."""
    blade = BLADE / np.linalg.norm(BLADE)
    prop = np.eye(4)
    prop[:3, :3] = rotation_between(np.array([0, 1.0, 0]), blade).T
    palm = (hands["R"] @ prop)[2, :3]
    want = SWORD_PALM - np.dot(SWORD_PALM, blade) * blade
    spin = rotation_between(palm - np.dot(palm, blade) * blade, want)
    prop[:3, :3] = prop[:3, :3] @ spin.T
    prop[3, :3] = pose.position("Bip01_Head") + FIST - blade * SWORD_AT
    return prop


def solve_arm(pose, side, hand_world, pole):
    """Two-bone IK that bends the elbow as vanilla's does, purely about the upper arm's local Y, with
    the upper arm rolled so that hinge faces the wrist: no twist at the elbow. The hand then takes
    hand_world's rotation (the wrist)."""
    upper, fore, hand = (f"Bip01_{side}_{b}" for b in ("UpperArm", "Forearm", "Hand"))
    shoulder, target = pose.position(upper), hand_world[3, :3]
    a, b = pose.local[fore][3, 0], pose.local[hand][3, 0]   # the bones run along their parents' X
    d = min(np.linalg.norm(target - shoulder), a + b - 1e-4)
    reach = (target - shoulder) / np.linalg.norm(target - shoulder)
    along = (a * a - b * b + d * d) / (2 * d)
    out = pole - np.dot(pole, reach) * reach
    out /= np.linalg.norm(out)
    elbow_ = shoulder + reach * along + out * np.sqrt(max(a * a - along * along, 0))
    x = (elbow_ - shoulder) / a
    forearm = shoulder + reach * d - elbow_
    forearm /= np.linalg.norm(forearm)
    # Bending by +angle about local Y swings the forearm toward the upper arm's -Z.
    z = -(forearm - np.dot(forearm, x) * x)
    z = z / np.linalg.norm(z) if np.linalg.norm(z) > 1e-6 else -out + np.dot(out, x) * x
    world = np.eye(4)
    world[0, :3], world[1, :3], world[2, :3], world[3, :3] = x, np.cross(z, x), z, shoulder
    pose.set_world(upper, world)
    angle = np.arccos(np.clip(np.dot(x, forearm), -1, 1))
    pose.local[fore][:3, :3] = _rodrigues(np.array([0, 1.0, 0]), angle).T
    pose.update()
    world = pose.world[hand].copy()
    world[:3, :3] = hand_world[:3, :3]
    pose.set_world(hand, world)


def hold(pose, hands, sword):
    solve_arm(pose, "R", hands["R"] @ sword, SWORD_ELBOW)
    solve_arm(pose, "L", hands["L"] @ sword, OFF_ELBOW)
    pose.set_world("Bip01_Prop1", sword)


def wrist(pose, rest, side):
    """How far the hand is turned from its resting set on the forearm (rest: a Pose of vanilla's
    idle): (twist about the forearm, swing of the fingers), in degrees. Without twist bones, a
    twisted wrist wrings the forearm's skin."""
    hand = pose.local[f"Bip01_{side}_Hand"][:3, :3]
    neutral = rest.local[f"Bip01_{side}_Hand"][:3, :3]
    swing = np.degrees(np.arccos(np.clip(np.dot(hand[0], neutral[0]), -1, 1)))
    flat = [v - np.dot(v, [1.0, 0, 0]) * np.array([1.0, 0, 0]) for v in (hand[2], neutral[2])]
    twist = np.degrees(np.arctan2(np.dot(np.cross(flat[1], flat[0]), [1.0, 0, 0]), np.dot(flat[0], flat[1])))
    return twist, swing


def build(clip, base, hands):
    pose = Pose(clip)
    curl_fingers(pose, base)
    # Widen the stance on the ground and sink the body onto the knees.
    feet = {side: pose.world[f"Bip01_{side}_Foot"].copy() for side in "RL"}
    middle = (feet["R"][3, :3] + feet["L"][3, :3]) / 2
    for foot in feet.values():
        foot[3, [0, 2]] = middle[[0, 2]] + (foot[3, [0, 2]] - middle[[0, 2]]) * WIDEN
    root = pose.world["Bip01"].copy()
    root[3, 1] -= CROUCH
    pose.set_world("Bip01", root)
    for side in "RL":
        solve_leg(pose, side, feet[side])
    for bone in ("Bip01_Spine", "Bip01_Spine1"):
        pose.rotate_world(bone, _rodrigues(np.array([0, 1.0, 0]), np.radians(TORSO_TURN / 2)))
    pose.rotate_world("Bip01_Neck", _rodrigues(np.array([0, 1.0, 0]), np.radians(-TORSO_TURN)))
    hold(pose, hands, sword_target(pose, hands))
    return pose


def frame(held, hands, phase):
    """The ready stance at phase (0-1) of a breath."""
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

    chest = np.radians(CHEST_DEGREES * inhale)
    pose.rotate_world("Bip01_Spine1", _rodrigues(np.array([1.0, 0, 0]), chest))
    pose.rotate_world("Bip01_Head", _rodrigues(np.array([1.0, 0, 0]), -chest))
    for side, sign in (("L", 1), ("R", -1)):
        pose.rotate_world(f"Bip01_{side}_Clavicle",
                          _rodrigues(np.array([0, 0, 1.0]), np.radians(sign * SHOULDER_DEGREES * inhale)))

    sword[3, 1] += drop
    hold(pose, hands, sword)
    return pose


def walking_lean(pose, legs):
    """Mean forward lean (degrees, pelvis to neck) of pose's spine and above played over legs' clip."""
    upper = ["Bip01_Spine"]
    for name in upper:
        upper += [child.name for child in pose.x.bones[name].children]
    leans = []
    for tick in sorted({t for keys in legs.keys.values() for kind in keys.values() for t, _ in kind}):
        local = legs.local_matrices(tick)
        local.update({name: pose.local[name] for name in upper if name in local})
        world = legs.world_matrices(local)
        up = world["Bip01_Neck"][3, :3] - world["Bip01_Pelvis"][3, :3]
        leans.append(np.degrees(np.arctan2(-up[2], up[1])))
    return float(np.mean(leans))


def lean_back(held, hands, degrees):
    """held with the spine (and the sword in both hands) leaned back by degrees about the spine's base."""
    pose = held.copy()
    q = _rodrigues(np.array([1.0, 0, 0]), np.radians(degrees))
    pivot = pose.position("Bip01_Spine")
    sword = pose.world["Bip01_Prop1"].copy()
    sword[:3, :3] = sword[:3, :3] @ q.T
    sword[3, :3] = pivot + (sword[3, :3] - pivot) @ q.T
    pose.rotate_world("Bip01_Spine", q)
    hold(pose, hands, sword)
    return pose


def walking(held, hands, legs):
    """held leaned back until its lean over legs is (1 - WALK_LEAN) of what it was; and the two leans."""
    before = walking_lean(held, legs)
    target = before * (1 - WALK_LEAN)
    low, high = 0.0, 30.0
    for _ in range(30):
        mid = (low + high) / 2
        low, high = (mid, high) if walking_lean(lean_back(held, hands, mid), legs) > target else (low, mid)
    pose = lean_back(held, hands, (low + high) / 2)
    return pose, before, walking_lean(pose, legs)


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def slerp(a, b, t):
    """Rotation (3x3, row-vector form) t of the way from a to b."""
    qa, qb = xfile.matrix_quat(a), xfile.matrix_quat(b)
    if np.dot(qa, qb) < 0:
        qb = -qb
    angle = np.arccos(np.clip(np.dot(qa, qb), -1, 1))
    q = qa if angle < 1e-6 else (np.sin((1 - t) * angle) * qa + np.sin(t * angle) * qb) / np.sin(angle)
    return xfile.quat_matrix(q / np.linalg.norm(q))


def beckon_target(held):
    """Where the off hand beckons from: ahead of its shoulder, palm up, fingers toward the target."""
    shoulder = held.position("Bip01_L_UpperArm")
    reach = sum(held.local[f"Bip01_L_{b}"][3, 0] for b in ("Forearm", "Hand"))
    direction = BECKON_REACH / np.linalg.norm(BECKON_REACH)
    return hand_frame(direction, BECKON_PALM, shoulder + direction * reach * BECKON_FRACTION)


def beckon_frame(held, hands, fingers, t):
    """The beckon at t seconds: the ready stance breathing on, the off hand lifted off the hilt to
    beckon. fingers: the off hand's finger rotations (open, closed in the fist)."""
    pose = frame(held, hands, t / BREATH_SECONDS % 1)
    lift = smooth(t / BECKON_LIFT) * (1 - smooth((t - BECKON_RETURN) / BECKON_LIFT))
    grip, out = pose.world["Bip01_L_Hand"].copy(), beckon_target(pose)
    target = np.eye(4)
    target[:3, :3] = slerp(grip[:3, :3], out[:3, :3], lift)
    target[3, :3] = grip[3, :3] + (out[3, :3] - grip[3, :3]) * lift + np.array([0, 0, -BECKON_ARC]) * np.sin(np.pi * lift)
    # The elbow swings out to the off side on the way, so the forearm passes clear of the stomach.
    pole = OFF_ELBOW + (BECKON_ELBOW - OFF_ELBOW) * lift + np.array([BECKON_SWING_OUT, 0, 0]) * np.sin(np.pi * lift)
    solve_arm(pose, "L", target, pole)
    # The fist opens as the hand lifts and closes as it returns; between, the fingers curl in and open.
    curl = BECKON_CURL * sum(np.sin(np.pi * smooth((t - start) / BECKON_CURL_SECONDS)) ** 2
                             for start in BECKON_CURLS)
    for finger in FINGERS:
        open_, fist = fingers[finger]
        closed = 1 - lift + lift * (curl if finger == "Finger1" else 0)
        pose.local[f"Bip01_L_{finger}"][:3, :3] = slerp(open_, fist, closed)
    pose.update()
    return pose


def arm_clearance(clip, pose, side):
    """The closest an arm (the outer half of the upper arm and the forearm, as bone lines) comes to the
    torso's skin, less ARM_RADIUS (negative: the elbow or forearm passes into the body)."""
    torso = sorted({i for bone, indices, weights, _ in clip.skins
                    if bone in ("Bip01_Pelvis", "Bip01_Spine", "Bip01_Spine1") for i in indices[weights > 0.5]})
    verts = clip.skinned(pose.world)[torso]
    shoulder, elbow_, wrist = (pose.position(f"Bip01_{side}_{b}") for b in ("UpperArm", "Forearm", "Hand"))
    closest = np.inf
    for a, b in (((shoulder + elbow_) / 2, elbow_), (elbow_, wrist)):
        t = np.clip((verts - a) @ (b - a) / np.dot(b - a, b - a), 0, 1)
        closest = min(closest, np.min(np.linalg.norm(verts - (a + t[:, None] * (b - a)), axis=1)))
    return closest - ARM_RADIUS


def slip(pose, hands):
    """How far the hands are off their grips on the hilt."""
    return max(np.linalg.norm((hands[s] @ pose.world["Bip01_Prop1"])[3, :3] - pose.position(f"Bip01_{s}_Hand"))
               for s in "RL")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pz", type=Path, default=DEFAULT_PZ, help="the game's projectzomboid folder")
    parser.add_argument("--out", type=Path, default=OUT / f"{NAME}.x")
    args = parser.parse_args()

    def load(name):
        return xfile.XFile(args.pz / ANIMS / f"{name}.x")

    base = load(GRIP_BASE)
    rest = Pose(load(REST))
    hands = grips(base)
    clip = load(BASE)
    held = build(clip, base, hands)
    frames = [(round(i / BREATH_KEYS * BREATH_SECONDS * clip.ticks), frame(held, hands, (i % BREATH_KEYS) / BREATH_KEYS))
              for i in range(BREATH_KEYS + 1)]
    slide = max(np.linalg.norm(p.position(f"Bip01_{s}_Foot") - held.position(f"Bip01_{s}_Foot"))
                for _, p in frames for s in "RL")
    print(f"{len(frames)} keys over {BREATH_SECONDS}s; feet slide {slide:.2g}, "
          f"hands slip {max(slip(p, hands) for _, p in frames):.2g}; arms clear the torso by "
          f"{min(arm_clearance(clip, p, 'R') for _, p in frames):.3f} (sword), "
          f"{min(arm_clearance(clip, p, 'L') for _, p in frames):.3f} (off); "
          + "; ".join("{} wrist twist {:.0f}, swing {:.0f}, elbow {:.0f}".format(name, *wrist(held, rest, s), elbow(held, s))
                      for name, s in (("sword", "R"), ("off", "L"))) + " degrees")
    write(clip, frames, args.out, NAME)

    upright, before, after = walking(held, hands, load(WALK_LEGS))
    walk = [(tick, frame(upright, hands, (i % BREATH_KEYS) / BREATH_KEYS)) for i, (tick, _) in enumerate(frames)]
    print(f"{WALK_NAME}: upper body leans {before:.1f} degrees over {WALK_LEGS}, now {after:.1f}; hands slip "
          f"{max(slip(p, hands) for _, p in walk):.2g}; arms clear the torso by "
          f"{min(arm_clearance(clip, p, 'R') for _, p in walk):.3f} (sword), "
          f"{min(arm_clearance(clip, p, 'L') for _, p in walk):.3f} (off)")
    write(clip, walk, args.out.with_name(f"{WALK_NAME}.x"), WALK_NAME)

    open_hand = Pose(load(REST))
    fingers = {f: (open_hand.local[f"Bip01_L_{f}"][:3, :3], held.local[f"Bip01_L_{f}"][:3, :3]) for f in FINGERS}
    keys = round(BECKON_SECONDS * 10)
    beckon = [(round(i / keys * BECKON_SECONDS * clip.ticks), beckon_frame(held, hands, fingers, i / keys * BECKON_SECONDS))
              for i in range(keys + 1)]
    top = beckon[round(keys * (BECKON_LIFT + 0.1) / BECKON_SECONDS)][1]
    print(f"{BECKON_NAME}: {len(beckon)} keys over {BECKON_SECONDS}s; off hand back on the hilt at the end "
          f"{slip(beckon[-1][1], hands):.2g}; off arm clears the torso by "
          f"{min(arm_clearance(clip, p, 'L') for _, p in beckon):.3f}; beckoning wrist twist {{:.0f}}, swing {{:.0f}}, "
          f"elbow {elbow(top, 'L'):.0f} degrees".format(*wrist(top, rest, "L")))
    write(clip, beckon, args.out.with_name(f"{BECKON_NAME}.x"), BECKON_NAME)


if __name__ == "__main__":
    main()
