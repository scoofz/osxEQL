#!/bin/bash
# Let EQBuddy (or any opted-in topmost window) float over the FULLSCREEN game.
#
# Why: when EQ runs fullscreen, macOS puts its window at a level no ordinary
# topmost window can beat, so EQBuddy's own window disappears behind it (it only
# shows again once the game goes windowed). engine/patches/winemac-overlay.patch
# adds an opt-in per-app knob to winemac.drv (LetTopmostWindowsFloatOverFullscreen)
# that lifts such a window above the fullscreen level. EQBuddy writes that knob for
# itself from its WineFloatOverFullscreen setting, which engine/eqbuddy.sh turns on.
#
# This rebuilds ONLY winemac.so — from the same CodeWeavers CrossOver source the
# runtime was built from (engine/build-wine.sh), plus the patch — and swaps it into
# the Wine runtime(s) in place, keeping a backup. Minutes, not the full 30-60 min
# build. Nothing prebuilt is downloaded; the patch is readable in engine/patches/.
#
#   engine/overlay.sh            patch the runtime(s)
#   engine/overlay.sh --revert   restore the original winemac.so
#   engine/overlay.sh --status   show whether each runtime is patched
#
# Runtimes touched: $WINE_DIR (the engine's) and /Applications/osxEQL.app's embedded
# one — each only once if one is a symlink to the other. An .app is re-signed
# ad-hoc afterwards (editing a bundle file breaks its signature).
# Requires: Xcode command-line tools, and bison >= 3 (brew install bison).
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"

CX_VERSION="${OSXEQL_CX_VERSION:-26.2.0}"      # must match engine/build-wine.sh
PATCH="$HERE/patches/winemac-overlay.patch"
WS="$HOME/osxeql-wine-build"                    # shared with build-wine.sh (tarball cache)
TARBALL="$WS/crossover-sources-${CX_VERSION}.tar.gz"
WORK="$WS/overlay-${CX_VERSION//./}"
WINESRC="$WORK/sources/wine"
BUILD="$WORK/build-winemac"
APP="${OSXEQL_APP:-/Applications/osxEQL.app}"
SYMBOL=topmost_float_over_fullscreen

# Unique real paths of the runtimes to patch.
runtimes() {
    local seen="" d r
    for d in "$WINE_DIR" "$APP/Contents/Resources/Wine"; do
        [ -f "$d/lib/wine/x86_64-unix/winemac.so" ] || continue
        r="$(cd "$d" && pwd -P)"
        case "|$seen|" in *"|$r|"*) continue ;; esac
        seen="$seen|$r"
        printf '%s\n' "$r"
    done
}

# The patch's registry-knob name is a string literal in the binary: no nm needed.
is_patched() { grep -aq LetTopmostWindowsFloatOverFullscreen "$1" 2>/dev/null; }

# Re-sign the enclosing .app, if the runtime lives inside one.
resign_app() {
    local rt="$1" app
    case "$rt" in */Contents/Resources/Wine) app="${rt%/Contents/Resources/Wine}" ;; *) return 0 ;; esac
    log "re-signing $app (ad-hoc)"
    codesign --force --deep --sign - "$app" >/dev/null 2>&1 || warn "codesign of $app failed — it may refuse to launch"
}

install_so() {  # $1 = runtime, $2 = built winemac.so
    local so="$1/lib/wine/x86_64-unix/winemac.so"
    [ -f "$so.osxeql-orig" ] || cp "$so" "$so.osxeql-orig"    # keep the very first original
    cp "$2" "$so" || die "could not write $so"
    codesign --force --sign - "$so" >/dev/null 2>&1 || true
    resign_app "$1"
    log "patched: $so"
}

patch_is_applied() {  # judge by the tree, not by patch's exit status (partial = failure)
    [ "$(grep -l "$SYMBOL" \
        "$WINESRC/dlls/winemac.drv/macdrv_cocoa.h" \
        "$WINESRC/dlls/winemac.drv/macdrv_main.c" \
        "$WINESRC/dlls/winemac.drv/cocoa_window.m" 2>/dev/null | wc -l | tr -d ' ')" -eq 3 ]
}

find_bison() {
    local b
    for b in /opt/homebrew/opt/bison/bin /usr/local/opt/bison/bin; do
        [ -x "$b/bison" ] && { printf '%s\n' "$b"; return 0; }
    done
    return 1
}

