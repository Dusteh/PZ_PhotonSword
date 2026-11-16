#!/usr/bin/env bash
# Builds the mods' Steam Workshop releases into releases/ at the repo root.
#
#   ./release.sh [MOD...]     check every mod (or just the ones named) and build it into releases/
#                             and ~/Zomboid/Workshop/
#   ./release.sh --sync-ids   after uploading, copy each item's new id= back into this repo
#
# Each mod's Workshop folder (workshop.txt, preview.png, Contents/) is checked against the game
# uploader's rules and copied to releases/<MOD>, then to ~/Zomboid/Workshop/<MOD>, the only place
# the in-game uploader looks. Only those files go: tools/, dev/ (the dev kits), docs/, and the
# generators never leave the repo. Set WORKSHOP_DIR to build somewhere else, and UPLOAD_DIR to
# copy somewhere other than ~/Zomboid/Workshop (empty to skip the copy).
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
workshop="${WORKSHOP_DIR:-$root/releases}"
upload="${UPLOAD_DIR-$HOME/Zomboid/Workshop}"
[ "$upload" != "$workshop" ] || upload=""
all_mods=(PhotonSword PhotonSwordForms PhotonSwordALife PhotonSwordBandits PhotonSwordEoH)
errors=0

fail() {
    echo "  ERROR: $*" >&2
    errors=$((errors + 1))
}

# The id= line of a workshop.txt, if it has one.
item_id() {
    [ -f "$1" ] && grep -m1 '^id=' "$1" | cut -d= -f2- || true
}

# built_id MOD: the id= a build of MOD holds, in releases/ or the upload copy (where the uploader
# writes it). Fails if the two disagree, since only one can be the real item.
built_id() {
    local mod="$1" id upload_id
    id="$(item_id "$workshop/$mod/workshop.txt")"
    [ -n "$upload" ] || { echo "$id"; return 0; }
    upload_id="$(item_id "$upload/$mod/workshop.txt")"
    if [ -n "$id" ] && [ -n "$upload_id" ] && [ "$id" != "$upload_id" ]; then
        echo "  ERROR: $mod has id=$id in $workshop but id=$upload_id in $upload; fix one by hand" >&2
        return 1
    fi
    echo "${id:-$upload_id}"
}

# --sync-ids: the uploader writes the new item's id= into the uploaded workshop.txt. Keep it in the
# repo, so the next upload updates that item instead of creating another.
if [ "${1:-}" = "--sync-ids" ]; then
    for mod in "${all_mods[@]}"; do
        id="$(built_id "$mod")" || { errors=$((errors + 1)); continue; }
        repo_id="$(item_id "$root/$mod/workshop.txt")"
        if [ -z "$id" ]; then
            echo "$mod: not uploaded yet (no id= in its built workshop.txt)"
        elif [ "$id" = "$repo_id" ]; then
            echo "$mod: id=$id (already in the repo)"
        elif [ -n "$repo_id" ]; then
            fail "$mod: the build has id=$id but the repo has id=$repo_id; fix one by hand"
        else
            sed -i "s/^version=\(.*\)$/version=\1\nid=$id/" "$root/$mod/workshop.txt"
            echo "$mod: id=$id written to $mod/workshop.txt"
        fi
    done
    [ "$errors" -eq 0 ] || exit 1
    echo "Commit the workshop.txt changes."
    exit 0
fi

mods=("$@")
if [ "${#mods[@]}" -eq 0 ]; then
    mods=("${all_mods[@]}")
fi

if [ -n "$(git -C "$root" status --porcelain)" ]; then
    echo "WARNING: uncommitted changes; the release won't match a commit." >&2
fi

