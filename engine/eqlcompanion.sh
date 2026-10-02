#!/bin/bash
# EQ Legends Companion — install it into the osxEQL prefix and run it with the game.
#
# EQ Legends Companion (github.com/jmoyers/everquest-companion, Josh Moyers) is a
# Windows Electron app that reads EverQuest's /log: DPS meter and floating overlays,
# Plane of Sky tracker, loot and item knowledge, AA/levels, raid targets, buff timers,
# sound and voice alerts. It is the second companion osxEQL-Buddy can run, next to
# EQBuddy Evolved (engine/eqbuddy.sh), with the same treatment:
#
#   * install: official NSIS installer from the project's GitHub release, verified
#     against the SHA-512 electron-builder publishes in latest.yml, run silently into
#     the game's prefix. Its own log discovery already looks at
#     C:\Users\Public\Daybreak Game Company\…\EverQuest Legends — which is exactly where
#     the game writes in our prefix, so no setup.
#   * update: latest.yml's version vs. the installed one, at every launch, in the
#     background. (The app's own electron-updater checks the installer's Authenticode
#     signature through PowerShell, which Wine doesn't have — ours replaces it.)
#   * float over fullscreen: the patched winemac.so knob, written for its exe before
#     it starts (engine/overlay.sh, same as EQBuddy).
#   * hide when another app is in front / close with the game: the same macOS helper
#     (engine/tools/eqbuddy-focus.swift) with --app for this exe, sounds off — Electron
#     plays its own audio through Wine's CoreAudio driver, no bridge needed.
#
# The app itself already detects Wine and switches Chromium to the flags that paint in
# a Wine prefix (its shared/wineDetect.ts, GitHub issue 28) — we change nothing in it.
# Licence: FSL-1.1-MIT. osxEQL-Buddy never bundles it; it downloads the official
# release on the player's request and runs it unmodified.
#
# Sourced after engine/eqbuddy.sh (shares the helper binary, autohide/autoclose
# settings and the Wine environment). Mode file $OSXEQL_HOME/eqlc: window|off
# (absent = not decided: the app asks once).

EQLC_MODE_FILE="$OSXEQL_HOME/eqlc"
EQLC_STAMP="$OSXEQL_HOME/eqlc-installed-version"
EQLC_AUTOUPDATE_FILE="$OSXEQL_HOME/eqlc-autoupdate"
EQLC_RELEASE_URL="${OSXEQL_EQLC_URL:-https://github.com/jmoyers/everquest-companion/releases/latest/download}"

eqlc_mode() {
    local m
    m="$( [ -f "$EQLC_MODE_FILE" ] && tr -cd 'a-z' < "$EQLC_MODE_FILE")"
    case "$m" in window|off) echo "$m" ;; *) echo unset ;; esac
}
eqlc_set_mode() { echo "$1" > "$EQLC_MODE_FILE"; }
eqlc_autoupdate() {
    [ "$( [ -f "$EQLC_AUTOUPDATE_FILE" ] && tr -cd 'a-z' < "$EQLC_AUTOUPDATE_FILE")" = off ] && echo off || echo on
}

