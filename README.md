# osxEQL-Buddy

**EverQuest Legends on Apple Silicon Macs — with [EQBuddy Evolved](https://github.com/DranakCorps-bot/EQBuddy)
running alongside it as a real overlay.**

osxEQL-Buddy is a fork of [sowoky/osxEQL](https://github.com/sowoky/osxEQL). It keeps
everything osxEQL does — the game on **100% open-source parts**: Wine compiled from
CodeWeavers' published LGPL source + **DXMT** (DirectX 11 → Metal), no CrossOver, no
proprietary D3DMetal — and adds the pieces needed to use EQBuddy Evolved, a
Windows-only companion widget, on a Mac as if it were native:

- EQBuddy is **installed and started with the game** (opt-in, official release, SHA-256 checked);
- it **floats over the game, even fullscreen**;
- it **hides when you switch to another app** and comes back with the game;
- its **alert sounds play** (through macOS);
- the game window is **sized to your display** so fullscreen works and the mouse
  reaches every pixel.

> Unofficial, fan-made compatibility tool. **Not** affiliated with or endorsed by
> Daybreak Game Company, Game Jawn, CodeWeavers, Apple, or the EQBuddy author. The
> EverQuest Legends game is **not included** — you bring your own copy from the
> official installer. EQBuddy Evolved is **not included** either — see
> [EQBuddy Evolved](#eqbuddy-evolved-companion).

---

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 13+ (macOS 26 Tahoe supported).
- A Daybreak / EverQuest Legends account and the official **`EQLegends_setup.exe`**.
- ~10 GB free disk (the game client downloads through Daybreak's launcher).
- Internet access the first time, if you want EQBuddy (≈55 MB download).

## Install (players)

1. Download **`osxEQL-<version>.dmg`** from this fork's [Releases](../../releases) page.
2. Open it and drag **osxEQL** into **Applications**. (The app keeps the name
   `osxEQL.app` and the data folder `~/Library/Application Support/osxEQL`, so an
   existing osxEQL install — prefix, game client, settings — is reused as is.)
3. The release is **ad-hoc signed, not notarized by Apple**, so clear the
   quarantine flag once before the first launch:
   ```bash
   xattr -dr com.apple.quarantine /Applications/osxEQL.app
   ```
   (or right-click → **Open** the first time).
4. Download **`EQLegends_setup.exe`** from the official EverQuest Legends site.
5. Launch **osxEQL**. A setup window walks the whole install: pick the installer
   when asked, then watch it run Daybreak's installer, update the launcher, and
   download the game — you get a chime when the login screen is ready. Log in,
   hit **Play**.
6. On the next launch osxEQL asks **once** whether to install EQBuddy Evolved.
   Say yes and it opens next to the game from then on.

Nothing else to install: no Homebrew, no Xcode, no Wine — the runtime (with the
overlay-patched Mac driver) and the helpers ship inside the app.

## What's different from osxEQL

### Game window = your display (fullscreen and mouse fixed)
The game runs inside a Wine *virtual desktop*. Upstream sized it to "display minus
menu/title bar" (and the CLI to a fixed 1280×960). EverQuest's in-game fullscreen asks
Wine for a display mode of exactly `Width×Height`; a virtual desktop only offers its
own size plus smaller standard modes, so EQ fell back to **1280×960** — the picture
shrank, the **mouse stopped working outside a 1280×960 area**, and EQ rewrote
`eqclient.ini`.

Now the virtual desktop is **exactly the main display** by default, and all four
`eqclient.ini` size keys are pinned to it at every launch (backup:
`eqclient.ini.osxeql-bak`). Fullscreen and windowed are the same size, the mouse maps
1:1, and your Fullscreen choice is kept. `osxeql res auto|WxH` still lets you pick a
smaller window (fullscreen is then forced off, since that is what breaks it);
`osxeql res max` returns to the default. The `osxeql play` CLI now uses the same rules
as the app.

### Sound follows your headphones
Wine's CoreAudio driver pinned the game's sound to the device that was the macOS
default when the game started. If that device vanished mid-game — Bluetooth
headphones out of battery — the sound blasted out of the Mac speakers, ignoring their
volume and mute, until the game was restarted. The bundled `winecoreaudio.so` now opens
the game's default-device streams on macOS's *default output* unit, which follows the
system default: headphones die → speakers, at the speakers' volume/mute; connect other
headphones → the sound moves to them, no restart. Streams opened on a specific device
are unchanged; `OSXEQL_PIN_AUDIO_DEVICE=1` restores the old behaviour.

### EQBuddy Evolved companion
Everything below is automatic in the app once EQBuddy is installed.

| What | How |
|---|---|
| **Install** | Downloads the official `EQBuddyEvolvedSetup.exe` from EQBuddy's GitHub release, refuses it unless it matches the published `.sha256`, installs it silently into the game's prefix. EQBuddy sees the prefix as `C:\` and finds your logs with no setup. |
| **Start with the game** | Started next to LaunchPad on every Play, as its own Mac window (`window` mode). |
| **Always the latest version** | At every launch, before EQBuddy starts, the SHA-256 published next to the latest official installer is compared with the one last installed. A new release (or a missing EQBuddy) is downloaded, verified and installed silently — in the background, the game never waits. Offline: the installed copy starts as is. `osxeql eqbuddy autoupdate off` disables it; `osxeql eqbuddy update` checks now. |
| **Float over fullscreen** | macOS puts a fullscreen game above every normal "always on top" window. The bundled Mac driver (`winemac.so`) carries a small opt-in patch (from EQBuddy 1.99.18, MIT) that lets EQBuddy's windows sit above it. osxEQL-Buddy writes the driver setting *before* EQBuddy starts (the driver reads it at startup, so EQBuddy's own write only counted on the *next* launch) and turns on EQBuddy's `WineFloatOverFullscreen` option, which also keeps clicks on the widget from pulling the game out of fullscreen. |
| **Hide when the game isn't in front** | EQBuddy's own "Hide when game unfocused" can't see the game (different Wine desktop). A small macOS helper (`eqbuddy-focus`) watches the frontmost app and hides EQBuddy while you're in another app, showing it again when you're back in EverQuest. EQBuddy's own option is switched off so the two don't fight. |
| **Closes with the game** | When the game has been closed for 20 s (enough for a quick relaunch from LaunchPad), the helper quits EQBuddy with a normal macOS Quit, which EQBuddy handles as a Windows shutdown — it saves and exits cleanly (forced only if it ignores that for 30 s). An EQBuddy you opened without the game is left alone. `osxeql eqbuddy autoclose off` disables it. |
| **Alert sounds** | EQBuddy plays alerts through WPF's MediaPlayer, which can't play anything under this Wine (Wine's WAV parser needs GStreamer, which the runtime doesn't ship) — every alert logged `0x80040218`. The helper watches EQBuddy's `error.log` and plays the sound on the Mac with `afplay`, using the macOS system sounds EQBuddy 1.x used natively (Ding→Ping, Notify→Glass, Chimes→Blow, Chord→Pop, Tada→Hero, Exclamation→Sosumi, Alarm→Submarine) at EQBuddy's alert volume. Custom `.wav`/`.mp3` files inside the prefix play as is. |

**Known limits**
- The log line doesn't say which rule fired, so alerts play the sound your
  sound-enabled rules share, or else EQBuddy's shared "Alert sound".
- **Spoken alerts** (text-to-speech) stay silent: they need a Windows speech voice,
  which Wine doesn't have.

EQBuddy Evolved is a separate, **proprietary** product by its own author. osxEQL-Buddy
never bundles or redistributes it: it only downloads the official, signed release on
your request and runs it unmodified. The overlay patch and the macOS sound mapping come
from EQBuddy **1.x**, which is MIT-licensed (see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)).

## Command line (`engine/osxeql`)

The CLI is the headless equivalent of the app. From a clone of this repo:

```bash
engine/osxeql status                  # what's installed (Wine, prefix, game, EQBuddy, overlay)
engine/osxeql play                    # launch the game (+ EQBuddy)
engine/osxeql res [max|auto|WxH]      # game window size (default: max = exact display)

engine/osxeql eqbuddy                 # show EQBuddy install + mode
engine/osxeql eqbuddy install         # download (SHA-256 checked) + install EQBuddy
engine/osxeql eqbuddy window|desktop|off
                                      # window (default) = own Mac window over the game;
                                      # desktop = inside the game's Wine desktop (experimental);
                                      # off = never start it
engine/osxeql eqbuddy autohide on|off # hide EQBuddy while another app is in front
engine/osxeql eqbuddy autoclose on|off
                                      # quit EQBuddy 20 s after the game closes (default on)
engine/osxeql eqbuddy update          # install the latest EQBuddy release now, if newer
engine/osxeql eqbuddy autoupdate on|off
                                      # do that automatically at every launch (default on)

engine/osxeql overlay [--status|--revert]
                                      # rebuild winemac.so with the float-over-fullscreen
                                      # patch (only needed for a self-built runtime; the
                                      # release app already has it). Xcode CLT + brew bison.
engine/osxeql audiofix [--status|--revert]
                                      # rebuild winecoreaudio.so so the game's sound follows
                                      # the macOS default output (same needs as overlay)
engine/osxeql winlevels [filter] [--delay N]
                                      # list on-screen windows + macOS window levels
                                      # (diagnoses what is drawn above what)
```

If the CLI says `wine: not staged`, point it at the app's runtime once:
```bash
ln -s /Applications/osxEQL.app/Contents/Resources/Wine "$HOME/Library/Application Support/osxEQL/Wine"
```

### Logs
All in `~/Library/Application Support/osxEQL/logs/`:
`app-launch.log` / `launch-*.log` (game), `eqbuddy.log` (EQBuddy start, helper
decisions, alert sounds), `eqbuddy-install.log`, `overlay-*.log`. EQBuddy's own errors:
`…/osxEQL/prefix/drive_c/users/<you>/AppData/Roaming/EQBuddy Evolved/error.log`.

## How it works

`eqgame.exe` is a 64-bit Direct3D 11 game. To run it on macOS you need (1) **Wine**
to run the Windows binary and (2) a **D3D11→Metal** translator. osxEQL uses:

- **Wine** built from CodeWeavers' official LGPL CrossOver source — it has the
  `macdrv_functions` bridge DXMT needs to attach a Metal view (stock Wine doesn't).
- **DXMT** (github.com/3Shain/dxmt) for D3D11→Metal — the open-source alternative
  to Apple's proprietary D3DMetal.

The runtime (Wine + DXMT) is embedded in `osxEQL.app`; the wine prefix and the game
client live in `~/Library/Application Support/osxEQL/`. EQBuddy is installed into that
same prefix. Deep technical notes are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
and [`docs/JOURNEY.md`](docs/JOURNEY.md).

## Build from source (developers)

```bash
# 1. Compile the Wine runtime from CodeWeavers' LGPL source (~30-60 min, x86_64).
#    Needs Xcode CLT + Intel Homebrew. Stages to ~/…/osxEQL/Wine.cxbuild, then
#    verify DXMT render and swap into ~/…/osxEQL/Wine.
engine/build-wine.sh

# 2. Stage DXMT into that wine tree + create a prefix.
engine/osxeql backend dxmt

# 3. Build the app icon (needs `brew install librsvg`).
cd assets/icon && uv run python generate.py && \
  rsvg-convert -w 1024 -h 1024 icon.svg -o icon.png && bash build_icns.sh icon.png && cd ../..

# 4. (osxEQL-Buddy) Patch the Mac driver (EQBuddy floats over the fullscreen game)
#    and the CoreAudio driver (sound follows the macOS output). build-wine.sh already
#    applies both; for a runtime built before that, rebuild just those two .so files
#    (minutes). Needs Xcode CLT + brew bison.
engine/osxeql overlay
engine/osxeql audiofix

# 5. Assemble the self-contained app + DMG. build-app.sh also compiles the Swift
#    helpers (setup window, eqbuddy-focus) and reports whether the overlay patch is in.

packaging/build-app.sh        # -> dist/osxEQL.app  (embeds the runtime)
packaging/build-dmg.sh        # -> dist/osxEQL-<ver>.dmg

# 6. (Optional) Sign with a Developer ID for Gatekeeper-clean distribution.
#    Set these env vars — secrets stay local, never in the repo:
export CODESIGN_IDENTITY="Developer ID Application: ..."
export NOTARIZE_KEY=~/path/to/AuthKey.p8
export NOTARIZE_KEY_ID=<key-id>
export NOTARIZE_ISSUER=<issuer-uuid>
packaging/build-app.sh        # signs + notarizes instead of ad-hoc
packaging/build-dmg.sh        # auto-detects signed app, notarizes DMG
```

### Prerequisites (building only — the release DMG needs none of this)

Since v0.2.1 `packaging/build-app.sh` bundles the Homebrew dylibs wine dlopens
(freetype, gnutls, SDL2, …) into the app, so **end users don't need Homebrew**.
Building from source does:

- **x86_64 Homebrew** (`/usr/local/bin/brew`).
  > [!IMPORTANT]
  > Wine is an x86_64 application and **requires** x86_64 libraries. The standard ARM64 Homebrew (`/opt/homebrew/bin/brew`) will install incompatible libraries that will cause Wine to instantly crash.
  > 
  > To install the x86_64 version of Homebrew on an Apple Silicon Mac, run:
  > ```bash
  > arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  > ```

- **Required Homebrew formulas** (must be installed via `arch -x86_64 /usr/local/bin/brew install <formula>`):
  - `bison` `mingw-w64` `pkgconfig` `coreutils` `freetype` `gnutls` `molten-vk` `sdl2` `vulkan-loader` `vulkan-headers` `libpcap`

The `engine/osxeql` CLI (`setup`/`install`/`import-client`/`play`/`backend`/`res`/
`eqbuddy`/`overlay`/`winlevels`/`status`/`doctor`) is the headless equivalent of the
app and is handy for development.

## Project layout

```
app/            launcher.sh (the app entry point + first-run wizard) + Info.plist
assets/icon/    icon source (generate.py / icon.svg) + AppIcon.icns + build_icns.sh
engine/         headless CLI + numbered setup scripts + build-wine.sh
  eqbuddy.sh    EQBuddy install/launch, sounds, overlay + autohide settings (also in the .app)
  overlay.sh    rebuild winemac.so with the float-over-fullscreen patch
  audiofix.sh   rebuild winecoreaudio.so so sound follows the macOS default output
  driverlib.sh  shared build/install plumbing for overlay.sh + audiofix.sh
  patches/      winemac-overlay.patch (EQBuddy 1.99.18, MIT), coreaudio-follow-default.py,
                + upstream macdrv patch
  tools/        eqbuddy-focus.swift (autohide + alert sounds), winlevels.m (diagnostics)
packaging/      build-app.sh, build-dmg.sh, sign-and-notarize.sh, entitlements.plist,
                verify-release.sh (check a signed DMG against this source)
docs/           ARCHITECTURE / STATUS / JOURNEY / VISION
```

The big artifacts — the 569 MB Wine runtime, the ~7 GB game client, the DMG — are
**not** in git (see `.gitignore`); the runtime ships inside the Release DMG, the
game client is the user's own.

## License & credits

- osxEQL and osxEQL-Buddy's own code: **MIT** (see [`LICENSE`](LICENSE)). osxEQL by
  [sowoky](https://github.com/sowoky/osxEQL); EQBuddy integration in this fork.
- EQBuddy 1.99.18 (MIT): the winemac overlay patch, `winlevels.m` and the macOS
  sound mapping. EQBuddy **Evolved** is proprietary and is not included.
- Wine (LGPL-2.1) and DXMT (LGPL-2.1+) — see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)
  for license texts and how to obtain/rebuild the corresponding source.
- EverQuest Legends © Daybreak Game Company / Game Jawn. Not included, not affiliated.
- Upstream osxEQL releases are signed by Skybound Solutions, LLC (code signing
  contributed by [@skybound-raz](https://github.com/skybound-raz)); osxEQL-Buddy
  releases are ad-hoc signed.