# check MOD: the rules the game's uploader (SteamWorkshopItem.validateContents) and loader apply,
# plus a syntax check of every Lua and JSON file that ships.
# check_changelog MOD WORKSHOP_TXT VERSION: the Workshop page's Change Log leads with an entry for
# the version being released: a "[b][YYYY-MM-DD] [VERSION][/b]" line followed by a [list] of what
# changed, newest entry first.
check_changelog() {
    local mod="$1" txt="$2" version="$3"
    [ -f "$txt" ] || return 0
    grep -q '^description=\[h[23]\]Change Log\[/h[23]\]$' "$txt" || {
        fail "$mod/workshop.txt has no Change Log section"
        return 0
    }
    local newest
    newest="$(grep -m1 -E '^description=\[b\]\[[0-9]{4}-[0-9]{2}-[0-9]{2}\] \[[^]]+\]\[/b\]$' "$txt" \
        | sed -E 's/^description=\[b\]\[[0-9-]+\] \[([^]]+)\]\[\/b\]$/\1/' || true)"
    if [ -z "$newest" ]; then
        fail "$mod/workshop.txt's Change Log has no [b][YYYY-MM-DD] [VERSION][/b] entry"
    elif [ "$newest" != "$version" ]; then
        fail "$mod/workshop.txt's newest Change Log entry is $newest, but mod.info is $version; add a [b][$(date +%F)] [$version][/b] entry at the top"
    fi
}

# check_description MOD WORKSHOP_TXT: the Workshop page fits Steam's description limit, 8000
# (k_cchPublishedDocumentDescriptionMax in the Steamworks SDK; the game passes the text straight
# through). It isn't clear whether Steam counts characters or bytes, or line breaks as one or two,
# so this counts the strict way (UTF-8 bytes, each line break as CRLF) and warns from 7000.
check_description() {
    local mod="$1" txt="$2" size
    [ -f "$txt" ] || return 0
    size="$(sed -n 's/^description=//p' "$txt" | python3 -I -c 'import sys; print(len(sys.stdin.read().replace("\n", "\r\n").encode()))')"
    if [ "$size" -gt 8000 ]; then
        fail "$mod/workshop.txt's description is $size bytes; Steam's limit is 8000"
    elif [ "$size" -gt 7000 ]; then
        echo "  WARNING: $mod/workshop.txt's description is $size bytes, close to Steam's 8000" >&2
    fi
}