# The installed exe. electron-builder's one-click per-user NSIS installs to
# %LOCALAPPDATA%\Programs\<name>\<productName>.exe; both names are tried.
eqlc_exe() {
    local c
    for c in "$WINEPREFIX"/drive_c/users/*/AppData/Local/Programs/*/"EQ Legends Companion.exe" \
             "$WINEPREFIX"/drive_c/users/*/AppData/Local/Programs/*/everquest-companion.exe; do
        [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

eqlc_running() { pgrep -qf 'EQ Legends Companion\.exe|everquest-companion\.exe' 2>/dev/null; }

# latest.yml -> "version<TAB>file<TAB>sha512(base64)" on stdout.
eqlc_latest() {
    curl -fsSL --max-time 10 "$EQLC_RELEASE_URL/latest.yml" 2>/dev/null | awk '
        /^version:/ { v=$2 } /^path:/ { p=$2 } /^sha512:/ { s=$2 }
        END { if (v != "" && p != "" && s != "") printf "%s\t%s\t%s\n", v, p, s }'
}

# Download + verify the installer named in latest.yml into $1. Prints "version<TAB>path".
eqlc_download() {
    local dir="$1" meta ver file want got
    meta="$(eqlc_latest)" || true
    [ -n "$meta" ] || { echo "could not read $EQLC_RELEASE_URL/latest.yml" >&2; return 1; }
    IFS=$'\t' read -r ver file want <<< "$meta"
    case "$file" in *[/\\]*|"") echo "unexpected installer name in latest.yml: $file" >&2; return 1 ;; esac
    mkdir -p "$dir" || return 1
    rm -f "$dir/$file"
    curl -fsSL --retry 2 -o "$dir/$file" "$EQLC_RELEASE_URL/$file" || {
        echo "could not download $file" >&2; return 1; }
    got="$(openssl dgst -sha512 -binary "$dir/$file" | openssl base64 -A)"
    if [ "$got" != "$want" ]; then
        echo "SHA-512 mismatch for $file — refusing to install" >&2
        rm -f "$dir/$file"; return 1
    fi
    printf '%s\t%s\n' "$ver" "$dir/$file"
}

# Silent NSIS install (/S). One-click per-user: no admin, no wizard. Waits for it.
eqlc_install() {
    local log="$1" meta ver setup
    meta="$(eqlc_download "$OSXEQL_HOME/cache" 2>>"$log")" || return 1
    IFS=$'\t' read -r ver setup <<< "$meta"
    echo "EQLC: installing $ver" >>"$log"
    "$WINE" "$setup" /S >>"$log" 2>&1 || echo "EQLC: installer returned non-zero" >>"$log"
    eqlc_exe >/dev/null || { echo "EQLC: installer finished but the exe was not found" >>"$log"; return 1; }
    echo "$ver" > "$EQLC_STAMP"
    echo "EQLC: installed $ver" >>"$log"
}

# Newer release (or missing app) -> install. Never touches a running copy; offline -> no-op.
eqlc_update() {
    local log="$1" latest have
    [ "$(eqlc_autoupdate)" = on ] || [ "${EQLC_FORCE_UPDATE:-0}" = 1 ] || return 0
    eqlc_running && return 0
    latest="$(eqlc_latest | cut -f1)"
    [ -n "$latest" ] || { echo "EQLC: update check failed (offline?)" >>"$log"; return 0; }
    have="$( [ -f "$EQLC_STAMP" ] && cat "$EQLC_STAMP")"
    if eqlc_exe >/dev/null && [ "$have" = "$latest" ]; then
        echo "EQLC: up to date ($latest)" >>"$log"; return 0
    fi
    echo "EQLC: ${have:-unknown} -> $latest" >>"$log"
    eqlc_install "$log" || echo "EQLC: update failed — starting the installed copy" >>"$log"
    return 0
}

# Float over the fullscreen game: the patched driver's per-exe knob, written BEFORE the
# app starts (the driver reads it at startup). No-op with a stock winemac.so.
eqlc_sync_float() {
    local log="$1" exe="$2" so
    so="$(dirname "$WINE")/../lib/wine/x86_64-unix/winemac.so"
    [ -f "$so.osxeql-overlay" ] || return 0
    [ "$(shasum -a 256 "$so" 2>/dev/null | cut -d' ' -f1)" = "$(tr -cd '0-9a-f' < "$so.osxeql-overlay")" ] || return 0
    "$WINE" reg add "HKCU\\Software\\Wine\\AppDefaults\\$(basename "$exe")\\Mac Driver" \
        /v LetTopmostWindowsFloatOverFullscreen /t REG_SZ /d Y /f >>"$log" 2>&1 \
        || echo "EQLC: could not write the Mac Driver knob" >>"$log"
}

eqlc_start_helper() {
    local log="$1" bin ah=off ac
    [ "$( [ -f "$OSXEQL_HOME/eqbuddy-helper" ] && tr -cd 'a-z' < "$OSXEQL_HOME/eqbuddy-helper")" = off ] && return 0
    pgrep -qf 'eqbuddy-focus.*--app eq legends companion' && return 0
    bin="$(eqbuddy_focus_bin "$log")" || return 0
    [ "$(eqbuddy_autohide)" = on ] && ah=on
    ac="$(eqbuddy_autoclose)"
    echo "EQLC: helper $bin (autohide $ah, autoclose $ac)" >>"$log"
    nohup "$bin" --prefix "$WINEPREFIX" --app "eq legends companion" --app "everquest-companion" \
        --sounds off --autohide "$ah" --autoclose "$ac" >>"$log" 2>&1 &
}

eqlc_launch() {
    local log="$1" exe
    [ "$(eqlc_mode)" = window ] || return 0
    exe="$(eqlc_exe)" || { echo "EQLC: enabled but not installed" >>"$log"; return 0; }
    if eqlc_running; then eqlc_start_helper "$log"; return 0; fi
    eqlc_sync_float "$log" "$exe"
    echo "EQLC: starting $exe" >>"$log"
    "$WINE" "$exe" >>"$log" 2>&1 &
    eqlc_start_helper "$log"
}

# Update (or install if missing), then launch — in the background: the game never waits.
eqlc_update_and_launch() {
    [ "$(eqlc_mode)" = window ] || return 0
    ( eqlc_update "$1"; eqlc_launch "$1" ) &
}
