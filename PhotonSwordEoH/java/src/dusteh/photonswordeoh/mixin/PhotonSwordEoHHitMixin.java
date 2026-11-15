package dusteh.photonswordeoh.mixin;

import dusteh.photonswordeoh.LuaHooks;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoSurvivor;
import zombie.inventory.types.HandWeapon;

/**
 * Echoes of Humanity lands every NPC attack (melee and ranged) and every player hit on its NPCs
 * through the game's Hit, on survivor bodies. Before a hit with a survivor on either side, Lua's
 * beforeHit(target, attacker, weapon, damage) may return a number to settle it instead (0: blocked
 * or deflected; EoH treats a 0 as a hit that did nothing). After, afterHit gets the damage dealt.
 */
@Mixin(IsoGameCharacter.class)
public abstract class PhotonSwordEoHHitMixin {
    private static final String HIT =
        "Hit(Lzombie/inventory/types/HandWeapon;Lzombie/characters/IsoGameCharacter;FZFZ)F";

    @Inject(method = HIT, at = @At("HEAD"), cancellable = true)
    private void photonSwordEoH$beforeHit(HandWeapon weapon, IsoGameCharacter wielder, float damage,
            boolean ignoreDamage, float modDelta, boolean remote, CallbackInfoReturnable<Float> cir) {
        IsoGameCharacter self = (IsoGameCharacter) (Object) this;
        if (!(self instanceof IsoSurvivor) && !(wielder instanceof IsoSurvivor)) return;
        Object settled = LuaHooks.call("beforeHit", self, wielder, weapon, (double) damage);
        if (settled instanceof Double) cir.setReturnValue(((Double) settled).floatValue());
    }

    @Inject(method = HIT, at = @At("RETURN"))
    private void photonSwordEoH$afterHit(HandWeapon weapon, IsoGameCharacter wielder, float damage,
            boolean ignoreDamage, float modDelta, boolean remote, CallbackInfoReturnable<Float> cir) {
        IsoGameCharacter self = (IsoGameCharacter) (Object) this;
        if (!(self instanceof IsoSurvivor) && !(wielder instanceof IsoSurvivor)) return;
        LuaHooks.call("afterHit", self, wielder, weapon, (double) cir.getReturnValueF());
    }
}
