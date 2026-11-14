# Photon Sword Forms

A Build 42 companion mod for [Photon Sword](../README.md) and Senator's Martial Arms. It adds
**photon sword Forms**: fighting styles for an ignited photon sword, each learned from its own
manual and trained through its own mastery. Pick your Form in the **Photon Sword** tab of
Senator's martial arts window. How the sword is held between moves (the rest, walks, ready
stance, and beckons) is Photon Sword's own stance, which every ignited sword gets; a Form adds its
attacks, its block, and deflecting gunfire.

## Requirements

| Mod | ID | Where |
|---|---|---|
| Photon Sword | `PhotonSword` | This repo, `PhotonSword/` (the version with the stance, `PS_Stance.lua`) |
| Senator's Martial Arms | `SenatorMartialArms` | Workshop 3823941212 |
| Senator Martial Arts Core | `SenatorMartialArtsCore` | Workshop 3812456765 (this mod's Lua requires `SMA_Core` directly) |

Game version: Build 42.22 or later (the latest stable release; Senator's mods need 42.20).

## Forms

| Form | Manual | Moves |
|---|---|---|
| Form 1 | `PhotonSwordForms.PhotonSwordManual` ("Photon Sword: Form 1") | 17 moves on Senator's katana clips, unlocked at mastery 0-4 |

## How it works

Senator's Martial Arms builds each weapon art (prefix `SWMK` for the katana, `SWMA` for the bo
staff, and so on) from a per-art definition plus shared machinery in its `SWMA_*.lua` files.
**Each Form is one such art**, modeled on the katana's:

- **Forms** (`shared/PhotonSwordForms/PSF_Core.lua`): `PSF.define` builds a Form from a
  definition and registers it with Senator's machinery: progression (Martial Arts XP, mastery,
  stamina, attack speed), moving attacks, the per-move shuffle, and weapon dodges. Each Form has
  its own manual, mastery track (style `psf_<id>`), state in player modData (`PSF_<id>`), and
  server module (`PhotonSwordForms_<id>`). Form definitions live in `PSF_Form<n>.lua`, and
  `PSF_Forms.lua` lists them in display order.
- **Active Form**: a player fights with one Form at a time, stored in modData (`PSF_art.active`).
  A Form can be used only if it's the active one, it's learned, and the player holds an ignited
  `PhotonSword.PhotonSword` in both hands, so Forms never compete for a swing. Learning a
  player's first Form makes it active. Once two or more Forms are learned, the tab's choice
  button switches between them.
- **Takeover from the katana art**: the lit photon sword is a two-handed Long Blade, so Senator's
  katana art would also claim it. `PSF_Core.lua` wraps `SWMK.canUse` so the katana art steps
  aside whenever a Form is enabled (`PSF.fightingForm`: active, learned, usable, and not disabled
  in the tab).
- **No Form enabled**: with none learned, or the active one disabled with the tab's Disable
  button, the ignited sword gets the game's default two-handed katana behavior. Photon Sword's
  stance yields (`PS.addStanceYield`), so the sword plays vanilla's two-handed animations (or
  Senator's katana art's, for a player who knows it), the ready stance doesn't deflect gunfire, and
  running keeps the blade lit.
- **Animations** (`media/AnimSets/player/`): authored by `tools/gen_forms_animsets.py` from the mod's
  own move data: each move's clip, hit and end points, walking variant, and the move it flows
  into, plus the block. The nodes read only the mod's own variables (`PSFHolding`, `PSFActive`, `PSFMove`, ...).
  They play Senator's `SWMK_Katana_*` clips by name, which load from Senator's mod; no `.x` files
  are copied. Senator's katana art and its `SWMK*` variables are never touched. All Forms share
  the `PSF*` variables, and a move id picks its node. Because only the active Form may touch
  these variables, inactive Forms update before the active one and never clear them on sync or
  attack finish.
- **Form 1** (`PSF_Form1.lua`): the mod's own move list, mastery gates, combos, clip lengths,
  attack speed, and standing-only moves. Nothing is read from Senator's katana art.
- **Mastery damage** (`PSF_Settings.lua`): each mastery level of the Form you fight with adds 10%
  to the sword's damage in it (+50% at mastery 5; the sandbox's Damage per Form Mastery Level). It
  wraps Senator's `damageScale`, which sets the weapon's damage for every strike, so it stacks with
  Senator's Attack Damage multiplier and shows in the Photon Sword tab's Damage row.
