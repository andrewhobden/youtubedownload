# YouTubeLibrary (iOS + macOS Catalyst)

SwiftUI media-library app that wraps the `download.py` engine from the
repo root. Two libraries (Videos, Music Albums), automatic mode
selection per URL (`--chapters` / `--playlist` / `--autosplit` /
single-file), built-in video and audio players. One Xcode target
builds for iOS sideload **and** Mac Catalyst.

The Python download logic and ffmpeg post-processing live in two
separate runtimes:

- Embedded **Python 3.11** (via Python-Apple-support) runs `yt-dlp` with
  all `FFmpeg*` post-processors disabled.
- **ffmpeg-kit-ios** (linked C library, *not* a spawnable binary) does
  all mp3 conversion, chapter slicing, silence-split slicing, and
  thumbnail conversion on the Swift side.

## Current build status (2026-06-05)

iOS-only v1 boots end-to-end on iOS Simulator with embedded Python +
yt-dlp loaded. Catalyst is deferred.

- ✅ `xcodegen generate` produces a working `.xcodeproj`.
- ✅ Swift compiles cleanly for `generic/platform=iOS` and
  `generic/platform=iOS Simulator` (`xcodebuild build` succeeds with no
  errors or warnings, code-signing skipped for local builds).
- ✅ `yt-dlp` 2025.10.14 bundled at `apple/Resources/site-packages/yt_dlp/`.
- ✅ Python 3.13 runtime bundled (`apple/Frameworks/Python.xcframework`
  + `apple/Resources/python-stdlib/`).
