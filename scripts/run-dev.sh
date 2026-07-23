#!/usr/bin/env bash
# Quick build & run for iteration. The dock icon stays hidden (.accessory);
# look for the gauge icon in the menu bar. Ctrl-C to stop.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
exec .build/debug/ClaudeMenubar
