#!/bin/bash
# EQBuddy Evolved companion — install it into the osxEQL prefix and start it
# alongside the game.
#
# EQBuddy Evolved (github.com/DranakCorps-bot/EQBuddy) is a Windows-only WPF widget
# that tails EQ's /log file. Run inside the SAME prefix as the game it sees the
# prefix's drive_c as C:\ and finds the logs on its own — no configuration.
#
# EQBuddy Evolved is proprietary: osxEQL NEVER bundles or redistributes it. We fetch
# the official signed installer from the upstream GitHub release, verify it against
# the SHA-256 the release publishes next to it, and run it unmodified.
#
# Sourced by engine/osxeql (after lib.sh) and by the .app launcher (copied to
# Contents/Resources/eqbuddy.sh). Callers must set WINE, WINEPREFIX and OSXEQL_HOME,
# and the wine environment (see wine_env / the launcher's exports).
#
# Mode file $OSXEQL_HOME/eqbuddy — one word:
#   desktop  start EQBuddy INSIDE the game's Wine virtual desktop (an overlay: it
#            floats over the game, within the game window)
#   window   start EQBuddy as its own Mac window (e.g. on a second display)
#   off      never start it (and never ask again)
#   (absent) not decided yet — the .app asks once on the next PLAY launch

EQBUDDY_MODE_FILE="$OSXEQL_HOME/eqbuddy"
EQBUDDY_SETUP_NAME="EQBuddyEvolvedSetup.exe"
# releases/latest is the Evolved (v2) line upstream. If a release ever lacks the
# Evolved installer, the download 404s and we fail cleanly — nothing is guessed.
EQBUDDY_RELEASE_URL="${OSXEQL_EQBUDDY_URL:-https://github.com/DranakCorps-bot/EQBuddy/releases/latest/download}"

eqbuddy_mode() {
    local m
    m="$( [ -f "$EQBUDDY_MODE_FILE" ] && tr -cd 'a-z' < "$EQBUDDY_MODE_FILE")"
    case "$m" in
        desktop|window|off) echo "$m" ;;
        *)                  echo unset ;;
    esac
}

eqbuddy_set_mode() { echo "$1" > "$EQBUDDY_MODE_FILE"; }

# Unix path of the installed EQBuddy.exe, or nothing. The installer runs per-user
# (PrivilegesRequired=lowest → {userpf}), so it normally lands under
# users/<name>/AppData/Local/Programs; the Program Files arms cover an admin install.
eqbuddy_exe() {
    local c
    for c in "$WINEPREFIX"/drive_c/users/*/AppData/Local/Programs/"EQBuddy Evolved"/EQBuddy.exe \
             "$WINEPREFIX/drive_c/Program Files/EQBuddy Evolved/EQBuddy.exe" \
             "$WINEPREFIX/drive_c/Program Files (x86)/EQBuddy Evolved/EQBuddy.exe"; do
        [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

# drive_c-relative unix path -> C:\ windows path (no wine process needed).
eqbuddy_winpath() {
    local rel="${1#"$WINEPREFIX/drive_c/"}"
    printf 'C:\\%s\n' "${rel//\//\\}"
}

eqbuddy_running() { pgrep -f 'EQBuddy\.exe' >/dev/null 2>&1; }

# Download + verify the official installer into $1 (a directory). Prints the path.
eqbuddy_download() {
    local dir="$1" exe sha want got
    exe="$dir/$EQBUDDY_SETUP_NAME"; sha="$exe.sha256"
    mkdir -p "$dir" || return 1
    rm -f "$exe" "$sha"
    curl -fsSL --retry 2 -o "$sha" "$EQBUDDY_RELEASE_URL/$EQBUDDY_SETUP_NAME.sha256" || {
        echo "could not download $EQBUDDY_SETUP_NAME.sha256 from $EQBUDDY_RELEASE_URL" >&2; return 1; }
    curl -fsSL --retry 2 -o "$exe" "$EQBUDDY_RELEASE_URL/$EQBUDDY_SETUP_NAME" || {
        echo "could not download $EQBUDDY_SETUP_NAME from $EQBUDDY_RELEASE_URL" >&2; return 1; }
    # The .sha256 is PowerShell's Get-FileHash (uppercase hex, maybe a BOM): keep hex only.
    want="$(tr -cd '0-9A-Fa-f' < "$sha" | tr 'A-F' 'a-f')"
    got="$(shasum -a 256 "$exe" | cut -d' ' -f1)"
    if [ "${#want}" -ne 64 ] || [ "$want" != "$got" ]; then
        echo "SHA-256 mismatch for $EQBUDDY_SETUP_NAME (expected '$want', got '$got') — refusing to install" >&2
        rm -f "$exe"
        return 1
    fi
    printf '%s\n' "$exe"
}

# Inno Setup silent-install arguments. /TASKS="" skips the desktop-shortcut task.
# The installer's [Run] entry starts EQBuddy when it finishes, even when silent.
EQBUDDY_SETUP_ARGS=(/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /SP- '/TASKS=')

# Start the installed EQBuddy per the mode. $1x$2 = the virtual-desktop size (must
# equal the one LaunchPad is started with, or a second, differently sized desktop
# named osxEQL is requested). $3 = log file. Never blocks; never fatal.
eqbuddy_launch() {
    local w="$1" h="$2" log="$3" mode exe
    mode="$(eqbuddy_mode)"
    case "$mode" in desktop|window) ;; *) return 0 ;; esac
    exe="$(eqbuddy_exe)" || { echo "EQBuddy: mode=$mode but EQBuddy.exe is not installed (osxeql eqbuddy install)" >>"$log"; return 0; }
    # A second copy would only ask the running one to show itself (EQBuddy is
    # single-instance), so an already-running EQBuddy is left alone.
    eqbuddy_running && return 0
    echo "EQBuddy: starting ($mode): $exe" >>"$log"
    if [ "$mode" = desktop ]; then
        "$WINE" explorer "/desktop=osxEQL,${w}x${h}" "$(eqbuddy_winpath "$exe")" >>"$log" 2>&1 &
    else
        "$WINE" "$exe" >>"$log" 2>&1 &
    fi
}
