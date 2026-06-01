#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../app-scripts/build-kit.sh
build_app "Stat" \
  --info app/Stat/Info.plist \
  --resources "icons/cpu.png icons/gpu.png icons/temp.png icons/download-k.png icons/download-m.png icons/upload-k.png icons/upload-m.png icons/day-sun.png icons/day-mon.png icons/day-tue.png icons/day-wed.png icons/day-thu.png icons/day-fri.png icons/day-sat.png fonts/Oswald-Light.ttf"
