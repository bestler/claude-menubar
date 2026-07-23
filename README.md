<div align="center">

# 📊 Claude Menubar

**See your Claude usage at a glance — right from the macOS menu bar.**

Live session cost, tokens, burn rate, and time-to-reset for Claude Code,
Claude Pro & Max — a tiny native menu-bar app powered by
[`ccusage`](https://github.com/ryoppippi/ccusage).

[![Latest release](https://img.shields.io/github/v/release/bestler/claude-menubar?sort=semver)](https://github.com/bestler/claude-menubar/releases)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000?logo=apple)](https://github.com/bestler/claude-menubar)
[![Built with Swift](https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white)](https://github.com/bestler/claude-menubar)
[![License: MIT](https://img.shields.io/github/license/bestler/claude-menubar)](LICENSE)

</div>

---

Ever wanted a quick answer to *"how much Claude have I burned this session, and
when does it reset?"* without opening a terminal? This lives in your menu bar
and just shows you — updating every few seconds.

```
 ┌─────────────────────────────────────┐
 │ ● Active session                    │
 │ Cost: $17.20                        │
 │ Tokens: 7.2M                        │
 │ Burn: $10.3/hr · 72k tok/min        │
 │ Resets in: 1h 5m  (calibrated 3m…)  │
 │ ─────────────────────────────────── │
 │ Session: 41%                        │
 │ ─────────────────────────────────── │
 │ Menu bar shows          ▸           │
 │ Refresh interval        ▸           │
 │ Calibrate Session %…                │
 │ Calibrate reset time…               │
 │ Launch at login              ✓      │
 │ Quit                                │
 └─────────────────────────────────────┘
```

## Install

```sh
brew install --cask bestler/tap/claude-menubar
```

Or grab the notarized `.app` from the
[latest release](https://github.com/bestler/claude-menubar/releases/latest),
unzip, and drop it in `/Applications`.

Then click the menu-bar icon and (optionally) toggle **Launch at login**.

## Requirements

The app reads your usage via the `ccusage` CLI. It finds it automatically — you
only need **one** of these:

- `ccusage` installed (`brew install ccusage` or `npm i -g ccusage`), **or**
- [`bun`](https://bun.sh) or [Node.js](https://nodejs.org) — it'll run
  `ccusage` on demand via `bunx`/`npx`, no install needed.

If none are found, the menu tells you how to get one.

## What it shows

Everything in the top section is **always accurate**, straight from your local
usage data:

| Metric | Meaning |
| --- | --- |
| **Cost** | Spend in the current 5-hour session block |
| **Tokens** | Total tokens used this block |
| **Burn rate** | $/hour and tokens/minute right now |
| **Resets in** | Time until the session window rolls over |

Pick which one rides in the menu bar itself via **Menu bar shows ▸**.

## Percentages & reset time — calibration

Anthropic doesn't publish your plan's token quota anywhere, and the real reset
clock only lives in Claude's live API responses. So rather than show you a
made-up number, Claude Menubar lets you **calibrate** against what the Claude
app already tells you:

- **Calibrate Session %** — type the % the Claude app shows; the app maps it to
  your current token count and displays a live % from then on.
- **Calibrate reset time** — type Claude Code's "resets in …" and it counts down
  exactly for the current window (auto-expires and falls back to an estimate
  when the window rolls over).

Recalibrating is a one-tap menu action any time it drifts.

> **Weekly tracking** (optional) works the same way. Note that `ccusage`'s week
> is a calendar week, which may not line up exactly with a rolling weekly limit —
> treat it as an approximation.

## Build from source

```sh
git clone https://github.com/bestler/claude-menubar
cd claude-menubar
./scripts/run-dev.sh          # build & run for development
./scripts/build-app.sh        # assemble a .app bundle in ./build
```

Requires the Swift toolchain (Xcode or Command Line Tools) on macOS 13+.

## License

[MIT](LICENSE)

<div align="center"><sub>

Keywords: Claude usage monitor · Claude Code menu bar · ccusage macOS app ·
Claude Pro / Max token tracker · session cost & burn rate · usage limit menu bar

</sub></div>
