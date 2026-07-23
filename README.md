# Claude Menubar

A lightweight macOS menu-bar app that shows live Claude usage, powered by
[`ccusage`](https://ccusage.com). Written in Swift (AppKit), no dock icon,
minimal footprint.

## What it shows

Because Anthropic exposes **no official plan quota**, this app never invents a
fake "% of limit". By default it shows only numbers that are always correct:

- **Session cost** ($) and **tokens** for the active 5-hour block
- **Burn rate** ($/hr and tokens/min)
- **Time until the block resets**

If you want a **percentage**, you calibrate it once against the number the
Claude app itself shows you:

> "Calibrate Session %…" → enter the % the Claude app displays right now.
> The app maps it to your current token count (`limit = tokens / (pct/100)`)
> and shows a live % on every refresh afterward. Recalibrate any time it drifts.

Optional **weekly** tracking works the same way (calendar-week approximation —
see caveat below).

### Time-to-reset

Claude's 5-hour limit is **account-wide** across every surface (Code, desktop,
web, API). The true reset time is only in the **live API response headers**,
which Claude Code reads in-memory and never writes to disk — so no local tool
(this app or `ccusage`) can read it. `ccusage`'s block model is a floored-to-
the-hour estimate that will not match Claude Code.

So reset time is calibrated too:

> "Calibrate reset time…" → type what Claude Code shows ("resets in 1h8").
> The app anchors an exact reset timestamp and counts down precisely for that
> window. When the window rolls over the value expires and falls back to the
> `ccusage` block estimate (shown as `~2h47`), prompting you to recalibrate.

## Requirements

You need `ccusage` runnable. The app finds it automatically, in this order:

1. A `ccusage` binary on disk (Homebrew, npm global, etc.)
2. `bunx ccusage@latest` (if `bun` is installed)
3. `npx -y ccusage@latest` (if `node` is installed)

If none are found, the menu shows how to install one. GUI apps don't inherit
your shell `PATH`, so the app searches common locations explicitly
(`/opt/homebrew/bin`, nvm/bun/volta/fnm dirs, etc.).

## Build & run

```bash
# Dev: build and run in the foreground
./scripts/run-dev.sh

# Release: build a proper .app bundle
./scripts/build-app.sh
mv "build/Claude Menubar.app" /Applications/
open "/Applications/Claude Menubar.app"
```

**Launch at login** (the menu toggle) uses `SMAppService` and only works from
an installed `.app` in `/Applications`, not from `swift run`.

## Homebrew (planned)

Distribution will be a **cask** pointing at a released, zipped `.app`. Until the
app is signed with a Developer ID and notarized, Gatekeeper will quarantine it;
users would clear it with:

```bash
xattr -dr com.apple.quarantine "/Applications/Claude Menubar.app"
```

A signed + notarized build removes that step. Cask skeleton lives in
`Casks/` once a release is cut.

## Caveats

- **Weekly window**: `ccusage`'s "week" is a calendar week (configurable start
  day), not necessarily Anthropic's rolling 7-day limit window. Treat weekly %
  as an approximation.
- **Calibration drift**: the implied limit depends on model mix and cache
  accounting, so recalibrate when the app's % diverges from what Claude shows.

## Project layout

```
Sources/ClaudeMenubar/
  main.swift          NSApplication bootstrap (.accessory policy)
  AppDelegate.swift   status item, menu, refresh timer, dialogs
  CCUsage.swift       runner resolution (PATH search) + Process + JSON decode
  UsageModels.swift   Codable structs, UsageSnapshot, formatters
  Calibration.swift   UserDefaults-backed calibration store
  Preferences.swift   display/refresh prefs
  LoginItem.swift     SMAppService wrapper
Resources/Info.plist  LSUIElement, bundle id, version
scripts/              run-dev.sh, build-app.sh
```
