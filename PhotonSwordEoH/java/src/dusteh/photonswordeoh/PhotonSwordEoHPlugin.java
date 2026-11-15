package dusteh.photonswordeoh;

import com.fadedmods.fjl.api.FJLContext;
import com.fadedmods.fjl.api.FJLPlugin;

/** Photon Sword - Echoes of Humanity: the FJL entry point. The work is the Hit mixin and Lua. */
public final class PhotonSwordEoHPlugin implements FJLPlugin {
    @Override
    public void onLoad(FJLContext context) {
        LuaHooks.logger = context.getLogger();
        context.getLogger().info("Photon Sword - Echoes of Humanity hooks loaded");
    }
}
