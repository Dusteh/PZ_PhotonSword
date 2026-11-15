#!/usr/bin/env bash
# Copies every mod in this repo into ~/Zomboid/mods for local testing: Photon Sword, Photon Sword
# Forms, and the compatibility patches.
# PZ mangles script paths when the mod folder is a symlink, so this copies instead of linking.
# The dev kits and in-game tests (dev/*DevKit*.lua) are copied in too, unless run with --release.
#
# The game also loads mods from ~/Zomboid/Workshop/*/Contents/mods (upload copies) and from Steam
# subscriptions, and with two copies of one mod id it may load the old one. So this first moves any
# upload copy of these mods to ~/Zomboid/Workshop_aside/ (README: Releasing copies a fresh one back
# in to upload), warns about subscribed copies (unsubscribe on Steam; deleting them only makes
# Steam download them again), and warns if the game is running (it reads mods at startup).
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
mods=(PhotonSword PhotonSwordForms PhotonSwordBandits PhotonSwordALife PhotonSwordEoH)
workshop="$HOME/Zomboid/Workshop"
aside="$HOME/Zomboid/Workshop_aside"
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

# set_aside MOD: moves MOD's upload copy out of ~/Zomboid/Workshop. An earlier set-aside copy is
# replaced, unless its workshop.txt holds an id the repo doesn't (run ./release.sh --sync-ids).
set_aside() {
    local src="$workshop/$1" dest="$aside/$1"
    [ -d "$src" ] || return 0
    if [ -d "$dest" ]; then
        local old_id
        old_id="$(item_id "$dest/workshop.txt")"
        if [ -n "$old_id" ] && [ "$old_id" != "$(item_id "$root/$1/workshop.txt")" ]; then
            echo "ERROR: $dest has id=$old_id, which $1/workshop.txt lacks; sync it, then re-run" >&2
            exit 1
        fi
        rm -rf "$dest"
    fi
    mkdir -p "$aside"
    mv "$src" "$dest"
    echo "Moved the upload copy $src to $dest"
}

# warn_subscribed MOD: names any Steam download of MOD, which can shadow the deployed copy.
warn_subscribed() {
    [ -n "$steam_content" ] || return 0
    local info
    for info in "$steam_content"/*/mods/"$1"/42/mod.info; do
        [ -f "$info" ] || continue
        local item="${info#"$steam_content"/}"
        item="${item%%/*}"
        echo "WARNING: subscribed to $1 on Steam (item $item); unsubscribe so the game loads the deployed copy:" >&2
        echo "         https://steamcommunity.com/sharedfiles/filedetails/?id=$item" >&2
    done
}

for mod in "${mods[@]}"; do
    set_aside "$mod"
    warn_subscribed "$mod"
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

if pgrep -f "ProjectZomboid/projectzomboid.sh" >/dev/null 2>&1; then
    echo "WARNING: the game is running; quit and relaunch it to load these changes." >&2
fi
