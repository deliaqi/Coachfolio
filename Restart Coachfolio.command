#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
DERIVED_DATA_DIR="$PROJECT_DIR/DerivedData/Coachfolio-Launcher"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/Coachfolio.app"

cd "$PROJECT_DIR"
/usr/bin/xcodebuild -quiet \
  -project CoachJournal.xcodeproj \
  -scheme "Coach Journal" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

# Quit a running copy before opening the freshly built app.
/usr/bin/osascript -e 'tell application id "com.coachjournal.mac" to quit' >/dev/null 2>&1 || true
/bin/sleep 1
/usr/bin/killall -q Coachfolio 2>/dev/null || true
/usr/bin/open -n "$APP_PATH"