build_winemac() {  # $1 = an existing winemac.so (to copy its Vulkan soname from)
    local ref="$1" bisondir vk
    xcode-select -p >/dev/null 2>&1 || die "Xcode command-line tools missing — run: xcode-select --install"
    bisondir="$(find_bison)" || die "bison >= 3 not found — run: brew install bison"
    [ -f "$PATCH" ] || die "missing $PATCH"
    mkdir -p "$WS" "$WORK"

    if [ ! -f "$WINESRC/configure" ]; then
        if [ ! -s "$TARBALL" ]; then
            log "downloading CrossOver ${CX_VERSION} source (CodeWeavers' LGPL drop)…"
            curl -fL --retry 3 --progress-bar -o "$TARBALL.part" \
                "https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz" \
                && mv "$TARBALL.part" "$TARBALL" || { rm -f "$TARBALL.part"; die "source download failed"; }
        fi
        log "extracting sources/wine…"
        tar xzf "$TARBALL" -C "$WORK" sources/wine || die "extract failed"
    fi

    if patch_is_applied; then
        log "overlay patch already applied to the source tree"
    else
        log "applying $(basename "$PATCH")…"
        ( cd "$WINESRC" && patch -p1 --forward --no-backup-if-mismatch < "$PATCH" ) || true
        patch_is_applied || die "the overlay patch does not apply to CrossOver ${CX_VERSION} (see .rej files under $WINESRC/dlls/winemac.drv)"
    fi

    if [ ! -f "$BUILD/Makefile" ]; then
        log "configuring (winemac.drv only)…"
        mkdir -p "$BUILD"
        ( cd "$BUILD" && PATH="$bisondir:$PATH" CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
            "$WINESRC/configure" --host=x86_64-apple-darwin --without-mingw \
            --enable-archs=none --disable-tests \
            --without-alsa --without-capi --without-cups --without-dbus --without-ffmpeg \
            --without-fontconfig --without-freetype --without-gphoto --without-gnutls \
            --without-gssapi --without-gstreamer --without-hwloc --without-inotify --without-krb5 \
            --without-netapi --without-opencl --without-oss --without-pcap --without-pcsclite \
            --without-pulse --without-sane --without-sdl --without-udev --without-unwind \
            --without-usb --without-v4l2 --without-vulkan --without-wayland >"$LOGDIR/overlay-configure.log" 2>&1 ) \
            || die "configure failed — see $LOGDIR/overlay-configure.log"
    fi

    # Keep the Vulkan library name the shipped winemac.so was built with (the runtime's
    # own build had Vulkan; this winemac-only configure doesn't, so it is passed in).
    vk="$(strings "$ref" 2>/dev/null | grep -m1 -E '^lib(MoltenVK|vulkan)[A-Za-z0-9._-]*\.dylib$')"
    vk="${vk:-libMoltenVK.dylib}"
    log "building winemac.so (Vulkan soname: $vk)…"
    # Doubled backslashes are load-bearing: make runs each recipe through /bin/sh.
    ( cd "$BUILD" && PATH="$bisondir:$PATH" \
        make dlls/winemac.drv/winemac.so -j"$(sysctl -n hw.ncpu)" \
        "CFLAGS=-g -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -DSONAME_LIBVULKAN=\\\"$vk\\\"" \
        >"$LOGDIR/overlay-build.log" 2>&1 ) || die "build failed — see $LOGDIR/overlay-build.log"
    [ -f "$BUILD/dlls/winemac.drv/winemac.so" ] || die "build produced no winemac.so"
    is_patched "$BUILD/dlls/winemac.drv/winemac.so" || die "built winemac.so lacks the patch symbol"
    # Same ABI guard as build-app.sh: without this bridge DXMT cannot draw (gotcha #1).
    nm -gU "$BUILD/dlls/winemac.drv/winemac.so" | grep -q macdrv_functions \
        || die "built winemac.so does not export macdrv_functions — refusing to install (gotcha #1)"
}

rts="$(runtimes)"
[ -n "$rts" ] || die "no Wine runtime found (looked in $WINE_DIR and $APP)"

case "${1:-}" in
    --status)
        while IFS= read -r rt; do
            if is_patched "$rt/lib/wine/x86_64-unix/winemac.so"; then echo "patched:     $rt"
            else echo "not patched: $rt"; fi
        done <<< "$rts"
        ;;
    --revert)
        pgrep -f 'eqgame|LaunchPad|EQBuddy\.exe' >/dev/null && die "quit the game and EQBuddy first"
        while IFS= read -r rt; do
            so="$rt/lib/wine/x86_64-unix/winemac.so"
            [ -f "$so.osxeql-orig" ] || { log "no backup for $rt — leaving it"; continue; }
            cp "$so.osxeql-orig" "$so" && codesign --force --sign - "$so" >/dev/null 2>&1
            resign_app "$rt"
            log "restored: $so"
        done <<< "$rts"
        ;;
    "")
        pgrep -f 'eqgame|LaunchPad|EQBuddy\.exe' >/dev/null && die "quit the game and EQBuddy first (winemac.so is in use)"
        built=""
        while IFS= read -r rt; do
            so="$rt/lib/wine/x86_64-unix/winemac.so"
            if is_patched "$so"; then log "already patched: $rt"; continue; fi
            [ -n "$built" ] || { build_winemac "$so"; built="$BUILD/dlls/winemac.drv/winemac.so"; }
            install_so "$rt" "$built"
        done <<< "$rts"
        log "done. Next: osxeql eqbuddy window (EQBuddy as its own window), then launch the game."
        ;;
    *) die "usage: engine/overlay.sh [--status|--revert]" ;;
esac
