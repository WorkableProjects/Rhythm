#!/usr/bin/env bash
# Builds Rhythm (app + widget extension) for the iOS Simulator and runs the unit and UI tests.
# Usage: scripts/ci-ios.sh [--build-only]
set -euo pipefail
cd "$(dirname "$0")/.."

# Pick the newest available iPhone simulator.
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in runtime.rsplit("iOS-", 1)[-1].split("-") if x.isdigit())
    for d in devices:
        if d["name"].startswith("iPhone") and (best is None or version > best[0]):
            best = (version, d["udid"], d["name"])
print(best[1] if best else "")
')
if [[ -z "$DEVICE_ID" ]]; then
  echo "No iPhone simulator available" >&2
  exit 1
fi
echo "Using simulator $DEVICE_ID"

COMMON=(-project Rhythm.xcodeproj -scheme Rhythm -destination "id=$DEVICE_ID" CODE_SIGNING_ALLOWED=NO)

if [[ "${1:-}" == "--build-only" ]]; then
  xcodebuild "${COMMON[@]}" build
else
  xcodebuild "${COMMON[@]}" test
fi
