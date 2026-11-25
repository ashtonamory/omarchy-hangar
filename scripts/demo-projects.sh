#!/usr/bin/env bash
# Build fake demo projects under ~/Code for the README screenshot and GIF.
set -euo pipefail
root="$HOME/Code"
[[ -e $root ]] && { echo "$root already exists, refusing"; exit 1; }
mkdir -p "$root"
now=$(date +%s)

# project <name> <branch> <changes> <readme title> <readme line> <hours-ago:subject>...
project() {
  local name=$1 branch=$2 changes=$3 title=$4 line=$5; shift 5
  local dir="$root/$name"
  mkdir -p "$dir"; cd "$dir"
  git init -q -b main
  printf '# %s\n\n%s\n\n## Getting started\n\nRun `make dev` and open http://localhost:3000.\n' "$title" "$line" > README.md
  local entries=("$@") i
  # oldest first
  for ((i=${#entries[@]}-1; i>=0; i--)); do
    local hours=${entries[i]%%:*} subject=${entries[i]#*:}
    local ts=$((now - hours*3600))
    echo "$subject" >> CHANGELOG
    git add -A
    GIT_AUTHOR_DATE="@$ts" GIT_COMMITTER_DATE="@$ts" \
      git -c user.name="Demo" -c user.email="demo@example.invalid" commit -q -m "$subject"
    if ((i == ${#entries[@]}-1)) && [[ $branch != main ]]; then git checkout -q -b "$branch"; fi
  done
  for ((i=1; i<=changes; i++)); do echo "wip $i" > "wip-$i.txt"; done
  local newest=${entries[0]%%:*}
  touch -d "@$((now - newest*3600))" "$dir"
}

project aurora-ui feat/command-palette 3 "Aurora UI" "Terminal-flavoured components for web apps: tables, palettes and toasts that follow your theme." \
  "1:Command palette: fuzzy match on titles and keywords" "3:Palette opens on Ctrl+K" "20:Toast queue drops duplicates" "50:Dark and light tokens from one palette" "120:Table: sticky header and keyboard rows" "200:Initial component set"
project tidepool main 0 "Tidepool" "A fast log tailer that groups repeated lines and highlights what changed." \
  "5:Group repeats within a 2s window" "28:Colour levels by severity" "70:Follow rotated files" "160:Read from stdin" "300:First release"
project pixel-forge feat/onion-skin 1 "Pixel Forge" "A tiny sprite editor with layers, palettes and onion skinning for animation frames." \
  "9:Onion skin shows the previous two frames" "30:Frame strip with drag to reorder" "75:Palette import from .hex files" "190:Layers and blend modes" "400:Canvas, pencil and fill"
project ledgerline fix/csv-import 1 "Ledgerline" "Plain-text personal finance: import bank CSVs, tag spending, see where the month went." \
  "26:Handle quoted commas in bank CSVs" "48:Monthly summary by tag" "100:Rules file for auto-tagging" "260:Import and list transactions"
project orbit-api main 0 "Orbit API" "A small REST service for tracking satellites passing over a location." \
  "52:Cache TLE data for six hours" "80:Pass predictions endpoint" "150:Health check and metrics" "330:Project scaffold"
project weather-station main 2 "Weather Station" "ESP32 sensor firmware and a dashboard that charts temperature, humidity and pressure." \
  "75:Dashboard: 24h pressure trend" "110:Deep sleep between readings" "240:BME280 driver" "500:Blink test"
project nightshift chore/deps 0 "Nightshift" "Warms your screen after sunset and cools it at dawn, with per-monitor schedules." \
  "130:Update dependencies" "170:Per-monitor schedules" "380:Sunset times from latitude" "600:Toggle from the command line"
project trailmix main 0 "Trailmix" "Recipe box for camping trips: scale portions, build a shopping list, print a card." \
  "220:Scale portions by group size" "350:Shopping list merges duplicates" "700:Recipe cards"
project lumen-docs docs/getting-started 0 "Lumen Docs" "Documentation site for the Lumen static site generator." \
  "400:Getting started guide" "520:Search index" "900:Site skeleton"

mkdir -p "$root/sketches"; touch -d "@$((now - 1100*3600))" "$root/sketches"
touch -d "@$((now - 1*3600))" "$root"
echo "made $(ls "$root" | wc -l) projects in $root"