- **Guard**: Martial Arts Core's block (`SMA_Guard.lua`) normally works only for unarmed styles.
  `PSF_Core.lua` wraps `SMA.guardEligible` so a Form with `guard = true` (Form 1 has it) can
  guard with an ignited sword. The player holds Core's Block key while aiming. Core runs the
  rest: guard meter and HUD, perfect-guard stagger, zombie pushes, guard break, and multiplayer
  sync. `SMA.guardDrain` is wrapped so Form users get Core's Martial Arts level drain reduction
  without an unarmed style. While the guard is up, Form moves don't start. The pose is driven by
  the mod's own `PSFBlock` variable (set from Core's `SMAGuard`) and plays the mod's own clip,
  `PSF_Block`: a center guard, both hands on the hilt in front of the body's middle and the blade
  held vertical, breathing in a 2.6-second loop (chest and shoulders rise, the body settles on
  planted feet, the sword rides along). The guard stance requires `PSFBlock=false`, so raising
  the guard switches nodes immediately rather than on the next move. When the block stops a
  blow, it plays `PSF_BlockParry` once (0.5 s): the blow knocks the blade's tip toward the off
  side, the hands recoil, and the body rocks back and sinks, then the guard comes back to center
  (`PSFParry`, set while the clip plays). That's every blow the block stops: a photon sword strike
  Photon Sword settles (an NPC's, from the patch mods) and any melee blow Martial Arts Core
  settles itself (another player's). Core's blocks are told from its other guard drains by the
  guard's `lastHit` stamp (`PSF.newCoreBlock`): a new stamp made as a melee blow struck the
  player, and not one Photon Sword made (bullets, shotgun soaks) or a zombie pushed off the guard.
  Only the side settling the blow can tell, so in multiplayer the server sends every client a
  `parry` (`PSF_Server.lua`), and the blocker sees it a round trip after the block.
- **Deflecting bullets** (`shared/PhotonSwordForms/PSF_Deflect.lua`): Photon Sword's deflect
  (`PS_Deflect.lua`: the rolls, shotgun soaks, striking back, multiplayer sync, and its sandbox and
  mod options) with a Form's guard in place of its ready stance. For a player whose active Form can
  guard, the guard is Martial Arts Core's block (past Core's startup, not broken, within Core's arc),
  guard skill is the Form's mastery and the Martial Arts level weighted equally (so full skill, and
  the whole-blast chance, needs full mastery), and each deflection drains the guard meter by Core's
  own block drain (`SMA.guardDrain`, lowered by Martial Arts level, scaled by Guard Drain from
  Gunfire). One the meter can't pay for breaks the guard and the shot lands; a soaked blast pays that
  share of the drain. It does this by replacing Photon Sword's guard hooks (`PS.guardUp`,
  `PS.guardFacing`, `PS.guardSkill`, `PS.guardDrain`, `PS.drainGuard`, `PS.guardPays`, and for
  blocking photon swords `PS.blockChance`, which is 100: the block always holds while the meter
  pays) for those players. Another player's photon sword strike is left to Core's own block, which
  already takes any melee hit between players (`PS.meleeGuardHandled`); an NPC's goes through Photon
  Sword's block and drains the meter by Core's rule. Everyone else keeps Photon Sword's rules. Bandits and Project A-Life gunfire is covered by
  Photon Sword's patch mods, which work with or without this mod.
- **Stance**: between moves, a player with an enabled Form holds the ignited sword in Photon Sword's
  stance (`PS_Stance.lua`: the rest, walks, ready stance, and its beckons). The block outranks it,
  and the stance also yields while the block is up, since a playing node keeps playing while its
  own conditions hold (`PS.addStanceYield` in `PSF_Core.lua`). It yields while a dodge plays too:
  the ready stance's AnimSets outrank Senator's Pak Mei dodge nodes, so the dodge key would roll
  the dodge without its animation.
