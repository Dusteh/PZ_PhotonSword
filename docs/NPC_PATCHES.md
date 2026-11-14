# NPC patch feature set

Photon Sword ships one patch mod per NPC mod: **Photon Sword - Bandits** (`PhotonSwordBandits`) and
**Photon Sword - Project A-Life** (`PhotonSwordALife`). Every NPC patch must offer the same features,
with the same option names and the same defaults, so a player gets the same photon sword whichever
NPC mod they run. This page is that contract. When a feature changes in one patch, change it in
every patch and update this table in the same commit. A new NPC patch starts from the checklist at
the end.

Shared behavior lives in Photon Sword itself (`PS_Core.lua`, `PS_Deflect.lua`, `PS_PowerDrain.lua`,
and the client effects), so a patch only hooks its NPC mod and calls those helpers. Keep it that
way: if two patches need the same logic, move it into Photon Sword.

## Features

| # | Feature | Contract | Bandits | Project A-Life |
|---|---|---|---|---|
| 1 | **Guard deflects NPC bullets** | A shot from an NPC at a player whose guard is up (the ready stance, or a Form's block) is rolled by `PS.judgeShot` / `PS.judgeLocalShot`, with Photon Sword's Deflect sandbox options. A deflected bullet never lands. | `PlayerDamageModel.BulletHit` wrapped (`PSB_Deflect.lua`, client) | `Wounds.damagePlayer` and its three callers wrapped (`PSA_Deflect.lua`, server) |
| 2 | **Deflected bullets strike back** | With Deflected Bullets Hit the Shooter on, the bullet hits the NPC through the NPC mod's own damage, so its health and hit reactions apply. | Hit with the weapon; health synced as Bandits syncs a client hit | A-Life's `HumanDamage.apply` |
| 3 | **Shotgun blasts soaked** | A blast lands, and `PS.soak` gives back the soaked share (Soak sandbox options). | Yes | Yes |
| 4 | **Guard meter** | With Photon Sword Forms, each deflection or block drains the Form's guard meter, and an empty meter breaks the guard; in multiplayer the server settles it. | `deflect` command to the server | Settled on the server, where it runs |
| 4b | **Guard blocks NPC swords** | An NPC's photon sword strike at a player whose guard is up and faces it is rolled by `PS.judgeBlow` (with authority) or `PS.judgeLocalBlow` (on the client running the NPC), with Photon Sword's Block sandbox options (a Form's block always holds while the meter pays). A blocked strike deals nothing, and the NPC mod's pain cry and blood for it are muted. | `PlayerDamageModel.MeleeHit` wrapped; `PlayerVoiceSound` and `Splash` muted after a block (`PSB_Deflect.lua`, client) | Melee through the same `Wounds.damagePlayer` wrapper (`PSA_Deflect.lua`, server) |
| 4c | **NPC swords block players'** | An NPC holding a photon sword, lit, on its feet and facing the player, blocks the player's photon sword strike at Photon Sword's **NPC Block Chance** (`NpcBlockChance`, default 35) through `PS.npcBlocks`: one roll per strike, the spark at the NPC. Photon Sword avoids the vanilla hit itself (`OnWeaponHitCharacter`, the attacker's client); a patch whose NPC mod weighs player hits its own way asks `PS.npcBlocks` there too. | Automatic (bandits take vanilla hits) | `Fence.shield` wrapped so a block counts as armor stopping the blow, with `Fence.weighBlow` noting the wielder (`PSA_Block.lua`, shared) |
| 4d | **NPC swords block NPCs'** | An NPC holding a lit photon sword blocks another NPC's photon sword strike from in front at Photon Sword's **NPC vs NPC Block Chance** (`NpcVsNpcBlockChance`, default 20), through the same `PS.npcBlocks`. The blow is settled by the NPC mod's own "blocked" result where it has one, so no damage, hurt cry, or blood follows; the spark plays at the blocker (sent to clients when the server settles it). Works across NPC mods when the striker's mod runs the swing. | `ZombieActions.Smack.onWorking` wrapped: a blocked swing runs with the victim hidden from `BanditZombie.Cache` for that call (`PSB_Duel.lua`, shared; runs on the client running the bandit) | `HumanDamage.shielded` wrapped, with `HumanDamage.apply` noting the striker, so a block is A-Life's armor block (`PSA_Duel.lua`, server) |
| 4e | **NPCs parry** | An NPC whose photon sword blocks a strike (4c or 4d) plays the ready stance's parry, `PS_Parry`, once, where the block is decided: `PS.playNpcParry` sets its BumpType to `PSParry`, which Photon Sword's zombie `bumped` AnimSet (`PS_parry`) plays. Its own hit reaction to the blocked blow is held off until the parry ends. | Automatic (Bandits plays NPCs' actions by BumpType); its next swing waits in a wrapped `ZombieActions.Smack.onStart` until the parry ends (`PSB_Duel.lua`) | `ps_parry` registered as an A-Life animation preset and played with `Animations.apply`, which syncs it; `hit_react` and `HurtAnim.react` wait for it (`PSA_Parry.lua`, shared) |
| 5 | **NPCs carry photon swords** | An NPC whose loadout has a melee weapon (not bare hands) carries the ignited photon sword instead, at the patch's **Photon Sword Chance (%)** (`SpawnChance`, default **2**, 0-100). Rolled once per NPC with `PS.stableRoll` on a key that survives the NPC mod rebuilding the NPC, so it keeps the result. Only the side with authority rolls. | `Bandit.ApplyVisuals` wrapped; key: name + profile id; server / single player | `ProfileHydrator.plan` wrapped; key: actor uid; server / single player |
| 6 | **Authored swords honored** | An NPC profile that names `PhotonSword.PhotonSword` as its melee weapon keeps it whatever the chance. | Bandit Creator melee slot | Creator loadout melee slot |
| 7 | **Blade color** | **NPC Blade Color** (`BladeColor`, enum: Random (default), then the eight palette colors). Random is stable per NPC (`PS.npcBladeColor`). | Color set while Bandits makes the hand and corpse items | Set on the swords `ProfileHydrator.apply` added |
| 8 | **The blade is a real photon sword** | Every sword item the NPC holds, swings, or drops goes through `PS.issueNpcBlade`: Photon Sword's Blade Damage Multiplier and the blade color. The NPC mod's own melee AI and animations wield it, and its damage comes from the item. | `BanditCompatibility.InstanceItem` wrapped | `ProfileHydrator.apply` wrapped |
| 9 | **Lit only for a fight** | NPCs carry the sword dark (the hilt's model). It ignites, with the ignite sound, as soon as the NPC is fighting or closing in, and goes out, with the extinguish sound, 4 seconds after the fight ends. The patch only reports combat with `PS.addNpcCombatSource(fn)`; Photon Sword (`PS_NpcBlades.lua`, client) does the rest, and attacking always counts as fighting. The item stays the blade, so the NPC mod's AI and damage never change. | A "Smack" task, or within 6 tiles on its floor: a zombie, a player while hostile to players, or a bandit on the other side (`PSB_Combat.lua`, client) | `ALifeCombatPhase` is anything but `idle`, `none`, or `exit` (`PSA_Combat.lua`, client) |
| 9b | **Light, hum, clean blade** | While lit, clients light, hum, and keep clean the NPC's blade, with each player's own mod options. | Automatic (`PS.forEachNpcWielder`) | Automatic |
| 10 | **Lootable sword** | The NPC mod's own death drops leave the sword on the corpse. A player who picks it up gets a part-drained battery (20-60%) fitted, so it stays lit (`PS_PowerDrain.lua`). | Bandits' items to spawn at death | A-Life's death drops |
| 11 | **No back-door spawns** | The NPC mod's own automatic loot or weapon scans never hand out photon swords, so feature 5 is the only way an NPC gets one. | Nothing to exclude | Both item types excluded from ModLoot (`PSA_ModLoot.lua`) |
| 12 | **Sandbox section** | A section of the shared Photon Sword sandbox page (`page = PhotonSword`, registered with `PS.addSandboxSection`) with exactly `SpawnChance` and `BladeColor`, same labels, tooltips, ranges, and defaults. | Bandits NPCs section (`PSB_Sandbox.lua`) | Project A-Life NPCs section (`PSA_Sandbox.lua`) |
| 13 | **Load order and requirements** | `require=\PhotonSword,\<NPC mod>`; `loadModAfter=\PhotonSword,\PhotonSwordForms,\<NPC mod>` (B42 writes mod ids with a leading backslash); works with or without Photon Sword Forms. | `Bandits2` | `ProjectALifeNPCs` |
| 14 | **Art and docs** | Its own blade color and an emblem for the NPC mod, fused with the sword (`tools/gen_art.py`); `mod.info` and `workshop.txt` describe features 1-11 (with 4b-4e); MIT licensed. | Yes | Yes |

## Not supported in any NPC patch

Keep these the same across patches too, until every patch gains them:

- NPCs don't use Photon Sword's stance, raise a guard, or deflect gunfire themselves (their sword
  blocks only players' photon swords, feature 4c).
- An A-Life NPC's strike at a bandit isn't blocked: A-Life treats bandits as zombies and hits them
  the game's way, outside `HumanDamage.apply`. (A bandit's strike at an A-Life NPC is.) Players
  usually run one NPC mod at a time, so this is left as is; both patch descriptions tell players.
- In multiplayer, a player's strike on an NPC that another machine runs is blocked only where the
  attacker's client settles it: Project A-Life NPCs weighed on the server from a client's hit report
  don't block (A-Life's report carries no attacker to roll against).
- NPC swings don't cut doors, walls, or objects.
- NPC blades don't drain a battery; they switch off only when the fight ends.

## Checklist for a new NPC patch

1. Copy an existing patch folder, rename the mod id, and set `require`, `loadModAfter`, `mod.info`,
   and `workshop.txt` (feature 13 and 14). Add it to `deploy.sh`, `release.sh`, and `tools/gen_art.py`.
2. Find where the NPC mod's gunfire wounds a player and route it through `PS.judgeShot` or
   `PS.judgeLocalShot`, `PS.strikeBack`, and `PS.soak` (features 1-4). Route its melee wounds
   through `PS.judgeBlow` or `PS.judgeLocalBlow`, muting the hurt sounds after a block (feature 4b).
   If it weighs players' hits on its NPCs itself rather than taking vanilla damage, ask
   `PS.npcBlocks` there (feature 4c). Find where one NPC's melee blow lands on another and ask
   `PS.npcBlocks` there, settling a block as the NPC mod's own blocked hit if it has one (feature 4d).
   Check a blocking NPC's parry plays: if the NPC mod runs its NPCs' animations itself, replace
   `PS.playNpcParry` to play `PSParry` its way, and hold off its hit reaction and next swing until
   the parry ends (feature 4e).
3. Find where it picks an NPC's melee weapon, and arm it at `SpawnChance` with `PS.stableRoll` on a
   stable NPC key, where it has authority (features 5-6).
4. Find every place it makes the weapon item, and pass sword items through `PS.issueNpcBlade`
   with `PS.npcBladeColor` (features 7-8).
5. Find what a client can see of an NPC's fight (a variable, a task, its targets), and report it
   with `PS.addNpcCombatSource` from a client file, counting the approach as well as the fight (feature 9).
6. Check its death drops keep the sword (feature 10), and exclude both photon sword item types
   from any automatic loot scan it has (feature 11).
7. Copy the sandbox options and translations, changing only the page and mod names (feature 12).
8. Add a column to the table above, and an in-game suite (`dev/<prefix>_DevKitTest.lua`, run with
   `PSTest.run()`) covering what it can call directly.
