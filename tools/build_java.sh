#!/usr/bin/env bash
# Builds each mod's FJL plugin (MOD/java: src/ and resources/) into
# MOD/Contents/mods/MOD/42/java/MOD-<modversion>.jar, against the game jar and Faded Java Loader's
# agent jar (its API and Sponge Mixin). Needs a JDK 25 (the game's classes are Java 25): JAVA25_HOME, or sdkman's 25.0.5.0+8-tem.
set -euo pipefail
jdk="${JAVA25_HOME:-$HOME/.sdkman/candidates/java/25.0.5.0+8-tem}"
export PATH="$jdk/bin:$PATH"
root="$(cd "$(dirname "$0")/.." && pwd)"
game="${PZ_GAME:-$HOME/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid}"
cp="$game/projectzomboid.jar:$game/FadedJavaLoader/FadedJavaLoader-Agent.jar"
for src in "$root"/*/java; do
    mod="$(basename "$(dirname "$src")")"
    info="$root/$mod/Contents/mods/$mod/42/mod.info"
    version="$(grep -m1 '^modversion=' "$info" | cut -d= -f2-)"
    out="$root/$mod/Contents/mods/$mod/42/java"
    build="$(mktemp -d)"
    trap 'rm -rf "$build"' EXIT
    javac --release 25 -nowarn -cp "$cp" -d "$build" $(find "$src/src" -name '*.java')
    cp -r "$src/resources/." "$build/"
    mkdir -p "$out"
    rm -f "$out"/*.jar
    (cd "$build" && jar --create --file "$out/$mod-$version.jar" .)
    rm -rf "$build"
    echo "Built $mod-$version.jar"
done
