#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# record-demo.sh — capture a REAL cc-switcher first-session recording.
#
# The onboarding page (onboarding.html) ships an illustrative animated terminal.
# This script helps you record your *own* genuine session as an asciinema cast
# and (optionally) convert it to an animated SVG/GIF to embed or share.
#
# Requirements:
#   - asciinema        (https://docs.asciinema.org/getting-started/)
#       macOS:  brew install asciinema
#       Linux:  pipx install asciinema   # or your distro package
#   - cc-switcher sourced in this shell, and at least one API key set
#       (try the FREE path: export OPENROUTER_API_KEY=... then use cc-nemotron)
#   - optional, for SVG/GIF export:
#       agg            (https://github.com/asciinema/agg)  -> GIF
#       svg-term-cli   (npm i -g svg-term-cli)             -> SVG
#
# Usage:
#   ./docs/record-demo.sh                 # records to docs/demo.cast
#   ./docs/record-demo.sh my-demo.cast    # custom output path
#   ./docs/record-demo.sh demo.cast --gif # also produce demo.gif (needs agg)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

OUT="${1:-docs/demo.cast}"
WANT_GIF=false
[[ "${2:-}" == "--gif" ]] && WANT_GIF=true

if ! command -v asciinema >/dev/null 2>&1; then
  echo "✖ asciinema not found. Install it first: https://docs.asciinema.org" >&2
  exit 1
fi

cat <<'TIPS'
────────────────────────────────────────────────────────────
Recording tips (a good demo is ~60–90s):
  1) cc-doctor                 # show your key check passes
  2) cc-nemotron               # launch a FREE model (zero cost)
  3) ask it one short thing    # e.g. "reverse a linked list in Python"
  4) /exit (or Ctrl-D)         # return to your normal shell
Type `exit` when done to stop the recording.
────────────────────────────────────────────────────────────
TIPS

read -r -p "Press Enter to start recording to '$OUT'… "

# --overwrite so re-runs replace cleanly; idle time capped so pauses don't drag.
asciinema rec --overwrite --idle-time-limit 2 "$OUT"

echo "✔ Saved cast: $OUT"
echo "  Play it:    asciinema play \"$OUT\""

if $WANT_GIF; then
  if command -v agg >/dev/null 2>&1; then
    GIF="${OUT%.cast}.gif"
    agg "$OUT" "$GIF"
    echo "✔ Saved GIF:  $GIF"
  else
    echo "ℹ agg not installed — skipping GIF. Install: https://github.com/asciinema/agg" >&2
  fi
fi

cat <<'NEXT'

To embed the result:
  • asciinema cast: upload with `asciinema upload demo.cast` and paste the share link.
  • SVG (crisp, embeddable):  cat demo.cast | svg-term --out docs/demo.svg --window
  • GIF: reference docs/demo.gif from a Markdown/HTML <img>.
NEXT