check() {
    local mod="$1" dir="$root/$1"
    local contents="$dir/Contents" moddir="$dir/Contents/mods/$1"
    echo "Checking $mod"

    [ -f "$dir/workshop.txt" ] || fail "$mod/workshop.txt is missing"
    [ "$(item_id "$dir/workshop.txt")" != "0" ] || fail "$mod/workshop.txt has id=0, which the uploader takes for a real item; delete the line"
    grep -q '^title=' "$dir/workshop.txt" || fail "$mod/workshop.txt has no title="
    check_description "$mod" "$dir/workshop.txt"

    # preview.png: a 256x256 PNG of at most 1000KB, as the uploader's error messages state
    # (UI_WorkshopError_Preview* in the game's media/lua/shared/Translate/EN/UI.json).
    python3 -I - "$dir/preview.png" <<'EOF' || errors=$((errors + 1))
import struct, sys, os
path = sys.argv[1]
if not os.path.isfile(path):
    sys.exit(f"  ERROR: {path} is missing")
with open(path, "rb") as f:
    head = f.read(24)
if head[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit(f"  ERROR: {path} isn't a PNG")
w, h = struct.unpack(">II", head[16:24])
if (w, h) != (256, 256):
    sys.exit(f"  ERROR: {path} is {w}x{h}; the uploader takes 256x256")
if os.path.getsize(path) > 1024000:
    sys.exit(f"  ERROR: {path} is over 1,024,000 bytes")
EOF

    # Contents/ holds only mods/<MOD>, with both the 42/ and common/ folders.
    [ "$(ls -A "$contents")" = "mods" ] || fail "$mod/Contents must hold only mods/"
    [ "$(ls -A "$contents/mods")" = "$mod" ] || fail "$mod/Contents/mods must hold only $mod/"
    [ -d "$moddir/42" ] || fail "$mod has no 42/ folder"
    [ -d "$moddir/common" ] || fail "$mod has no common/ folder (Build 42 needs it, even empty)"

    # mod.info: its id matches the folder, and its poster and icon exist.
    local info="$moddir/42/mod.info"
    if [ -f "$info" ]; then
        [ "$(grep -m1 '^id=' "$info" | cut -d= -f2-)" = "$mod" ] || fail "$mod mod.info's id= isn't $mod"
        grep -q '^modversion=' "$info" || fail "$mod mod.info has no modversion="
        check_changelog "$mod" "$dir/workshop.txt" "$(grep -m1 '^modversion=' "$info" | cut -d= -f2- || true)"
        local key file
        for key in poster icon; do
            file="$(grep -m1 "^$key=" "$info" | cut -d= -f2- || true)"
            [ -z "$file" ] || [ -f "$moddir/42/$file" ] || fail "$mod mod.info's $key=$file is missing"
        done
    else
        fail "$mod has no 42/mod.info"
    fi

    # Nothing generative or dev-only ships.
    local stray
    stray="$(find "$contents" \( -name '*.py' -o -name '*.pyc' -o -name '__pycache__' -o -name '*.blend' \
        -o -name '*.blend1' -o -name '*DevKit*' -o -name '.*' ! -name '.gitkeep' \) -print)"
    [ -z "$stray" ] || fail "$mod ships files that belong outside the mod: $stray"

    local f
    while IFS= read -r -d '' f; do
        luac5.1 -p "$f" 2>/dev/null || fail "Lua syntax: ${f#"$root"/}"
    done < <(find "$moddir" -name '*.lua' -print0)
    while IFS= read -r -d '' f; do
        python3 -I -m json.tool "$f" >/dev/null 2>&1 || fail "JSON syntax: ${f#"$root"/}"
    done < <(find "$moddir" -name '*.json' -print0)
}

# Mods with an FJL Java plugin (MOD/java/) ship its jar, built fresh.
"$root/tools/build_java.sh" >/dev/null

for mod in "${mods[@]}"; do
    [ -d "$root/$mod/Contents" ] || { fail "no mod named $mod"; continue; }
    if [ -d "$root/$mod/java" ] && ! ls "$root/$mod/Contents/mods/$mod/42/java/"*.jar >/dev/null 2>&1; then
        fail "$mod has java/ but no built jar in 42/java/"
    fi
    check "$mod"
done
if [ "$errors" -gt 0 ]; then
    echo "$errors problem(s); nothing built." >&2
    exit 1
fi

for mod in "${mods[@]}"; do
    dest="$workshop/$mod"
    # An id= in releases/ or the upload copy that the repo doesn't have yet (uploaded, not synced)
    # is kept, so the next upload updates that item instead of creating a duplicate.
    built_id="$(built_id "$mod")" || exit 1
    mkdir -p "$dest/Contents"
    rsync -a --delete --exclude='.gitkeep' "$root/$mod/Contents/" "$dest/Contents/"
    cp "$root/$mod/preview.png" "$dest/preview.png"
    cp "$root/$mod/workshop.txt" "$dest/workshop.txt"
    if [ -n "$built_id" ] && [ -z "$(item_id "$root/$mod/workshop.txt")" ]; then
        sed -i "s/^version=\(.*\)$/version=\1\nid=$built_id/" "$dest/workshop.txt"
        echo "NOTE: $mod keeps id=$built_id; run ./release.sh --sync-ids" >&2
    fi
    where="$dest"
    if [ -n "$upload" ]; then
        mkdir -p "$upload/$mod"
        rsync -a --delete "$dest/" "$upload/$mod/"
        where="$where and $upload/$mod"
    fi
    version="$(grep -m1 '^modversion=' "$root/$mod/Contents/mods/$mod/42/mod.info" | cut -d= -f2-)"
    id="$(item_id "$dest/workshop.txt")"
    if [ -n "$id" ]; then
        echo "Built $mod $version to $where (updates Workshop item $id)"
    else
        echo "Built $mod $version to $where (new Workshop item)"
    fi
done
echo "Upload each mod from the game's Workshop menu (see README: Releasing). Then run ./release.sh --sync-ids."
