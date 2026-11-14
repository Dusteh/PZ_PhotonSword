#!/usr/bin/env bash
# Copies every mod in this repo into ~/Zomboid/mods for local testing: Photon Sword, Photon Sword
# Forms, and the compatibility patches.
# PZ mangles script paths when the mod folder is a symlink, so this copies instead of linking.
# The dev kits (dev/PS_DevKit.lua, dev/PSF_DevKit.lua) are copied in too, unless run with --release.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"

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

# devkit MOD KIT: copies dev/KIT into MOD's server Lua, unless --release.
devkit() {
    local dest="$HOME/Zomboid/mods/$1"
    if [ "$release" = 1 ]; then
        echo "Deployed to $dest"
    else
        mkdir -p "$dest/42/media/lua/server/$1"
        cp "$root/dev/$2" "$dest/42/media/lua/server/$1/"
        echo "Deployed to $dest (with dev kit)"
    fi
}

release=0
if [ "${1:-}" = "--release" ]; then
    release=1
fi

deploy PhotonSword
devkit PhotonSword PS_DevKit.lua
deploy PhotonSwordForms
devkit PhotonSwordForms PSF_DevKit.lua

# The compatibility patches, mods of their own.
for patch in PhotonSwordBandits PhotonSwordALife; do
    deploy "$patch"
    echo "Deployed to $HOME/Zomboid/mods/$patch"
done
