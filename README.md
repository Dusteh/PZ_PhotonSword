# Project Zomboid Photon Sword Mod

A Build 42 mod for [Project Zomboid](https://projectzomboid.com/) that adds photon swords to the game.
Each one is a two-handed energy blade you can find, ignite, and fight with.

This repo ([github.com/Dusteh/PZ_PhotonSword](https://github.com/Dusteh/PZ_PhotonSword)) holds every mod in the family,
each uploaded to the Workshop as its own item:

| Mod | ID | What it does |
|---|---|---|
| Photon Sword | `PhotonSword` | The sword: hilt, battery, blade, stance, deflecting gunfire, blocking photon swords, cutting |
| Photon Sword Forms | `PhotonSwordForms` | Fighting styles on Senator's Martial Arms ([docs](docs/PhotonSwordForms.md)) |
| Photon Sword - Project A-Life | `PhotonSwordALife` | Patch: A-Life NPCs carry photon swords, and the guard deflects their gunfire |
| Photon Sword - Bandits | `PhotonSwordBandits` | Patch: bandits carry photon swords, and the guard deflects their gunfire |

The two NPC patches keep the same feature set: see [NPC patch feature set](docs/NPC_PATCHES.md).

## Goal

Add a photon sword weapon that feels distinct from vanilla melee weapons while still fitting
Zomboid's survival balance:

- **New weapon items.** A photon sword hilt and its ignited blade, defined as item scripts and
  modeled on the vanilla `Katana` (`base:longblade`, two-handed, slashing). Each player picks
  their blade color in the mod options.
- **Ignite and extinguish.** A Lua-driven toggle between an inert hilt (light, harmless,
  stashable) and an ignited blade (high damage, emits light, hum and swing sounds).
- **Power source.** The blade drains a power cell or battery while ignited, so it's a
  resource to manage rather than a free win.
- **Light emission.** An ignited blade casts colored light around the player.
- **Durability.** The blade itself doesn't dull. Wear lands on the hilt or the power cell.
- **Spawning and loot.** Rare spawns added to loot distributions.
- **Assets.** 3D hilt and blade models, inventory icons, and sound effects.
- **Multiplayer safe.** Logic is split correctly across `client/`, `server/`, and `shared/`.

## Target

| | |
|---|---|
| Game version | Build 42.22 or later (`versionMin=42.22.0` in every `mod.info`) |
| Language | Lua 5.1 (Kahlua) plus PZ item/model script `.txt` files |
| Mod IDs | `PhotonSword`, `PhotonSwordForms`, `PhotonSwordALife`, `PhotonSwordBandits` (each must match `id=` in its `mod.info`) |

## Layout

The Build 42 mod layout, using Workshop packaging. Every mod folder follows the same shape:

```
PhotonSword/
├── workshop.txt                  # Workshop page (no id= until the first upload writes one)
├── preview.png                   # Workshop thumbnail, 256x256 (tools/gen_art.py)
└── Contents/mods/PhotonSword/
    ├── common/media/anims_X/PS/  # Stance clips (the game only loads clips from common/)
    └── 42/
        ├── mod.info              # name, id, author, description, url, poster, icon
        ├── poster.png            # 256x256, and icon.png 32x32 (tools/gen_art.py)
        ├── icon.png
        └── media/
            ├── AnimSets/player/  # Stance AnimSets (tools/gen_animsets.py)
            ├── scripts/          # item_photonsword.txt, models_photonsword.txt, sounds
            ├── lua/
            │   ├── client/       # UI, context menu (ignite/extinguish), light effects
            │   ├── server/       # loot distributions, power drain authority
            │   └── shared/       # constants, item helpers used by both sides
            ├── models_X/         # 3D models (.fbx / .X)
            ├── textures/         # Item_*.png icons, model textures
            └── sound/            # hum, ignite, swing, clash
PhotonSwordForms/                 # Companion mod: Forms, fighting styles (docs/PhotonSwordForms.md)
PhotonSwordALife/                 # Patch mod: Project A-Life NPCs carry swords and are deflected
PhotonSwordBandits/               # Patch mod: bandits carry swords and are deflected
dev/PS_DevKit.lua                 # Dev kits, deployed for testing only
dev/PSF_DevKit.lua
dev/PSA_DevKit.lua                # A-Life photon sword duel (PSDevKit.duel)
dev/*_DevKitTest.lua              # In-game test suites (PSTest.run)
docs/PhotonSwordForms.md          # Photon Sword Forms' docs
docs/NPC_PATCHES.md               # The feature set every NPC patch keeps
tools/                            # Model, sound, animation, AnimSet, and manual generators
deploy.sh                         # Copies every mod into ~/Zomboid/mods for testing
release.sh                        # Checks every mod and builds it into releases/ for the Workshop
releases/                         # Built Workshop folders (gitignored)
```

Only each mod's `workshop.txt`, `preview.png`, and `Contents/` reach Steam (see
[Releasing](#releasing-to-the-steam-workshop)). `tools/`, `dev/`, and `docs/` stay in the repo.

For local testing, run `./deploy.sh` to copy every mod here (Photon Sword, Photon Sword Forms, and
the patches) into `~/Zomboid/mods/`.
Don't symlink it: the game breaks script paths for symlinked mods (`FileNotFoundException` on
`/home/<user>/Zomboid/mods/home/<user>/zomboid/mods/...`). Re-run the script after every change.

## Current status

The basics are implemented but **not yet tested in-game**.

- **Items** (`scripts/item_photonsword.txt`): `PhotonSword.PhotonSwordHilt` (inert) and
  `PhotonSword.PhotonSword` (ignited). Ignite and extinguish swap one type for the other, keeping
  condition, modData, hotbar binding, and which hands hold it.
- **Power**: a hilt holds a battery's charge in modData (`PS_charge`). Insert Battery and Remove
  Battery work on inert hilts only. The server drains every ignited blade a player carries (held,
  on the hotbar, or in a bag) every in-game minute and extinguishes it when empty.
- **Light**: the client places a colored `IsoLightSource` on each player holding an ignited blade.
- **Loot**: hilts (without a battery) are added to `MedievalWeaponsJapan`, `MeleeWeapons_Late`,
  and `CrateRandomJunk`.
- **Mod options** (Options > Mods > Photon Sword, `client/PhotonSword/PS_Options.lua`),
  per-player client settings:
  - Hotkeys: Ignite / Extinguish (default `Z`, can draw a sword when your hands are empty), Swap
    Battery (default `R`, ignored while R would reload, sharpen, or rotate a placement), Toggle
    Cutting (default `X`), Draw When Hands Are Empty, and Extinguish When Holstered.
  - Visuals: Blade Color, blade light on/off and radius, Default Two-Handed Animations (off; the
    game's two-handed animations in place of the stance, for every player this client sees), and
    the ready stance's Beckon Chance (10%).
  - Sound: hum volume, and tone and pitch for the hum, swing, and hit.
  - Deflect: Show Deflect Text and Deflect Spark Sound.
  - Notifications: the low-power warning threshold.

  Photon Sword Forms adds its own section (Forms: Dodging) to this entry.
- **Sandbox options** (`media/sandbox-options.txt`, Photon Sword page): one page for this mod and
  its patch mods, in titled sections (Photon Sword, Cutting, Deflecting Gunfire, Blocking Photon
  Swords, then Photon Sword Forms, Project A-Life NPCs, and Bandits NPCs when those are on).
  Each mod puts its options on `page = PhotonSword` and registers its section with
  `PS.addSandboxSection(order, title, patterns...)`; `client/PhotonSword/PS_SandboxPage.lua`
  sorts the page and adds the titles (`Sandbox_Title_<title>`), which the new-game sandbox screen
  draws (the in-game admin window keeps the order but draws no titles). The options: battery life in in-game hours
  (default 8, 0 disables drain), a blade damage multiplier (default 1.0), and Extinguish While
  Running (default on). The multiplier is
  applied to each blade as it ignites, so debug-spawned blades keep base damage. Five toggles
  control what a swing cuts through: Destroy Doors and Windows (default on), Destroy Non-Player
  Walls (default off), Destroy World Objects (default on), Destroy Player-Built Objects (default
  off), and Instant Chop / Clear Vegetation (default on), plus a Cut Effect choice (Destroy or Set
  on Fire). Deflecting gunfire has its own: Deflect Bullets (on), Deflect Chance at No Skill / Full
  Skill (10 / 80%), Deflected Bullets Hit the Shooter (on), Soak Shotgun Blasts (on), Blast Soaked at
  No Skill / Full Skill (10 / 50%), and Whole Blast Blocked at Full Skill (60%). Blocking photon
  swords has Guard Blocks Photon Swords (on), Block Chance at No Skill / Full Skill (30 / 90%), NPC
  Block Chance (35%), and NPC vs NPC Block Chance (20%).
- **Cutting**: on each swing of an ignited blade, `client/PhotonSword/PS_Swing.lua` sends a `cut`
  command with the player's facing; `server/PhotonSword/PS_Cutting.lua` cuts one door, window, wall,
  or fence on each edge faced, one object standing in the square in front, and fells trees and
  clears bushes and tall grass on the player's square and the one in front. Removal goes through
  vanilla's sledgehammer code, and objects it refuses (floors, water, curbs, litter) are skipped.
  Map objects follow their category's option; anything player-built (`IsoThumpable`) follows
  Destroy Player-Built Objects. The Cut Effect option (default Destroy) can instead set targets
  on fire with `IsoFireManager.StartFire`: on the far side of an edge, or in the square in front,
  never on the player's own square. Other players' safehouses are never cut. The server ignores cut
  commands faster than one per 300 ms per player.
  Each cut plays vanilla's break sound for what was cut (door and player-built break sounds,
  `SmashWindow`, furniture breaks matched to material, `BreakPlant`/`RemovePlant`; trees play
  their own `FallingTree`), broadcast from the server in multiplayer.
  Cutting is off for each player until they turn it on with the Toggle Cutting hotkey (X by
  default, only while an ignited blade is held, saved in player modData as `PS_cutting`).
- **No blood**: `shared/PhotonSword/PS_NoBlood.lua` resets a held ignited blade's blood level to 0
  on each player update, since vanilla bloodies any weapon that hits and has no script switch.
- **Sound** (`media/scripts/sounds_photonsword.txt`): ignite, extinguish, three swing variants, two
  spark hit variants (used for zombie, door, floor, and other impacts), and a looping hum that
  plays while a blade is lit and fades out during swings (`client/PhotonSword/PS_Hum.lua`). Mod
  options set hum volume, plus tone (Smooth, Classic, Gritty) and pitch for the hum, the swing, and
  the hit. The hum is re-pitched live; swings and hits are pre-rendered at 70-130% in steps of 10,
  since the game plays them by name. The audio and the
  sound script are both generated by `tools/gen_sounds.py` (numpy + ffmpeg); edit and re-run it
  instead of editing the script by hand.
- **Models and icons** (`models_X/weapons/`, `textures/`, `scripts/models_photonsword.txt`): a hilt
  model and a hilt-plus-blade model, a blade texture per palette color, and one 32x32 hilt icon
  shared by both items (so the icon doesn't change on ignite), all
  generated by `tools/gen_models.py` (numpy + Pillow; `--preview DIR` also writes OBJs for
  Blender). The meshes copy vanilla Katana's orientation and attachment points.
- **Blade color**: a Blade Color mod option (eight palette colors, Blue by default). The
  igniting player's choice is stored on the blade (`PS_color`) and sets its model and light. Adding a color means adding it to
  both `PALETTE` in `gen_models.py` and
  `PS.BLADE_COLORS`/`PS.COLORS` in `PS_Core.lua`.
- **Stance** (`client/PhotonSword/PS_Stance.lua`, `media/AnimSets/player/*/PS_*.xml`,
  `common/media/anims_X/PS/`): an ignited sword held in both hands gets the mod's own idle, walk,
  and aim animations, over vanilla's two-handed ones. They read only the mod's variables
  (`PSHolding`, `PSGuard`, `PSBeckon`, `PSParry`, `PSHiltBeckon`, `PSWalking`, `PSFemale`), set for local players
  every update and for remote ones every few ticks. Another mod whose own animation takes the sword
  over adds a yield (`PS.addStanceYield(fn)` in `PS_Core.lua`): while `fn(playerObj)` is true the
  stance stays out, the ready stance doesn't guard against gunfire, and running doesn't put the
  blade out. Photon Sword Forms yields for its block, and whenever the ignited sword is held with no
  Form enabled, so the sword behaves as the game's default two-handed katana.
- **Ready stance**: aiming with the ignited sword (standing or strafing) plays `PS_Ready`, a relaxed two-handed ready guard after Obi-Wan Kenobi's: a wide
  stance on bent knees, left foot forward, shoulders square; both fists on the hilt low, the pommel a few inches in front of the sword hip (the sword,
  back hand at the bottom toward the pommel, its elbow out to the side, the off, fore hand above it,
  its forearm across the stomach), the arms untwisted and clear of the body, and the blade pointing
  straight ahead, its tip toward the cursor (which the character faces while aiming), rising 45
  degrees. It breathes (the chest rises, the shoulders lift, the body settles). Now and then, standing still in it, the off hand lets go of
  the hilt, lifts ahead palm up, beckons twice, and returns (`PS_ReadyBeckon`): every 3 seconds
  in the stance, a Beckon Chance roll (10% by default; `PS_Stance.lua` sets `PSBeckon` for the clip's length; each client
  rolls for the players it animates, so in multiplayer others may see it at a different moment).
  Aiming an extinguished hilt (vanilla's one-handed aim) gets the same beckon with the free off hand
  (`PS_AimBeckon`, `PSHiltBeckon`).
  When the ready stance's guard blocks a photon sword's strike, it parries (`PS_Parry`, 0.9 s): both
  hands sweep the sword up into a high cross-guard in front of the face, the blade across the body
  with its edge out; the blow drives the guard back toward the face and the body rocks back and sinks
  into the knees, feet planted; then the guard pushes back out and settles into the ready stance.
  Each client that shows the block (the "Blocked" text and spark) notes it (`PS.noteParry`), and
  `PS_Stance.lua` sets `PSParry` while the clip plays. An NPC whose photon sword blocks a strike
  (the patch mods) plays the same parry, through the zombie `bumped` state: `PS.playNpcParry` sets
  its BumpType to `PSParry` (the `zombie/bumped/PS_parry.xml` AnimSet), as Bandits plays its own
  NPCs' actions; Project A-Life's patch plays it as an A-Life animation preset instead.
  Walking in it plays `PS_ReadyWalk`: vanilla's aiming walk tips the pelvis forward, which pitched
  the stance's upper body to about 20 degrees, so the walking copy leans it back by a quarter.
- **High guard** (`PS_Guard`, not played or shipped; the aim stance before `PS_Ready`, kept in `tools/anim/make_guard.py` to switch back
  to in `tools/gen_animsets.py`): a one-handed high guard after Obi-Wan Kenobi's: side-on, the off shoulder
  leading; the sword arm's upper arm level with the shoulders, reaching forward and out, the
  forearm carrying on forward and up from an elbow bent about 30 degrees to a fist at eye height
  ahead of the face, the palm turned out and down, and the blade held level above the shoulders,
  pointing ahead (toward the cursor, which the character faces while aiming) and across toward the
  off side. The off arm reaches ahead toward the target,
  elbow relaxed, palm up, beckoning (the fingers curl in twice, then rest open, over each
  2.6-second breath).
- **Rest stance**: not aiming, with the ignited sword, the player holds it in the sword
  hand only, the blade angled low (down, forward, and out from the leg) and the off hand free.
  Standing and sneaking idles (`PS_Rest`, `PS_RestSneak`) breathe like the guard, with the off
  hand relaxed at the side. Walking and sneak walking (`PS_Walk*`, `PS_WalkSneak*`) are vanilla's
  one-handed walks, the off arm swinging, with the sword wrist holding the blade low. They're
  `idle` and `movement` nodes on `PSHolding` that outrank vanilla's two-handed ones, and the walks
  keep vanilla's speed and limp blending and footsteps. Turning in place plays vanilla's turn on
  the legs under the rest. The low sneak against a wall and walking in trees keep vanilla's
  two-handed animations.
- **Running and sprinting** (`client/PhotonSword/PS_RunExtinguish.lua`): starting to run or
  sprint with a lit photon sword extinguishes it through the toggle action, so the run plays
  vanilla's one-handed run with the hilt; when the run ends the blade relights in its color. A
  sword lit again by hand mid-run stays lit, one put away mid-run isn't relit, and an empty battery
  doesn't relight. The Extinguish While Running sandbox option (on) turns it off.
- **Deflecting bullets** (`shared/PhotonSword/PS_Deflect.lua`, `client/PhotonSword/PS_DeflectShow.lua`):
  with the guard up (the ready stance: aiming the ignited sword in both hands) and the shooter in
  front of it (within about 75 degrees either side), a bullet has a chance to be turned back on
  whoever fired it. Both bullets and shotgun blasts go by guard skill (`PS.guardSkill`): the Long
  Blade level / 10. A bullet's chance slides from 10% to 80% with it (the sandbox's Deflect Chance
  options). Nothing drains. The defender hears the blade's hit spark and sees "Deflected" (the
  Deflect Spark Sound and Show Deflect Text mod options).
  - **Guard hooks**: another mod can change what the guard is by replacing `PS.guardUp`,
    `PS.guardFacing`, `PS.guardSkill`, `PS.guardDrain`, `PS.drainGuard`, and `PS.guardPays`. Photon
    Sword Forms makes it a Form's Martial Arts Core block, with mastery and Martial Arts for skill and
    Core's guard meter to drain (one the meter can't pay for breaks the guard and the shot lands).
  - **Shotguns** (Soak options): a spread is too wide to send back, so the guard soaks part of the blast
    instead: 10% of its damage with no skill, sliding up to 50% at full skill, and at full skill
    there's also a 60% chance it takes the whole blast ("Blocked"; otherwise "Absorbed N%"). With a
    guard meter (Photon Sword Forms), it pays that share of the drain, or the guard breaks and the
    blast lands in full. Nothing goes back to
    the shooter. Vanilla's pellets each hit separately, so each is stopped with the soaked share's
    chance (the blast's damage drops by that share on average); Bandits lands a blast as one hit, so
    the hit lands and the soaked share of what each body part lost is given back.
  - **Other players' guns** (multiplayer): the server decides from `OnWeaponHitCharacter`. It cancels the bullet's damage,
    gives the shooter a bullet wound (synced with `sendDamage`), and tells every client to play the
    spark. The shooting client may still show its own hit effect for a moment.
  - **Blocking photon swords** (Block options): the raised guard also stops a photon sword's strike
    from in front, another player's or an NPC's, by `PS.blockChance` (30% to 90% by guard skill), and
    pays `PS.guardDrain` like a deflection. It shows "Blocked" and the spark. Players' strikes on
    players are settled on the server (or in single player) from `OnWeaponHitCharacter`; NPCs'
    strikes come in from the patch mods through `PS.judgeBlow` (where the guard is settled) and
    `PS.judgeLocalBlow` (a client asking the server with a `deflect` command). Photon Sword Forms
    makes a Form's block always hold while the meter pays, and leaves player-on-player strikes to
    Martial Arts Core's own block (`PS.meleeGuardHandled`). An NPC holding a lit photon sword, on its
    feet and facing the player, blocks a player's photon sword strike at NPC Block Chance
    (`PS.npcBlocks`, one roll per strike, with the spark at the NPC); a vanilla hit is avoided on
    the attacker's client, and Project A-Life's own hit weighing asks the same roll. NPCs' sword
    strikes at each other are blocked the same way at NPC vs NPC Block Chance (20%), from the patch
    mods (`PSB_Duel.lua`, `PSA_Duel.lua`); a block the server settles is sent to clients as an
    `npcBlock` command for the spark.
  - **NPC mods** are covered by patch mods in this repo, which also arm their NPCs with photon
    swords. Both keep the same features ([NPC patch feature set](docs/NPC_PATCHES.md)).
  - **Bandits**: covered by a separate patch mod in this repo, **Photon Sword - Bandits**
    (`PhotonSwordBandits/`, id `PhotonSwordBandits`). Bandits shoot on the client that runs
    them, through `PlayerDamageModel.BulletHit`, which the patch (`client/PhotonSwordBandits/PSB_Deflect.lua`)
    wraps. For a local player, that client rolls (`PS.judgeLocalShot`). It then hits the bandit back
    with the weapon, syncing the bandit's health the way Bandits does, or soaks a blast. In multiplayer
    it sends a `deflect` command so the server settles the guard (drains a Form's meter or breaks its guard).
    A bandit's sword strike goes through `PlayerDamageModel.MeleeHit`, also wrapped, into
    `PS.judgeLocalBlow`; a blocked strike deals nothing, and Bandits' pain cry and splash after it
    are muted.
  - **Project A-Life**: covered by a separate patch mod in this repo, **Photon Sword - Project A-Life**
    (`PhotonSwordALife/`, id `PhotonSwordALife`). A-Life's NPCs don't shoot through the
    game's weapon hits, so `OnWeaponHitCharacter` never sees them. Every way A-Life wounds a player
    ends in `ProjectALife.Wounds.damagePlayer`, so the patch (`server/PhotonSwordALife/PSA_Deflect.lua`)
    wraps it. It also wraps the three callers that lead there (`Combat.resolveAttack`,
    `ModuleGunner.grazePlayer` and `Executor.woundPlayer`) to note who fired. It then calls
    `PS.judgeShot` for the roll and the guard. A stopped shot reports itself as landed, so
    A-Life doesn't apply its flat fallback damage, and its pain cry is muted. A soaked blast gives
    back its share through `PS.soak`. A deflected bullet hits the NPC through A-Life's own
    `HumanDamage.apply`. It runs in single player or on the server, and logs which hooks it
    installed. An NPC's sword strike lands through the same calls and meets the guard through
    `PS.judgeBlow`. A player's strike on an A-Life NPC is weighed by A-Life itself
    (`AIFence`'s `Fence.weighBlow`); `shared/PhotonSwordALife/PSA_Block.lua` wraps its
    `Fence.shield` so the NPC's sword block counts like armor that stopped the blow.
  Players usually run one NPC mod at a time. With both, a bandit's sword blocks an A-Life NPC's
  strike, but an A-Life NPC's strike at a bandit can't be blocked (A-Life hits bandits as plain
  zombies); both patch descriptions say so.
  Both patches require only Photon Sword (and Bandits or Project A-Life), and work with Photon Sword
  Forms too. `deploy.sh` deploys them alongside the mod.
- **NPCs with photon swords**: each patch also arms its NPCs. An NPC with a melee weapon carries an
  ignited photon sword at the patch's Photon Sword Chance (default 2%), rolled once per NPC, in a
  color from its NPC Blade Color option. Bandits' patch wraps `Bandit.ApplyVisuals`, `Bandit.SetHands`,
  `Bandit.UpdateItemsToSpawnAtDeath` and `BanditCompatibility.InstanceItem` (`PSB_Arms.lua`);
  A-Life's wraps `ProfileHydrator.plan` and `apply` (`server/PhotonSwordALife/PSA_Arms.lua`) and keeps
  the swords out of A-Life's mod loot scan (`PSA_ModLoot.lua`). Photon Sword supplies the shared parts in
  `PS_Core.lua`: `PS.stableRoll` and `PS.npcBladeColor` for the roll and color, `PS.issueNpcBlade` to
  ready a blade (damage multiplier, color), and `PS.forEachNpcHolder`, which finds every zombie
  holding a photon sword. NPCs carry it dark and light it only for a fight: each patch reports when
  its NPCs fight or close in (`PS.addNpcCombatSource`; `PSB_Combat.lua`, `PSA_Combat.lua`), and
  `client/PhotonSword/PS_NpcBlades.lua` swaps the held blade's model between the hilt and the lit
  blade, with the ignite and extinguish sounds, putting it out 4 seconds after the fight. The item
  stays the blade, so the NPC mod's AI and damage never change. The light, hum, and no-blood code
  covers lit NPC blades (`PS.forEachNpcWielder`).
  `PS_PowerDrain.lua` fits a 20-60% battery to a batteryless blade a player picks up. The features
  both patches must keep are in [NPC patch feature set](docs/NPC_PATCHES.md).
- **Dev kit**: see [Development notes](#development-notes).
- **Placeholders**: equip and unequip sounds still borrow vanilla Katana's. Other constants live
  in `shared/PhotonSword/PS_Core.lua`.

## Built with

**Game and mod runtime**

- [Project Zomboid](https://projectzomboid.com/) Build 42: the mod targets its Lua API, events,
  timed actions (`ISBaseTimedAction`), `PZAPI.ModOptions`, sandbox options, and client/server
  commands.
- Lua 5.1 (the game's Kahlua VM) for all mod logic.
- PZ script files for items, models, and sounds, `sandbox-options.txt`, and JSON translations.
- DirectX `.x` (text) meshes and PNG textures/icons for the 3D models.
- FMOD, through the game's sound scripts: Ogg Vorbis one-shots and WAV loops.

**Asset generation** (`tools/`)

- Python 3.14 runs the generators.
- NumPy 2.3 handles mesh geometry in `gen_models.py`, and sound synthesis and FFT filtering in
  `gen_sounds.py`.
- Pillow 12.1 draws the textures and icons, and `gen_art.py` paints every mod's Workshop preview
  (256x256), mod list poster (256x256), and icon (32x32): a stylized ignited sword built from the
  hilt model's profile and paint, in the default blade color (`--color` picks another).
- FFmpeg 8.0 with libvorbis encodes the Ogg sound effects.
- Blender 5.0 previews the generated meshes (`gen_models.py --preview` writes OBJs).
- `tools/anim/` authors the stance clips from vanilla's animations (NumPy; `xfile.py` reads and
  writes the text `.x` format, `animlib.py` holds the pose, IK, breath, and clip writer), and
  `tools/gen_animsets.py` writes their AnimSets. Blender renders poses (`tools/anim/render.py`).

**Development and testing**

- `luac5.1` (Lua 5.1.5) syntax-checks every Lua file; Python's `json.tool` validates the
  translations.
- The community [Unofficial PZ JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/)
  (Build 42.20) are the reference for the Java API's classes and method names, and
  [PZwiki](https://pzwiki.net/) for `mod.info` and `workshop.txt`.
- The vanilla Lua and translations under `projectzomboid/media/lua/` are the reference for API
  usage and patterns, and for the Workshop uploader's rules (its error messages).
- rsync copies the mod into `~/Zomboid/mods` (`deploy.sh`).
- Git handles version control, with tags per release.
- [Claude Code](https://claude.com/claude-code) (Anthropic) helped write the code, assets,
  and tools.

## Stance animation tools

Clips must live under `common/`: the game skips a mod's `42/media/anims_X` entirely unless
`common/media/anims_X` exists (`ModelManager.loadHumanAnimations`). Each tool reads vanilla's clips
from the installed game (`--pz` to point elsewhere) and writes to `common/media/anims_X/PS/`.
Photon Sword Forms' `make_block.py` and `make_dodge.py` import `xfile` and `animlib` too.

- `tools/anim/make_ready.py` builds `PS_Ready.x` from vanilla's two-handed aim (`Bob_IdleAimBat`,
  left foot forward), spreading the feet by `WIDEN`, sinking the body by `CROUCH`, and turning the
  shoulders by `TORSO_TURN` (0 now; the head turns back to face ahead). The sword hand
  holds the hilt with the rests' grip (`make_rest.py`) slid toward the pommel (`SWORD_AT`); the off
  hand's grip is its mirror image across the hilt, `SPACING` above it toward the emitter. (With the
  hands the other way round, the sword elbow can't be drawn back: the off hand would sit inside the
  belly.)
  `GRIP_TILT` lays the hilt diagonally across both palms and `OFF_ROLL` turns the off fist about the
  hilt. The sword fist sits at `FIST` from the head bone with the blade along `BLADE`, the sword palm
  turned to `SWORD_PALM`, and the elbows toward `SWORD_ELBOW` and `OFF_ELBOW`. Its arm solver
  (`solve_arm`) bends each elbow only on its hinge, as vanilla's do, so the arms don't twist (the
  generic `solve_limb` in `animlib.py` aims bones by the shortest turn and can roll the forearm
  90 degrees or more). The values were chosen together by an optimizer to keep each wrist close to
  its resting set on the forearm (vanilla's `Bob_Idle`), the arms clear of the torso, the blade
  straight ahead toward the cursor and no steeper than 45 degrees, and the pommel 2 to 4 inches (0.03 to 0.055 units) from the sword hip. It
  prints how far the feet slide and the hands slip, how far each arm clears the torso (an elbow
  tucked against the chest clips through it in game), and each wrist's twist and swing from rest
  (vanilla's idles stay within about 27 and 40 degrees) and elbow angle. It also writes
  `PS_ReadyBeckon.x`, the ready pose with the off hand lifted to beckon (`BECKON_*`: where it
  reaches, the palm turned mostly up with the elbow tucked in so the wrist keeps its resting twist,
  the finger curls, and the elbow swinging out on the way so the forearm clears the stomach), and
  `PS_ReadyWalk.x`, the pose with the spine leaned back so its lean over vanilla's aiming walk
  (`WALK_LEGS`) drops by `WALK_LEAN` (the game plays the stance's spine and above over the walk's legs).
- `tools/anim/make_parry.py` builds `PS_Parry.x` from `make_ready.py`'s pose, grips, arm IK, and
  breath, so it leaves and rejoins the ready loop exactly. `GUARD_*` and `EDGE_ROLL` place the
  cross-guard (where the sword fist sits from the head, the blade's direction, each elbow's pole),
  `RECOIL*`, `BODY_ROCK`, and `BODY_SINK` shape the impact, and `PATH_ARC` and `OFF_SWING_OUT` keep the
  off forearm clear on the sweep. It prints how closely it joins the loop, how far the feet slide and
  the hands slip, each arm's clearance from the torso, and how close the blade comes to the head.
- `tools/anim/make_aim_beckon.py` builds `PS_AimBeckon.x`: vanilla's one-handed aim
  (`Bob_IdleAim1Hand`) with the off hand doing the ready stance's beckon (`make_ready.py`'s
  `BECKON_*`), easing from vanilla's arm onto the solved one over `EASE` of the lift.
- `tools/anim/make_guard.py` builds `PS_Guard.x` from vanilla's one-handed aim (`Bob_IdleAim1Hand`,
  left foot forward), turning the shoulders by `TORSO_TURN` (the head turns back to face ahead). It
  holds the hilt with the rests' grip (`make_rest.py`), the fist at `FIST` from the head bone with
  the blade along `BLADE`, the palm turned to `SWORD_PALM`, and the elbow toward `SWORD_ELBOW`. The
  grip ties the palm to the blade, so the blade's angle is tuned with the palm to keep the wrist
  natural: with the upper arm level, the elbow open and the blade level, the palm faces out and
  down and the wrist bends about 20 degrees (palm in, 90 or more). It places the off hand along `REACH` at `REACH_FRACTION` of the arm's length (so the elbow
  bends), fingers along `OFF_FINGERS`, palm along `OFF_PALM`. The beckon curls the off hand's finger
  bone by up to `CURL_DEGREES` and lifts the wrist by `WRIST_DEGREES`, twice per loop (`BECKON` of
  the loop each). It prints each wrist's bend and elbow angle and how far the hilt clears the head;
  the arms are short (about 0.27 from shoulder to wrist), so targets sit close to the body.
- `tools/anim/make_rest.py` builds the rests the same way (`RESTS`), from vanilla's one-handed
  idles (`Bob_IdleNoAim1Hand`, `Bob_IdleSneak`), whose off arm already hangs at the side. It holds
  the hilt along vanilla's fist (`GRIP_TILT` can turn it in the palm, but past about 10 degrees it
  pokes out under the wrist in game) with the middle of the fist at `GRIP_AT` along the hilt
  (halfway; it measures where the hand's skin sits on the hilt), turns the
  wrist so the blade points `down` below level and `out` to the side, moves the hand by `shift`,
  and adds the guard's breath. The walks (`WALKS`) are vanilla's one-handed walks with the wrist
  turned on every keyframe to keep the rest's blade angle (following `WALK_SWING` of the arm's
  swing) and the hilt set in the hand. For each clip it prints the lowest blade tip (for a
  `BLADE_LENGTH` blade), the blade's closest pass to the sword leg's bones, and the wrist bend
  range (vanilla's resting bat bends about 27 degrees; the standing rest bends 40), and for each rest how far the hilt drifts from the
  hand over vanilla's turns.
- `blender -b --python tools/anim/render.py -- CLIP.x OUT --blade y` renders any clip's first
  frame to `OUT_front/side/three/quarter.png` with a stand-in blade, so a pose can be checked without
  the game. `--prop PhotonSword_Hilt.x --zoom` draws the real hilt instead, close up, to check
  that it sits in the fist. `tools/anim/xfile.py` reads and writes the text `.x` format. The tools need `numpy`.
- `tools/gen_animsets.py` rewrites the stance AnimSets from its `STANCES`, `WALKS`, and `STATES`
  tables. Re-run it after changing them.

Known gaps:

- The stances haven't been seen in-game yet. Tune the rests and walks in `tools/anim/make_rest.py`.
- The low sneak and walking in trees still use vanilla's two-handed carry. (Running and sprinting
  put the blade out, so they play vanilla's one-handed run with the hilt.)
- While turning in place the hilt drifts up to about 5 cm from the hand (the weapon bone hangs
  off the root, not the hand, and the turn moves the spine under the arm), as vanilla's bat does.
- The heavy left limp walk bends the sword wrist about 50 degrees (vanilla's limp holds the hand
  on the hip).

## Development notes

- **Deploy and dev kit.** `./deploy.sh` copies the mod, Photon Sword Forms, and both patch mods into
  `~/Zomboid/mods`, plus the dev kits (`dev/PS_DevKit.lua` and `dev/PSF_DevKit.lua`, outside the mod folder so it never ships);
  `./deploy.sh --release` leaves the kits out. Each character gets the kit once on spawn: a charged,
  ignited photon sword in both hands, two spare batteries, and Long Blade 10 (the guard skill for
  deflecting gunfire). Change its `KIT` table to adjust it, bump `KIT.version` to give it again to
  existing characters, or run `PSDevKit.give(getPlayer())` in the debug Lua console. Single player
  only. Photon Sword Forms' kit adds the Forms and Martial Arts.
- **A-Life duel** (`dev/PSA_DevKit.lua`): `PSDevKit.duel()` in the debug Lua console spawns two
  A-Life NPCs a few tiles either side of you, hostile to each other and neutral to you, each with
  only a lit photon sword (blue and red), so they fight at once. It uses A-Life's own spawner with
  group warfare on, and strips their guns as A-Life builds their loadout. Options:
  `PSDevKit.duel({ profileId = "...", distance = 4, mode = "hunt" })`. `PSDevKit.duelists()` lists
  them; `PSDevKit.endDuel()` removes them from A-Life's registry (as its admin squad delete does), so
  A-Life doesn't restore them, and `PSDevKit.duelActorCount()` says how many it still has.
- **In-game tests** (`dev/*_DevKitTest.lua`): `PSTest.run()` in the debug Lua console runs every
  suite for the mods that are loaded (Photon Sword, Forms, A-Life, Bandits); `PSTest.run("forms")`
  runs only suites whose name contains the text, and `PSTest.list()` lists them. Results print to
  the console, show over the player, and go to `Zomboid/Lua/PhotonSwordTests.log`. Tests run one
  at a time on `OnTick`, so they can wait on the game (an NPC blade lighting up, a battery draining
  over an in-game minute, the A-Life duel); the whole run takes a few minutes. They spawn docile
  zombies next to you, set sandbox options, stub the guard up, and undo all of it afterwards,
  healing you if a test hurt you. Run them in a test save, standing in the open. A new mod's suite
  goes in `dev/` as another `*_DevKitTest.lua`, added to `deploy.sh`.
- **Reference vanilla scripts.** Vanilla weapon definitions live in
  `~/.steam/steam/steamapps/common/ProjectZomboid/projectzomboid/media/scripts/generated/items/weapon.txt`.
  `item Katana` is the baseline for stats (`MinDamage`, `MaxDamage`, `MaxRange`,
  `CriticalChance`, `SwingAnim = Bat`, `TwoHandWeapon = true`, and so on).
- **Vanilla Lua.** Lives under `.../projectzomboid/media/lua/` and is the best reference for
  the event and API usage the game actually runs.
- **Debug mode.** Launch with `-debug` to spawn items, reload Lua, and read errors in the
  console (`~/Zomboid/console.txt`).
- **Common pitfalls.** The `id` in `mod.info` must match whatever references the mod. Build 42
  needs both `42/` and `common/` folders. Lua syntax errors fail silently in-game, so check
  `console.txt`.
- **Conventions** every mod and patch here follows (check new code against them):
  - `mod.info`: `id` matches the folder; `require` and `loadModAfter` list every mod it depends on
    or patches, in B42's form (`\ModId`, comma separated).
  - Globals: only the mod's namespace tables (`PhotonSword`, `PhotonSwordForms`, the options tables,
    and the `ISPhotonSword*` timed actions); everything else is `local`. Lua files live under a
    folder named for the mod (`client/PhotonSword/...`), so they can't shadow another mod's file of
    the same name.
  - Client, server, shared: code a dedicated server runs never requires a `client/` file or touches
    UI; files under `server/` also return early on a client; every client and server command
    checks its module, arguments, and rate.
  - Wrapping someone else's function (vanilla's, or another mod's): keep the original, call it with
    every argument (`...`), and return everything it returned (`PS.pack`, then
    `unpack(results, 1, results.n)`), so other mods wrapping the same function, and future versions
    of it, still work. Install wrappers of another mod's functions on `OnGameStart` /
    `OnServerStarted` when that mod's tables may not exist yet at load, and print one
    `[ModId] ... patched` line, or what wasn't found.
  - Translations: a literal `%` is written `%%` (the game formats every string, so `(%)` or `10% a`
    breaks it); arguments are `%1`, `%2`.
  - Sandbox options: named `<ModId>.<Option>` on the mod's own page, each with a label and tooltip,
    and enum value labels (`valueTranslation`).
  - Item scripts: every sound, model, and texture named exists (the game's, or the mod's own).
  - Ship only what's used: no unused clips, textures, or sounds, and no dev kit (`release.sh`
    refuses `*DevKit*` files).
  - Logging: `print("[ModId] ...")` for install results and real problems only, never per tick.

## Releasing to the Steam Workshop

Each mod is its own Workshop item, uploaded with the game's in-game uploader. `release.sh` builds
only what ships into `releases/` (gitignored), so the generators, dev kits, and docs never reach
Steam.

1. **Bump versions.** Raise `modversion=` in the `42/mod.info` of each mod that changed, and
   update its `workshop.txt` and `mod.info` descriptions to match. Commit.
2. **Build.** Run `./release.sh` (or `./release.sh PhotonSword PhotonSwordForms` for just some
   mods). For each mod it checks what the uploader checks: a 256x256 `preview.png` of at most
   1000KB (the limits in the uploader's own error messages), `Contents/` holding only `mods/<ID>`, both `42/` and `common/`, no
   `id=0` (the uploader takes `0` for a real item id). It also checks the `mod.info` id, poster and
   icon, that no Python, Blender file, or dev kit is inside `Contents/`, and the syntax of every
   Lua (`luac5.1 -p`) and JSON file. It warns if the tree has uncommitted changes. If every check
   passes, it copies `workshop.txt`, `preview.png`, and `Contents/` (without `.gitkeep`) to
   `releases/<ID>/`. Set `WORKSHOP_DIR` to build elsewhere.
3. **Upload.** The game's uploader lists only folders in `~/Zomboid/Workshop/`, so copy each
   `releases/<ID>` folder there (`cp -r releases/<ID> ~/Zomboid/Workshop/`). Start the game with
   Steam running. From the main menu, choose Workshop > Create and update items, pick the mod,
   and upload. Each `workshop.txt` sets
   `visibility=private`, so new items stay hidden until you change their visibility on Steam.
4. **Record the item ids.** The first upload of a mod writes its new `id=` into the uploaded
   `workshop.txt`. Copy that file back to `releases/<ID>/` (or set `WORKSHOP_DIR=~/Zomboid/Workshop`),
   run `./release.sh --sync-ids` to copy each new id into the repo, then commit it, so later
   uploads update the same item. Until you sync, `release.sh` keeps an id in `releases/` that the
   repo lacks, so a rebuild doesn't create a duplicate item.
5. **Tag.** Tag the release commit (for example `git tag photonsword-v0.1.0`) and push it with
   the branch.

Upload Photon Sword before the mods that require it. After the first upload, each mod's Workshop
page can list the others as required items.

## Resources

- [gotmayonase/pz-modding-guide](https://github.com/gotmayonase/pz-modding-guide): current
  Build 42.15+ guide covering mod structure, item scripting, Lua, multiplayer, and testing
- [FWolfe/Zomboid-Modding-Guide](https://github.com/FWolfe/Zomboid-Modding-Guide): the classic
  comprehensive guide with Lua API, events, and models (some parts predate Build 42)
- [PZwiki: Mod](https://pzwiki.net/wiki/Mod): community wiki modding pages
- [Supercraft: Build a Project Zomboid mod](https://supercraft.host/wiki/project-zomboid/build_a_project_zomboid_mod/):
  walkthrough of `mod.info`, Lua, and a sample layout
- [PZfans: Build 42 modding, what works and what's broken](https://pzfans.com/build_42_modding_what_works_what_s_broken_and_what_s_worth_it)
- [Clothing mod tutorial](https://www.gamenguides.com/how-to-create-a-clothing-mod-in-project-zomboid):
  a good worked example of wiring a 3D model (`WorldStaticModel` and model scripts)
- The Indie Stone Discord, `#mod_development` channel

## Third-party content

Thanks to The Indie Stone for creating [Project Zomboid](https://projectzomboid.com/), which made
this possible. This is an unofficial fan production for non-commercial purposes made under the
[Indie Stone Terms](https://projectzomboid.com/blog/support/terms-conditions/).

What the mods take from elsewhere, and on what terms:

| Content | Where it comes from | Terms |
|---|---|---|
| The stance, guard, parry, block, and dodge clips (`anims_X/PS/*.x`, `anims_X/PSF/*.x`) | Authored by `tools/anim/` from vanilla's animations; each file carries vanilla's character skeleton and mesh, as the game's own clips do | The Indie Stone's Terms (2.1, 2.2): non-commercial, with the credit above |
| AnimSets, scripts, and Lua patterned on vanilla's | Project Zomboid's `media/` | The Indie Stone's Terms (2.1) |
| Form 1's attack clips | Senator's Martial Arms, loaded from Senator's mod (not copied) | Senator's |
| Parts of Photon Sword Forms' Lua | Adapted from Senator's katana art ([Credits](docs/PhotonSwordForms.md#credits)) | Senator's |
| Text on the Form manual textures | Rendered with the DejaVu fonts (not shipped) | [DejaVu license](https://dejavu-fonts.github.io/License.html) (free use, including in images) |
| Sounds, models, textures, icons, and Workshop art | Generated from scratch by `tools/` | This repo's MIT License |

The tools are run, not shipped: Python, NumPy (BSD), Pillow (MIT-CMU), FFmpeg with libvorbis
(LGPL/GPL and BSD; the encoded sounds carry no license terms), and Blender (GPL; the Blender
scripts here are MIT, which is GPL-compatible, and renders are unrestricted). No mod sells
anything or asks for donations, as the Terms require.

## License

Every mod in this repo (Photon Sword, Photon Sword Forms, and both patch mods) and its tools are
released under the [MIT License](LICENSE). Copyright (c) 2026 Dustin Hittenmiller. The exceptions,
which aren't this repo's to license, are listed under [Third-party content](#third-party-content):
The Indie Stone's content in the animation clips (vanilla's skeleton, mesh, and the motion the
clips are built from), and the parts of Photon Sword Forms' Lua adapted from Senator's Martial
Arms.
