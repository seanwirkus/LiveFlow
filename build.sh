#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/LiveFlow.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos14" \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/LiveFlow"

# Stable identity so TCC permissions (Accessibility, Mic) survive rebuilds.
IDENTITY="${LIVEFLOW_SIGN_ID:-Apple Development: Sean Wirkus (X4KQY878L7)}"
codesign --force -s "$IDENTITY" "$APP"
echo "Built $APP"
