#!/usr/bin/env bash
# Copies every mod in this repo into ~/Zomboid/mods for local testing: Photon Sword, Photon Sword
# Forms, and the compatibility patches.
# PZ mangles script paths when the mod folder is a symlink, so this copies instead of linking.
# The dev kits and in-game tests (dev/*DevKit*.lua) are copied in too, unless run with --release.
# It warns if the game is running (it reads mods at startup).
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
mods=(PhotonSword PhotonSwordForms PhotonSwordBandits PhotonSwordALife PhotonSwordEoH)
# The game also loads mods from ~/Zomboid/Workshop/*/Contents/mods (upload copies) and from Steam's
# downloads of subscribed items, and with two copies of one mod id it may load the stale one. So
# each mod's copies there are deleted first (clear_copies).
workshop="$HOME/Zomboid/Workshop"
steam_content=""
for dir in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
    if [ -d "$dir/steamapps/workshop/content/108600" ]; then
        steam_content="$dir/steamapps/workshop/content/108600"
        break
    fi
done

# The id= line of a workshop.txt, if it has one.
item_id() {
    [ -f "$1" ] && grep -m1 '^id=' "$1" | cut -d= -f2- || true
}

# clear_copies MOD: deletes MOD's upload copy (~/Zomboid/Workshop/MOD; ./release.sh builds a fresh
# one) and Steam's download of its Workshop item (the id= in MOD/workshop.txt). An upload copy whose
# id= the repo lacks is the only record of that item, so it stops the deploy instead. Steam downloads
# a subscribed item again when it updates or the game is verified; unsubscribe to keep it gone.
clear_copies() {
    local mod="$1" repo_id upload_id item
    repo_id="$(item_id "$root/$mod/workshop.txt")"
    if [ -d "$workshop/$mod" ]; then
        upload_id="$(item_id "$workshop/$mod/workshop.txt")"
        if [ -n "$upload_id" ] && [ "$upload_id" != "$repo_id" ]; then
            echo "ERROR: $workshop/$mod has id=$upload_id, which $mod/workshop.txt lacks; record it" \
                "(WORKSHOP_DIR=$workshop ./release.sh --sync-ids), then re-run" >&2
            exit 1
        fi
        rm -rf "$workshop/$mod"
        echo "Removed the upload copy $workshop/$mod"
    fi
    [ -n "$steam_content" ] && [ -n "$repo_id" ] || return 0
    item="$steam_content/$repo_id"
    [ -d "$item" ] || return 0
    if [ "$(ls -A "$item/mods" 2>/dev/null)" != "$mod" ]; then
        echo "WARNING: Steam item $repo_id ($item) doesn't hold just $mod; left alone" >&2
        return 0
    fi
    rm -rf "$item"
    echo "Removed Steam's download of item $repo_id ($item)"
}

for mod in "${mods[@]}"; do
    clear_copies "$mod"
done

# deploy MOD: copies MOD/Contents/mods/MOD to ~/Zomboid/mods/MOD.
deploy() {
    local dest="$HOME/Zomboid/mods/$1"
    # Replace a leftover symlink from earlier setups with a real directory.
    if [ -L "$dest" ]; then
        rm "$dest"
    fi
    mkdir -p "$dest"
    rsync -a --delete --exclude='.gitkeep' "$root/$1/Contents/mods/$1/" "$dest/"
}

# devkit MOD FILE...: copies each dev/FILE into MOD's server Lua, unless --release.
devkit() {
    local mod="$1" dest="$HOME/Zomboid/mods/$1"
    shift
    if [ "$release" = 1 ]; then
        echo "Deployed to $dest"
    else
        mkdir -p "$dest/42/media/lua/server/$mod"
        for file in "$@"; do cp "$root/dev/$file" "$dest/42/media/lua/server/$mod/"; done
        echo "Deployed to $dest (with dev kit)"
    fi
}

release=0
if [ "${1:-}" = "--release" ]; then
    release=1
fi

deploy PhotonSword
devkit PhotonSword PS_DevKit.lua PS_DevKitTest.lua
deploy PhotonSwordForms
devkit PhotonSwordForms PSF_DevKit.lua PSF_DevKitTest.lua

# The compatibility patches, mods of their own.
deploy PhotonSwordBandits
devkit PhotonSwordBandits PSB_DevKitTest.lua
deploy PhotonSwordALife
devkit PhotonSwordALife PSA_DevKit.lua PSA_DevKitTest.lua
# Echoes of Humanity's patch carries an FJL Java plugin, built first. FJL picks Java mods when the
# game starts, so a changed jar needs a restart.
"$root/tools/build_java.sh" >/dev/null
deploy PhotonSwordEoH
devkit PhotonSwordEoH PSE_DevKit.lua

# The game binary itself; the launcher script's name also turns up in shells that merely mention it.
# The pattern can't match its own text, so the shell running this doesn't count.
if pgrep -f '(^|/)ProjectZomboid64( |$)' >/dev/null 2>&1; then
    echo "WARNING: the game is running; quit and relaunch it to load these changes." >&2
fi
