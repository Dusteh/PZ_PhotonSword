#!/usr/bin/env python3
"""Generate the Photon Sword's stance AnimSets: how a character holds an ignited photon sword.

Every node plays this mod's own clips (common/media/anims_X/PS, authored by tools/anim/make_*.py from
vanilla's animations) and reads only this mod's animation variables (PSHolding, PSGuard, ...), which
client/PhotonSword/PS_Stance.lua sets. They override vanilla's two-handed idle, aim, and walks while
an ignited sword is held in both hands. Photon Sword Forms' attack and block nodes outrank them.

Usage: gen_animsets.py   (rewrites 42/media/AnimSets/player/*/PS_*.xml)
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "PhotonSword/Contents/mods/PhotonSword/42/media/AnimSets/player"

# Looped stances while aiming: the ready stance (PSGuard), PS_Ready (tools/anim/make_ready.py: a
# two-handed ready guard, the pommel by the sword hip and the blade pointing ahead toward the cursor),
# for both sexes. PS_Guard (tools/anim/make_guard.py, a one-handed high guard with the off hand
# beckoning) is the earlier stance, not played; set it as the guard's clip to switch back.
# And at rest (idle, not aiming), whenever the ignited sword is held (PSHolding): PS_Rest and
# PS_RestSneak (tools/anim/make_rest.py), blade low in the sword hand, off hand at the side. The rests
# keep playing while turning in place: vanilla's turn only takes the legs, pelvis, and lower spine
# (turning/turn.xml), so the sword stays in the rest above them.
STANCES = {
    "guard": dict(variable="PSGuard", clip="PS_Ready", rank=0, conditions=[("PSBeckon", "BOOL", "false")]),
    # Now and then, standing in the ready stance, the off hand leaves the hilt to beckon
    # (PS_ReadyBeckon, one pass; PS_Stance.lua sets PSBeckon for its length).
    "beckon": dict(variable="PSBeckon", clip="PS_ReadyBeckon", rank=1, looped=False,
                   conditions=[("PSWalking", "BOOL", "false")]),
    # The same beckon while aiming an extinguished hilt (PS_AimBeckon, over vanilla's one-handed aim;
    # PS_Stance.lua sets PSHiltBeckon). The hilt isn't two-handed, and with no lit sword PSFemale is
    # unset, so this node takes any weapon and either sex.
    "hiltBeckon": dict(variable="PSHiltBeckon", clip="PS_AimBeckon", rank=1, looped=False, weapon=None,
                       unisex=True),
    "rest": dict(variable="PSHolding", clip="PS_Rest", rank=0, conditions=[("sneaking", "BOOL", "false")]),
    # Crouched against a wall (vanilla's low sneak) keeps vanilla's two-handed idle.
    "restSneak": dict(variable="PSHolding", clip="PS_RestSneak", rank=0,
                      conditions=[("sneaking", "BOOL", "true"), ("nearWallCrouching", "BOOL", "false")]),
}

# Walking with the sword at rest: this mod's walks (tools/anim/make_rest.py, vanilla's one-handed
# walks with the blade held low) over vanilla's two-handed ones (walk2handed, sneakWalk2handed),
# blended by speed and limp as vanilla's defaultWalk and sneakWalk blend theirs. Walking in trees
# and the low sneak keep vanilla's. Each blend: clip, x (WalkInjury), y (WalkSpeed).
WALKS = {
    "walk": dict(clip="PS_Walk", speed="1.04", blend_time="0.20", footstep="walk",
                 conditions=[("sneaking", "BOOL", "false")],
                 blends=[("PS_WalkLightLimpR", 0.5, 1), ("PS_WalkLightLimpL", -0.5, 1),
                         ("PS_WalkHeavyLimpR", 1, 1), ("PS_WalkHeavyLimpL", -1, 1),
                         ("PS_Walk", 0, 1), ("PS_WalkSlow", 0, 0)],
                 triangles=[(2, 4, 6), (5, 2, 6), (6, 1, 5), (6, 3, 1)]),
    "walkSneak": dict(clip="PS_WalkSneak", speed="sneakLimpSpeedScale", blend_time="0.50", footstep="sneak_walk",
                      conditions=[("sneaking", "BOOL", "true"), ("nearWallCrouching", "BOOL", "false")],
                      blends=[("PS_WalkSneak_Slow", 0, 0), ("PS_WalkSneak", 0, 1),
                              ("PS_WalkSneak_Slow", -1, 0), ("PS_WalkSneak_Slow", 1, 0),
                              ("PS_WalkSneak_Slow", -1, 1), ("PS_WalkSneak_Slow", 1, 1)],
                      triangles=[(5, 3, 1), (2, 5, 1), (6, 2, 4), (1, 4, 2)]),
}

# Each stance per AnimSet state: condition priority, extra conditions, and bone weights
# (aim-strafe leaves the legs to the strafe animation), and clips that replace a stance's own in that state.
STATES = {
    "aim": dict(priority=80, stances=["guard", "beckon", "hiltBeckon"]),
    "strafe": dict(priority=110, stances=["guard", "beckon", "hiltBeckon"],
                   conditions=[("PSWalking", "BOOL", "false")]),
    # Walking in the ready stance plays PS_ReadyWalk, leaned back to offset the walk's forward-tipped pelvis.
    "aim-strafe": dict(priority=80, stances=["guard"], clips={"guard": "PS_ReadyWalk"},
                       bones=[("Bip01", 0, True), ("Bip01_Spine", 1, False), ("Bip01_Spine1", 1, True),
                              ("Bip01_Prop1", 1, None), ("Bip01_Prop2", 1, None)]),
    # Standing at rest, over vanilla's Idle2Handed and sneakidle2handed.
    "idle": dict(priority=80, stances=["rest", "restSneak"]),
}

SEXES = ("male", "female")


def condition(name, kind, value):
    return (f"  <m_Conditions><m_Name>{name}</m_Name><m_Type>{kind}</m_Type>"
            f"<m_Value>{value}</m_Value></m_Conditions>")


def bone(name, weight, descendants):
    extra = "" if descendants is None else f"<includeDescendants>{str(descendants).lower()}</includeDescendants>"
    return (f"  <m_SubStateBoneWeights><boneName>{name}</boneName><weight>{weight}</weight>"
            f"{extra}</m_SubStateBoneWeights>")


def event(name, value, pc):
    return (f"  <m_Events><m_EventName>{name}</m_EventName><m_TimePc>{pc}</m_TimePc>"
            f"<m_ParameterValue>{value}</m_ParameterValue></m_Events>")


def stance_node(stance, state, data, sex):
    lines = [
        "<animNode>",
        f"  <m_Name>PS_{stance['name']}" + ("" if stance.get("unisex") else f"_{sex}") + "</m_Name>",
        f"  <m_AnimName>{data.get('clips', {}).get(stance['name'], stance['clip'])}</m_AnimName>",
        "  <m_Priority>260</m_Priority>",
        f"  <m_ConditionPriority>{data['priority'] + stance['rank']}</m_ConditionPriority>",
        f"  <m_Looped>{str(stance.get('looped', True)).lower()}</m_Looped>",
        f"  <m_StopAnimOnExit>{str(not stance.get('looped', True)).lower()}</m_StopAnimOnExit>",
        "  <m_maxTorsoTwist>0</m_maxTorsoTwist>",
        "  <m_BlendTime>0.22</m_BlendTime>",
        "  <m_BlendOutTime>0.22</m_BlendOutTime>",
        "  <m_useDeferredMovement>false</m_useDeferredMovement>",
        "  <m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>",
    ]
    if stance.get("weapon", "2handed"):
        lines.append(condition("Weapon", "STRING", stance.get("weapon", "2handed")))
    if not stance.get("unisex"):
        lines.append(condition("PSFemale", "BOOL", str(sex == "female").lower()))
    lines += [
        condition(stance["variable"], "BOOL", "true"),
        condition("AimFloorAnim", "BOOL", "false"),
    ]
    lines += [condition(*c) for c in stance.get("conditions", []) + data.get("conditions", [])]
    lines += [bone(*b) for b in data.get("bones", [])]
    lines.append("</animNode>")
    return "\n".join(lines) + "\n"


def walk_node(name, data):
    lines = [
        "<animNode>",
        f"  <m_Name>PS_{name}</m_Name>",
        f"  <m_AnimName>{data['clip']}</m_AnimName>",
        f"  <m_ConditionPriority>80</m_ConditionPriority>",
        f"  <m_BlendTime>{data['blend_time']}</m_BlendTime>",
        f"  <m_SpeedScale>{data['speed']}</m_SpeedScale>",
        "  <m_Scalar>WalkInjury</m_Scalar>",
        "  <m_Scalar2>WalkSpeed</m_Scalar2>",
    ]
    for i, (clip, x, y) in enumerate(data["blends"], 1):
        lines.append(f'  <m_2DBlends referenceID="{i}"><m_AnimName>{clip}</m_AnimName><m_XPos>{x:.2f}</m_XPos>'
                     f"<m_YPos>{y:.2f}</m_YPos><m_SpeedScale>0.80</m_SpeedScale></m_2DBlends>")
    for a, b, c in data["triangles"]:
        lines.append(f"  <m_2DBlendTri><node1>{a}</node1><node2>{b}</node2><node3>{c}</node3></m_2DBlendTri>")
    lines += [
        condition("Weapon", "STRING", "2handed"),
        condition("PSHolding", "BOOL", "true"),
        condition("inTrees", "BOOL", "false"),
        condition("isTurningAround", "BOOL", "false"),
    ]
    lines += [condition(*c) for c in data["conditions"]]
    lines += [event("Footstep", data["footstep"], 0.2), event("Footstep", data["footstep"], 0.65)]
    lines.append("</animNode>")
    return "\n".join(lines) + "\n"


def main():
    for old in OUT.glob("*/PS_*.xml"):
        old.unlink()

    files = {}
    for name, stance in STANCES.items():
        stance["name"] = name
        for state, data in STATES.items():
            if name not in data["stances"]:
                continue
            if stance.get("unisex"):
                files[f"{state}/PS_{name}.xml"] = stance_node(stance, state, data, SEXES[0])
                continue
            for sex in SEXES:
                files[f"{state}/PS_{name}_{sex}.xml"] = stance_node(stance, state, data, sex)

    for name, data in WALKS.items():
        files[f"movement/PS_{name}.xml"] = walk_node(name, data)

    for path, text in files.items():
        target = OUT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    print(f"Wrote {len(files)} AnimSets to {OUT}")


if __name__ == "__main__":
    main()