- **Dodging** (`client/PhotonSwordForms/PSF_Dodging.lua`, `shared/PhotonSwordForms/PSF_Dodge.lua`):
  pressing Core's dodge key while aiming a photon sword (with a Form, or Senator's katana art)
  starts Core's dodge, but plays the photon sword's own leap (`PSF_DodgeLeft`, `_Right`, `_Back`,
  from `tools/anim/make_dodge.py`) in place of the Pak Mei dodge, whose clips let the weapon bone
  drift up to 40 cm from the hand. The leap crouches, springs about two tiles away on an arc with
  the feet tucked and the off arm out, lands on bent knees, and rises to the aim, the hilt held in
  the sword fist throughout. It matches the Pak Mei dodge's length and distance, so Core times it
  and measures its root motion the same way. The `PSF_dodge_*` AnimSets play it on `PSFDodgeAnim`
  (set for players holding a photon sword, under the Photon Sword Dodge Animation option) with
  Core's `SMADodge`, the local player's in the aim state and other players' (`SMARemoteDodge`) in
  the melee state, as Senator's are.
  With Extinguish While Dodging on, a lit blade goes out through Photon Sword's toggle action as
  the dodge starts, and relights when it ends (Relight After Dodge), if the battery holds charge and
  nothing else relit or put away the sword. The hilt left in hand fits no dodge style, so the style
  the dodge started with is kept until Core finishes it (or 3 seconds pass), letting the dodge and
  its Lightfoot XP complete.
- **Photon Sword tab** (`client/PhotonSwordForms/PSF_Tab.lua`): added next to Senator's Unarmed
  and Weapons tabs, in both the character info panel and the standalone window. It's a copy of
  Senator's Weapons page (`SWMA_WeaponWindow.lua`) listing Forms instead of arts, with the same
  layout, Enable/Disable and Manual buttons, Martial Arts card, footer, and admin button. Senator's
  spear/staff choice button becomes the active-Form choice, shown once two or more Forms are
  learned. Move names are the mod's own (`UI_PSF_<id>_Move_<move>`).
- **Admin**: `PSF_Forms.lua` adds each Form to Senator's table of arts (`SWMA_TrainingStyles`),
  so Senator's admin window can set a Form's learned state and mastery. They're added after
  Senator registers its practice Exercises, so Forms get no Exercise.
- **Combat** (`client/PhotonSwordForms/`): the combo driver (`PSF_Combos.lua`), swing and
  server-command events (`PSF_Combat.lua`), and footwork during moves (`PSF_Movement.lua`),
  installed on every Form. They work as Senator's `SWMK_Combos.lua`, `SWMK_Combat.lua`, and
  `SWMA_PlayerMovement.lua` do, with the same timings and vanilla's walking speeds, so Forms
  chain and move like Senator's arts.
- **Server** (`server/PhotonSwordForms/`): per-Form state sync, move approval and relay, and XP on
  hit. Also active-Form selection and manual loot.
- **Manuals** (`scripts/item_photonswordforms.txt`): 120-page magazines with this mod's own icon,
  cover, and textures on the game's magazine meshes (`scripts/models_photonswordforms.txt`), painted
  by `tools/gen_manual.py`. They're registered with Senator's illustrated manual window
  (`client/PhotonSwordForms/PSF_Manual.lua`), which shows the cover.

Senator's shared machinery has a few closed lists. This is how the mod works around each one:

| Senator file | Closed list | Workaround |
|---|---|---|
| `SWMA_DirectionPolicy` | disabled moves per prefix | adds an empty `PSF` entry before applying |
| `SWMA_MovingAttack` | standing-only moves per prefix | each Form sets its own after install |
| `SWMA_AutoCycle` | cycling mode chosen by prefix | installs with `"SWMK"` (prefix only picks the mode) |
| `SWMA_Dodge` | arts that dodge | wraps `SMA.weaponDodgeStyle` and `present` |
| `SWMA_PlayerMovement` | arts with footwork leases | `PSF_Movement.lua` reimplements it |
| `SWMA_GuardPeers` | arts refreshed for remote players | `PSF_Combat.lua` refreshes the Forms |
| `SWMA_WeaponWindow` | arts in the Weapons tab | a copy of the page in the Photon Sword tab (`PSF_Tab.lua`) |
| `SWMA_TrainingStyles` | arts with Exercise practice | **not handled yet** |

### Adding a Form

