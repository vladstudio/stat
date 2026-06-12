#!/bin/bash
set -e; cd "$(dirname "$0")"
source ./app.sh
source ../app-scripts/build-kit.sh
build_app
