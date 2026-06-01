#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../app-scripts/release-kit.sh
release_app "Stat" --info app/Stat/Info.plist
