#!/usr/bin/env python3
"""Generate the Photon Sword Forms AnimSets from this mod's own move animation data.

Forms play animation clips that ship with Senator's Martial Arms (its SWMK_Katana_* .x files),
plus this mod's own PSF_Block and PSF_Dodge*; no clip or AnimSet of Senator's is copied. Every node here is authored from
MOVES and STANCES below and reads only this mod's animation variables (PSFHolding, PSFActive,
PSFMove, ...), which PSF_Core.lua sets, so Forms never touch Senator's katana art. A node names
the clip it plays by Senator's clip name, which the game resolves from the installed mod.
How the sword is held between moves (rest, walks, ready stance, beckons) is Photon Sword's own
stance (tools/gen_animsets.py and the PS_* clips), which the block outranks.

AnimSet nodes are shared by every Form: a move id (PSFMove) picks its node, so a new Form reuses
these moves or adds its own entries here.

Usage: gen_forms_animsets.py   (rewrites 42/media/AnimSets/player/*/PSF_*.xml)
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "PhotonSwordForms/Contents/mods/PhotonSwordForms/42/media/AnimSets/player"

# Senator's clip names for a move id (Senator's Martial Arms, media/anims_X/SWMA).
CLIP = {"male": "SWMK_Katana_{}", "female": "SWMK_Katana_Female_{}"}
# The block held with Martial Arts Core's Block key (PSFBlock), playing this mod's own PSF_Block
# (common/media/anims_X/PSF, tools/anim/make_block.py) for both sexes. It outranks Photon Sword's
# ready stance (PS_Ready), which also gives way to it (PS.addStanceYield in PSF_Core.lua): a playing
# stance node seems to keep playing while its own conditions hold, even when a higher-priority node
# matches.
STANCES = {
    "block": dict(variable="PSFBlock", clip="PSF_Block", rank=5),
}

# The photon sword's dodges (tools/anim/make_dodge.py): a leap away with the hilt in the sword hand.
# They replace Senator's Pak Mei dodge nodes for a player holding a photon sword (PSFDodgeAnim, set
# by PSF_Dodging.lua under the Photon Sword Dodge Animation option), with Core's dodge variables:
# SMADodge names the side; the local player's dodge plays in the aim state, another player's
# (SMARemoteDodge) in the melee state, each as Senator's do. The clip's root motion carries the
# player (deferred movement), and SMADodge=done near the end tells Core the dodge is over.
DODGES = {"left": "PSF_DodgeLeft", "right": "PSF_DodgeRight", "back": "PSF_DodgeBack"}

# Per move: when the blade connects (hit) and when the move is done (end), as fractions of its
# clip; whether the clip has a walking (_moving) variant; the move it flows straight into (next,
# with that transition's blend); and a longer blend out for the long lunges.
MOVES = {
    "crosscut":      dict(hit=0.1967, end=0.7541, moving=True, blend_out=0.22),
    "shortthrust":   dict(hit=0.1940, end=0.7761, moving=True, blend_out=0.22),
    "longthrust":    dict(hit=0.2286, end=0.7857, moving=True, blend_out=0.22),
    "thrust":        dict(hit=0.1967, end=0.7541, moving=True),
    "cut":           dict(hit=0.2154, end=0.7692, moving=True),
    "low":           dict(hit=0.2394, end=0.7887, moving=True),
    "thrust_link":   dict(hit=0.4000, end=0.5000, moving=True, next="return_thrust"),
    "return_thrust": dict(hit=0.2121, end=0.7727, moving=True),
    "pair1":         dict(hit=0.3953, end=0.6512, next="pair2", next_blend=0),
    "pair2":         dict(hit=0.1818, end=0.7727),
    "reach":         dict(hit=0.2338, end=0.8052),
    "rise":          dict(hit=0.4333, end=0.5000, next="drop"),
    "drop":          dict(hit=0.2935, end=0.8370),
    "turn":          dict(hit=0.3543, end=0.8571),
    "arc1":          dict(hit=0.5352, end=0.6479, moving=True, next="arc2"),
    "arc2":          dict(hit=0.3636, end=0.6753, next="arc3"),
    "arc3":          dict(hit=0.3392, end=0.8538),
}

# Each stance per AnimSet state: condition priority, extra conditions, and bone weights
# (aim-strafe leaves the legs to the strafe animation), and clips that replace a stance's own in that state.
STATES = {
    "aim": dict(priority=80, stances=["block"]),
    "strafe": dict(priority=110, stances=["block"], conditions=[("PSFWalking", "BOOL", "false")]),
    "aim-strafe": dict(priority=80, stances=["block"], bones=[("Bip01", 0, True), ("Bip01_Spine", 1, False),
                                                           ("Bip01_Spine1", 1, True), ("Bip01_Prop1", 1, None),
                                                           ("Bip01_Prop2", 1, None)]),
    # Turning in place while aiming (tracking a target) would drop the block for the vanilla turn;
    # hold it instead, as Martial Arts Core does for its unarmed block.
    "turning": dict(priority=80, stances=["block"], conditions=[("aim", "BOOL", "true"), ("ismoving", "BOOL", "false")]),
    "turningAim180": dict(priority=80, stances=["block"],
                          conditions=[("aim", "BOOL", "true"), ("ismoving", "BOOL", "false")]),
}

# Moving attacks animate the upper body only; the player's legs keep walking.
MOVING_BONES = [("Bip01_Spine", 1, False), ("Bip01_Spine1", 1, True), ("Bip01_Neck", 1, True),
                ("Bip01_BackPack", 1, True), ("Bip01_Prop1", 1, True), ("Bip01_Prop2", 1, True)]
STANDING_BONES = [("Bip01", 1, None)]

SEXES = ("male", "female")


def node_name(move, sex, moving=False):
    return f"PSF_{move}_{sex}" + ("_moving" if moving else "")


def number(value):
    return f"{value:.4f}".rstrip("0").rstrip(".") if isinstance(value, float) else str(value)


def condition(name, kind, value):
    return (f"  <m_Conditions><m_Name>{name}</m_Name><m_Type>{kind}</m_Type>"
            f"<m_Value>{value}</m_Value></m_Conditions>")


def bone(name, weight, descendants):
    extra = "" if descendants is None else f"<includeDescendants>{str(descendants).lower()}</includeDescendants>"
    return (f"  <m_SubStateBoneWeights><boneName>{name}</boneName><weight>{weight}</weight>"
            f"{extra}</m_SubStateBoneWeights>")


def event(name, value, time=None, pc=None):
    when = f"<m_Time>{time}</m_Time>" if time else f"<m_TimePc>{number(pc)}</m_TimePc>"
    param = f"<m_ParameterValue>{value}</m_ParameterValue>" if value else "<m_ParameterValue />"
    return f"  <m_Events><m_EventName>{name}</m_EventName>{when}{param}</m_Events>"


def melee_node(move, data, sex, moving):
    end = data["end"]
    lines = [
        "<animNode>",
        f"  <m_Name>{node_name(move, sex, moving)}</m_Name>",
        f"  <m_AnimName>{CLIP[sex].format(move + ('_moving' if moving else ''))}</m_AnimName>",
        "  <m_Priority>260</m_Priority>",
        f"  <m_ConditionPriority>{81 if moving else 80}</m_ConditionPriority>",
        "  <m_Looped>false</m_Looped>",
        "  <m_BlendTime>0.10</m_BlendTime>",
        f"  <m_BlendOutTime>{data.get('blend_out', 0.10):.2f}</m_BlendOutTime>",
        "  <m_StopAnimOnExit>false</m_StopAnimOnExit>",
        "  <m_maxTorsoTwist>0</m_maxTorsoTwist>",
        "  <m_SpeedScale>PSFAttackSpeed</m_SpeedScale>",
        "  <m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>",
        "  <m_EarlyTransitionOut>false</m_EarlyTransitionOut>",
        "  <m_DeferredBoneName>Bip01</m_DeferredBoneName>",
        "  <m_deferredBoneAxis>Z</m_deferredBoneAxis>",
        "  <m_useDeferredMovement>false</m_useDeferredMovement>",
        condition("PSFHolding", "BOOL", "true"),
        condition("Weapon", "STRING", "2handed"),
        condition("AimFloorAnim", "BOOL", "false"),
        condition("PSFActive", "BOOL", "true"),
        condition("PSFMove", "STRING", move),
        condition("PSFFemale", "BOOL", str(sex == "female").lower()),
    ]
    if moving:
        lines.append(condition("PSFAttackMoving", "BOOL", "true"))
    lines += [
        event("AttackAnim", "TRUE", time="Start"),
        # A moving attack leaves the legs free to walk.
        event("BlockMovement", "FALSE" if moving else "TRUE", time="Start"),
        event("PlaySwingSound", None, time="Start"),
        event("PlayerVoiceSound", "MeleeAttack", time="Start"),
        event("AttackCollisionCheck", "MeleeSwing", pc=data["hit"]),
        event("SetVariable", f"PSFCompleted={move}", pc=end),
        event("BlockMovement", "FALSE", pc=end),
        event("AttackAnim", "FALSE", pc=end),
        event("SetMeleeDelay", "0", pc=end),
    ]
    lines += [bone(*b) for b in (MOVING_BONES if moving else STANDING_BONES)]
    if data.get("next"):
        blend = number(data.get("next_blend", 0.06))
        lines.append(f"  <m_Transitions><m_Target>{node_name(data['next'], sex)}</m_Target>"
                     f"<m_blendInTime>{blend}</m_blendInTime><m_blendOutTime>{blend}</m_blendOutTime>"
                     "</m_Transitions>")
    lines.append("</animNode>")
    return "\n".join(lines) + "\n"


def stance_node(stance, state, data, sex):
    lines = [
        "<animNode>",
        f"  <m_Name>PSF_{stance['name']}" + ("" if stance.get("unisex") else f"_{sex}") + "</m_Name>",
        f"  <m_AnimName>{data.get('clips', {}).get(stance['name'], stance['clip']).format(sex)}</m_AnimName>",
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
        lines.append(condition("PSFFemale", "BOOL", str(sex == "female").lower()))
    lines += [
        condition(stance["variable"], "BOOL", "true"),
        condition("AimFloorAnim", "BOOL", "false"),
    ]
    lines += [condition(*c) for c in stance.get("conditions", []) + data.get("conditions", [])]
    lines += [bone(*b) for b in data.get("bones", [])]
    lines.append("</animNode>")
    return "\n".join(lines) + "\n"


def dodge_node(side, clip, remote):
    lines = [
        "<animNode>",
        f"  <m_Name>PSF_dodge_{side}" + ("_remote" if remote else "") + "</m_Name>",
        f"  <m_AnimName>{clip}</m_AnimName>",
        "  <m_Looped>false</m_Looped>",
        "  <m_SpeedScale>SMADodgeSpeed</m_SpeedScale>",
        f"  <m_Priority>{350 if remote else 170}</m_Priority>",
        # Above Senator's Pak Mei dodges (40 local, 30 remote) and Photon Sword's stance (80-90).
        "  <m_ConditionPriority>95</m_ConditionPriority>",
        "  <m_BlendTime>0.05</m_BlendTime>",
        "  <m_BlendOutTime>0.10</m_BlendOutTime>",
        "  <m_StopAnimOnExit>true</m_StopAnimOnExit>",
        "  <m_SyncTrackingEnabled>false</m_SyncTrackingEnabled>",
        "  <m_DeferredBoneName>Bip01</m_DeferredBoneName>",
        "  <m_deferredBoneAxis>Z</m_deferredBoneAxis>",
        "  <m_useDeferredMovement>true</m_useDeferredMovement>",
        condition("SMADodge", "STRING", side),
        condition("PSFDodgeAnim", "BOOL", "true"),
    ]
    if remote:
        lines += [
            condition("SMARemoteDodge", "BOOL", "true"),
            event("AttackAnim", "TRUE", time="Start"),
            event("AttackAnim", "FALSE", time="End"),
            event("SetVariable", "SMARemoteDodge=false", time="End"),
        ]
    lines += [
        bone("Bip01", 1, None),
        event("SetVariable", "SMAPakMeiRightGuard=false", pc=0.98),
        event("SetVariable", "SMADodge=done", pc=0.985),
        event("SetVariable", "SWMADodge=false", pc=0.985),
        "</animNode>",
    ]
    return "\n".join(lines) + "\n"


def main():
    for move, data in MOVES.items():
        assert not data.get("next") or data["next"] in MOVES, f"{move} flows into unknown {data['next']}"
    for old in OUT.glob("*/PSF_*.xml"):
        old.unlink()

    files = {}
    for move, data in MOVES.items():
        for sex in SEXES:
            for moving in (False, True) if data.get("moving") else (False,):
                files[f"melee/{node_name(move, sex, moving)}.xml"] = melee_node(move, data, sex, moving)
    for name, stance in STANCES.items():
        stance["name"] = name
        for state, data in STATES.items():
            if name not in data["stances"]:
                continue
            if stance.get("unisex"):
                files[f"{state}/PSF_{name}.xml"] = stance_node(stance, state, data, SEXES[0])
                continue
            for sex in SEXES:
                files[f"{state}/PSF_{name}_{sex}.xml"] = stance_node(stance, state, data, sex)

    for side, clip in DODGES.items():
        files[f"aim/PSF_dodge_{side}.xml"] = dodge_node(side, clip, False)
        files[f"melee/PSF_dodge_{side}_remote.xml"] = dodge_node(side, clip, True)

    for path, text in files.items():
        target = OUT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    print(f"Wrote {len(files)} AnimSets to {OUT}")


if __name__ == "__main__":
    main()