1. Write `shared/PhotonSwordForms/PSF_Form<n>.lua` with a `PSF.define{...}` call (fields are
   listed above `PSF.define` in `PSF_Core.lua`). Each move id needs an entry in `MOVES` in
   `tools/gen_forms_animsets.py`; add one for a new move (any clip in Senator's mods) and re-run it.
2. Require it from `PSF_Forms.lua`.
3. Add its manual item to `scripts/item_photonswordforms.txt` and translations for
   `UI_PSF_Form<n>`, `UI_PSF_Form<n>_Admin`, `UI_PSF_<id>_EquipStaff`, `UI_PSF_<id>_Guide*`, and the
   manual's name, and `UI_PSF_<id>_Move_<move>` for each move.
4. Add the Form to `FORMS` in `tools/gen_manual.py` and re-run it, then add its
   `PSF_Manual_<n>_Reading` and `_Ground` models to `scripts/models_photonswordforms.txt` and point
   the manual item at them (`Icon = PSF_Manual_<n>`).

## Settings

**Sandbox options** (the Photon Sword Forms section of the Photon Sword page; `media/sandbox-options.txt`, read through
`PSF.sandbox` in `PSF_Settings.lua`): the server's balance.

| Option | Default | |
|---|---|---|
| Damage per Form Mastery Level (%) | 10 | Each mastery level of the Form adds this to the sword's damage in it (+50% at full mastery), on top of Senator's Attack Damage multiplier. |
| Extinguish While Dodging | on | A dodge puts a lit blade out for the leap; off keeps it lit. |
| Guard Drain from Gunfire and Blocks | 1.0 | Scales the guard meter's drain from deflects, soaks, and blocked NPC photon sword strikes; 0 never drains. |

**Mod options** (the Forms: Dodging section of Options > Mods > Photon Sword,
`client/PhotonSwordForms/PSF_Options.lua`): per-player client settings.

| Option | Default | |
|---|---|---|
| Photon Sword Dodge Animation | on | Players dodging with a photon sword play its leap, hilt in hand; off plays Core's Pak Mei dodge. Applies to every player this client sees. |
| Relight After Dodge | on | Relights your blade on landing when a dodge put it out. |

The deflect options (Deflect Bullets, the deflect and soak chances, striking back, the whole-blast
chance) are in Photon Sword's sections of the sandbox page, and the Deflect Text, Deflect Spark Sound, and Beckon
Chance mod options are Photon Sword's.

## Current status

Version 0.1.0. Form 1 is a Senator weapon art with its
own move data, AnimSets, variables, and move names; only Senator's attack clips are reused, by
name. It guards with Martial Arts Core's block, which deflects gunfire through Photon Sword's
deflect. The stance between moves, deflecting from the ready stance, putting the blade out to run,
and the A-Life and Bandits patches are Photon Sword's. The manual has its own art. It's **not yet
tested in-game**. All Lua passes `luac5.1 -p`.

Known gaps to work on next:

- No Exercise practice for Forms.
- Form 1 uses the katana's clips and timings. Photon-sword-specific Forms come next.
- The server doesn't refuse a Form move while that player's guard is up. Only the client
  checks.
- The Photon Sword's cutting fires on `OnWeaponSwingHitPoint`. It should fire for these moves,
  since every move's AnimSet has an `AttackCollisionCheck` event, but that's unverified.
- Saves from 0.0.1 lose the learned art and its mastery (state moved from `PSF` /
  `psf_photonsword` to `PSF_form1` / `psf_form1`). Re-read the manual.

## Development

- The repo's `./deploy.sh` copies this mod to `~/Zomboid/mods/PhotonSwordForms`, along with Photon
  Sword and the patch mods. It also copies in the dev kit; `./deploy.sh --release` leaves it out.
- **Releasing:** `./release.sh` checks the mod and builds it into `releases/` for the Workshop
  uploader, without the tools or dev kit. See the [README](../README.md#releasing-to-the-steam-workshop).
- **Dev kit** (`dev/PSF_DevKit.lua`, outside the mod folder so it never ships): each character
  gets it once on spawn. It teaches every Form at mastery 5 and adds their manuals, and sets Martial
  Arts to 10. The sword comes from Photon Sword's kit (`dev/PS_DevKit.lua`: an
  ignited sword in both hands, spare batteries, and Long Blade 10), which
  `deploy.sh` copies in too. Change the `KIT` table to adjust it, and bump `KIT.version` to give it
  again to existing characters, or run `PSFDevKit.give(getPlayer())` in the debug Lua console.
  Single player only. Guard with Block (Caps Lock by default) while aiming.
- `python3 tools/gen_manual.py` paints each Form manual's icon, cover, and held and floor magazine
  textures into `media/textures/` (Pillow and the DejaVu fonts). Add a Form to its `FORMS` table,
  and a model pair to `models_photonswordforms.txt`, for a new manual.
- `tools/anim/make_dodge.py` builds `PSF_DodgeLeft.x`, `PSF_DodgeRight.x`, and `PSF_DodgeBack.x` from
  vanilla's one-handed aim (`Bob_IdleAim1Hand`): the root travels `DISTANCE` on the `HEIGHT` and
  `TRAVEL` curves, the feet plant until `TAKEOFF`, tuck up by `FOOT_LIFT`, and plant again at
  `LANDING`, the torso leans by `LEAN`, and the off arm swings out by `OFF_ARM`. Each key puts the
  weapon bone back on the sword hand (it hangs off the root), and the tool prints the root's
  travel, how far the hilt slips, and the lowest foot. Re-run `gen_forms_animsets.py` after renaming one.
- `tools/anim/make_block.py` builds `common/media/anims_X/PSF/PSF_Block.x` (and its one-pass parry,
  `PSF_BlockParry.x`: `PARRY_*`), with Photon Sword's
  animation library (`tools/anim/xfile.py`, `tools/anim/animlib.py`). Clips must live under
  `common/`: the game skips a mod's `42/media/anims_X` entirely unless `common/media/anims_X`
  exists (`ModelManager.loadHumanAnimations`), which is why Senator ships an empty
  `common/media/anims_X/Bob/.keep`. It starts from vanilla's
  two-handed aim (`Bob_IdleAimBat`, read from the installed game), squares the torso by `TORSO_TURN`, places the
  weapon bone at `GRIP` with the blade along `BLADE`, animates the breath (`BREATH_*`, `CHEST_DEGREES`,
  `SHOULDER_DEGREES`, `SINK`, `SWORD_LIFT`; legs are solved to keep the feet planted), and solves both arms so the hands keep their vanilla grip, each rolled around the hilt by
  `GRIP_ROLL` (which keeps the wrists straight) with the elbows aimed by `ELBOW_POLE` (down and out, so
  the left arm comes in under the right hand instead of wrapping around it).
- The stance clips and their tools (`make_ready.py`, `make_rest.py`, `make_aim_beckon.py`,
  `make_guard.py`, `render.py`) are Photon Sword's; see the [README](../README.md#stance-animation-tools).
- `python3 tools/gen_art.py` paints every mod's art: a stylized ignited photon sword, Forms' purple
  in an enso, for `preview.png` (256x256), `42/poster.png` (256x256), and `42/icon.png` (32x32). See the
  [README](../README.md). `tools/anim/poster.py` still renders a character in the ready stance with
  Blender, if you want that look instead.
  Pass absolute output paths; Blender treats relative ones as relative to the blend file.
- `tools/gen_forms_animsets.py` rewrites the move and block AnimSets from its `MOVES`, `STANCES`, and `STATES` tables. Re-run it
  after changing them.
- Senator's source is in
  `~/.local/share/Steam/steamapps/workshop/content/108600/3823941212/mods/SenatorMartialArms/42/media/lua/`.
  The katana art (`SWMK_*.lua`) is the reference for everything here.

## Credits

Photon Sword Forms is built on **Senator's Martial Arms** and **Senator Martial Arts Core** by
Senator, and plugs into their machinery (progression, moving attacks, the move shuffle, dodges,
guard, and the martial arts window). The attack animation clips are Senator's, loaded from
Senator's mods; none are copied. The block clips, manual art, sounds, and stance are this mod's
own; the block and dodge clips are built from vanilla's animations and carry vanilla's skeleton
and mesh, under The Indie Stone's Terms (see the README's
[Third-party content](../README.md#third-party-content)). The manual's text is set in DejaVu.

Some of this mod's Lua is adapted from Senator's katana art, because the parts it would reuse are
written for one art and can't be called for a Form: `PSF_Core.lua`, `PSF_Combat.lua`, and
`PSF_Form1.lua` follow `SWMK_Core.lua` and `SWMK_Combat.lua`, and `PSF_Tab.lua` follows the layout
of `SWMA_WeaponWindow.lua`. Those adapted parts are Senator's work. `PSF_Combos.lua`,
`PSF_Movement.lua`, `PSF_Sequence.lua`, and `PSF_Server.lua` are this mod's own, written to
behave as Senator's `SWMK_Combos.lua`, `SWMA_PlayerMovement.lua`, `SWMK_Sequence.lua`, and
`SWMK_Server.lua` do: they keep the function names Senator's machinery calls and the same rules
and timings.

## License

Released under the [MIT License](../LICENSE), like the rest of this repo, except for the parts
adapted from Senator's code (listed under Credits), which remain Senator's, and The Indie Stone's
content in the block and dodge clips; neither is covered by it. Senator's mods, which this one requires and whose attack clips it loads, are not part of it.
