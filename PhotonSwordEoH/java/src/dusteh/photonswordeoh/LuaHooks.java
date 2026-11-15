package dusteh.photonswordeoh;

import com.fadedmods.fjl.api.FJLLogger;
import se.krka.kahlua.vm.KahluaTable;
import zombie.GameWindow;
import zombie.Lua.LuaManager;
import zombie.network.GameServer;

/**
 * Calls the patch's Lua hooks: functions in the global table TABLE. Only on the game's own thread
 * (Lua isn't thread safe), never re-entrantly (a hook's own hits don't call hooks again), and a
 * missing table, function, or Lua error just means "no say".
 */
public final class LuaHooks {
    public static final String TABLE = "PhotonSwordEoHHooks";
    static FJLLogger logger;
    private static boolean busy;

    private LuaHooks() {}

    private static boolean onGameThread() {
        Thread current = Thread.currentThread();
        return current == GameWindow.gameThread || current == GameServer.mainThread;
    }

    /** The hook's first return value, or null. */
    public static Object call(String name, Object... args) {
        if (busy || !onGameThread() || LuaManager.env == null || LuaManager.caller == null) return null;
        Object table = LuaManager.env.rawget(TABLE);
        if (!(table instanceof KahluaTable)) return null;
        Object fn = ((KahluaTable) table).rawget(name);
        if (fn == null) return null;
        busy = true;
        try {
            Object[] result = LuaManager.caller.pcall(LuaManager.thread, fn, args);
            if (result == null || result.length < 2) return null;
            if (Boolean.TRUE.equals(result[0])) return result[1];
            if (logger != null) logger.warn(TABLE + "." + name + " failed: " + result[1]);
        } catch (Throwable t) {
            if (logger != null) logger.warn(TABLE + "." + name + " threw: " + t);
        } finally {
            busy = false;
        }
        return null;
    }
}
