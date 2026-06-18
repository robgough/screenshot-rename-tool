# screenshot-renamer

Watches your screenshot folder and renames new screenshots using the **on-device Apple
foundation model** (macOS 27 `FoundationModels`). It looks at the image, identifies the app or
website, and produces a name like:

```
Screenshot 2026-06-17 at 21.28.35.png   ->   20260617_2128 zapier slack planning thread.png
Screenshot 2018-10-04 at 17.06.14.png   ->   20181004_1706 govuk application complete vehicle tax summary.png
```

The capture date/time goes first as `YYYYMMDD_HHMM`, so **alphabetical order = chronological
order**. Descriptions are lowercase ASCII words only (filename-safe, no Unicode look-alikes).

## How it works

- The timestamp prefix is taken from macOS's default screenshot filename (falls back to the
  file's creation date).
- The description comes from `SystemLanguageModel.default` — the local model. Nothing leaves the
  Mac. The image is downscaled to 1536px first (faster, and it sidesteps a full-res Vision bug).
- Only files still named `Screenshot …` are touched; once renamed they no longer match, so they're
  never reprocessed. Files modified in the last ~2s are skipped (they may still be saving).

> Note on "two models": macOS 27 exposes the local `SystemLanguageModel` **and** a larger
> `PrivateCloudComputeLanguageModel` (Apple's privacy-preserving cloud, metered + needs network).
> This tool uses the local one. Switching to PCC would be a small change in `Renamer.describe`.

## Requirements

- macOS 27, Apple Silicon, **Apple Intelligence enabled** (Settings → Apple Intelligence & Siri).
- Xcode Command Line Tools (no full Xcode needed).

## Build

```sh
./build.sh          # produces ./screenshot-renamer
```

(We compile with `swiftc` directly: SwiftPM's `swift build` is currently broken on the CLT beta,
and the `@Generable` macro plugin ships only with full Xcode — neither is needed here.)

## Use it by hand

```sh
./screenshot-renamer --dry-run --max 10     # preview names, change nothing
./screenshot-renamer                        # rename current screenshots once, then exit
./screenshot-renamer --watch                # keep watching (Ctrl-C to stop)
./screenshot-renamer ~/some/other/folder    # a different folder
```

Default folder is `~/Documents/img.screenshots` (your current screenshot location).
Options: `--dry-run`, `--once` (default), `--watch`, `--max N`, `--max-pixel N`, `--interval N`.

## Run it automatically (launchd)

```sh
./install.sh        # builds, installs a LaunchAgent, starts watching at login
./uninstall.sh      # stop and remove it
tail -f ~/Library/Logs/screenshot-renamer.log
```

**One-time permission:** a background agent can't show a permission prompt, and your screenshots
live in `~/Documents` (a protected folder). Grant access or renames fail silently:

> System Settings → Privacy & Security → **Full Disk Access** → **+** → select
> `screenshot-renamer`, then re-run `./install.sh`.

## Files

- `Sources/screenshot-renamer/main.swift` — CLI, options, watch loop, availability check
- `Sources/screenshot-renamer/Renamer.swift` — file selection, naming, model call, rename
- `build.sh` / `install.sh` / `uninstall.sh` — build and launchd wiring
- `launchd/…plist` — reference copy of the agent definition
- `probe.swift` — quick `swift probe.swift` to check model availability/capabilities