- ✅ ffmpeg-kit + libav* + libsw* XCFrameworks linked from the
  [ChristopherGabba/ffmpeg-kit-ios-full-gpl](https://github.com/ChristopherGabba/ffmpeg-kit-ios-full-gpl)
  fork (arthenica's official binaries were archived in 2025).
- ✅ App installs + launches on iOS Simulator. SwiftUI UI renders
  "Videos" tab with empty-state placeholder. Stdout confirms
  `[PythonBridge] yt-dlp version: 2025.10.14` at launch.
- ⚠️  The committed Python `lib-dynload` matches the **simulator-arm64**
  slice. For a device build (sideload to iPhone), swap with
  `Python.xcframework/ios-arm64/lib-arm64/python3.13/lib-dynload/` —
  or wire it into a Run Script build phase keyed off `$PLATFORM_NAME`.
- ⚠️  **End-to-end download / mp3 / album flow is not yet exercised** in
  Simulator (would need UI automation). The Swift surface, Python
  bridge, and ffmpeg-kit linkage are all wired; first real download is
  the next manual smoke test.
- ⏸️  Mac Catalyst: deferred. The Python-Apple-support archives don't
  ship a Catalyst slice; ffmpeg-kit fork does. Re-enable
  `SUPPORTS_MACCATALYST: YES` once a Catalyst Python.xcframework slice
  is built from sources.

## One-time setup

```bash
brew install xcodegen                              # project file generator

cd apple/
python3 -m pip install --target Resources/site-packages --upgrade yt-dlp

xcodegen generate
open YouTubeLibrary.xcodeproj
```

In Xcode:

1. Set **Signing → Team** to your personal Apple ID (Personal Team is
   fine for sideload).
2. Choose a destination — an iOS device for sideload, or **"My Mac
   (Mac Catalyst)"** for the Mac build. The same target supports both.

## Embedded Python — Catalyst caveat

`Resources/site-packages/yt_dlp/` is already installed (see status
above). What's missing is the embedded **Python runtime** itself.

The staged archives `apple/Frameworks/_downloads/{iOS,macOS}.tar.gz`
(Python 3.13-b13 from
[Python-Apple-support](https://github.com/beeware/Python-Apple-support/releases))
provide:

| Archive    | Slices in `Python.xcframework`              |
|------------|---------------------------------------------|
| iOS.tar.gz | `ios-arm64`, `ios-arm64_x86_64-simulator`   |
| macOS.tar.gz | `macos-arm64_x86_64`                      |

There is **no Mac Catalyst slice in either archive.** A unified
`Python.xcframework` that links for iOS *and* Catalyst requires
combining either of the above with a Catalyst slice you build yourself,
or using [Briefcase](https://briefcase.readthedocs.io/) (which only
targets native iOS, not Catalyst).

For iOS-only sideload (no Catalyst): unpack `iOS.tar.gz` into
`apple/Frameworks/Python.xcframework` and `apple/Resources/python-stdlib`,
then re-add the framework reference to `project.yml` (see commented
block in that file) and `xcodegen generate`. The bundled `youtube_core.py`
will then `import yt_dlp` successfully.

For Catalyst: building a Catalyst slice from source is the only path
today. The BeeWare build scripts live at
[Python-Apple-support](https://github.com/beeware/Python-Apple-support);
their `Makefile` builds per-platform but does not currently target
Catalyst. PR welcome upstream.

`Resources/youtube_core.py` (committed) is the thin module Swift calls;
it imports `yt_dlp` from `Resources/site-packages/`.

## FFmpeg

**Status: blocker, no clean path today.**

`arthenica/ffmpeg-kit` was archived in 2025 and its release assets
(including the previously-recommended "audio" XCFramework) are gone.
Surviving sources of binaries:

| Source | URL | Notes |
|---|---|---|
| `ChristopherGabba/ffmpeg-kit-ios-full-gpl` | github releases | iOS-only "full-gpl" ~64 MB; **no Catalyst slice** |
| `safastak/ffmpeg-kit-ios-full-lgpl` | github releases | repo exists, currently 0 release assets |
| `arthenica/ffmpeg-kit` (source) | github | build from source via `ios.sh` — 30–60 min, many transitive deps |

`FFmpegOps` and `SilenceSplitter` reference the framework via
`#if canImport(ffmpegkit)`, so without it the project still builds — but
every call traps at runtime with `FFmpegError.ffmpegKitMissing`. To
unblock:

1. Pick a source above.
2. Place the resulting `ffmpegkit.xcframework` in `apple/Frameworks/`.
3. Re-add the framework reference to `project.yml` (commented block in
   `dependencies:`).
4. `xcodegen generate` and rebuild.

For Catalyst specifically, the only viable path today is to either
build ffmpeg-kit from source with a Catalyst slice, or use a different
ffmpeg wrapper (e.g. linking the system `libavformat`/`libavcodec`
installed via brew at run time, which works for personal Catalyst use
but adds runtime brittleness).

## Sideload signing (iOS)

- Free Apple ID works. Profiles last 7 days; re-install via Xcode after
  that.
- AltStore / SideStore also work — export an `.ipa` via
  `Product → Archive → Distribute App → Development`.

## Mac (Catalyst) notes

- The first launch prompts for a download folder via `NSOpenPanel`
  (`.fileImporter`). The choice persists across launches via a
  security-scoped bookmark in `UserDefaults`.
- "Sign to Run Locally" is enough for personal use; no developer
  membership required.
- Menu bar: ⌘N opens the Add sheet; ⌘R reveals the download folder
  (`Commands.swift`).

## Add flow — auto-classification

| Library  | URL                                  | Mode chosen          |
|----------|--------------------------------------|----------------------|
| Videos   | any `/watch?v=…`                     | single MP4           |
| Videos   | `/playlist?list=…`                   | many MP4s            |
| Videos   | `/watch?v=…&list=…`                  | single MP4 (ignores list) |
| Music    | `/playlist?list=…`                   | playlist album       |
| Music    | `/watch?v=…` ≥3 chapters             | chapters album       |
| Music    | `/watch?v=…` no chapters, ≥20 min    | autosplit album      |
| Music    | `/watch?v=…` no chapters, <20 min    | single-track album   |
| Music    | `/watch?v=…&list=…`                  | **prompt the user**  |

Thresholds (chapter count = 3, autosplit min duration = 20 min) live in
`Core/URLClassifier.swift`.

## Project layout

```
apple/
  project.yml            # XcodeGen config
  App/                   # @main, root tabs, Mac commands, entitlements
  Library/               # SwiftUI views (videos list, albums grid, players, add sheet)
  Model/                 # SwiftData @Models + MediaRoot + NowPlaying
  Core/                  # URLClassifier, Sanitize, FFmpegOps, SilenceSplitter,
                         # PythonBridge, YouTubeProbe, DownloadCoordinator
  Resources/             # youtube_core.py + python-stdlib/ + site-packages/
  Frameworks/            # Python.xcframework + ffmpegkit.xcframework
```

## What's deliberately out of v1

- App Store distribution.
- yt-dlp self-update from the network (embedded version goes stale —
  rebuild to refresh).
- iOS background-task scheduling for long downloads (foreground only).
- Track-boundary editing after autosplit.
- Importing pre-existing files into the library.
