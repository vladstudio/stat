#!/bin/bash
set -e; cd "$(dirname "$0")"
source ./app.sh
source ../app-scripts/build-kit.sh
source ../app-scripts/release-kit.sh
release_app
