#!/bin/sh
# Runs the app unit tests (SleepHoleTests) on the iPhone 16 Pro simulator with coverage, prints the
# per-file coverage of the app target, then shuts the simulator down. Usage: tools/test_app.sh
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=${SIM:-CAB9AC31-E34E-404A-B7C5-B18CA7E1A63A}
rm -rf build/tests.xcresult
xcodegen generate >/dev/null
xcodebuild test -project SleepHole.xcodeproj -scheme SleepHole -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath build/DerivedData -enableCodeCoverage YES -resultBundlePath build/tests.xcresult 2>&1 \
  | grep -E "error:|✘|Test run|TEST (SUCCEEDED|FAILED)"
xcrun xccov view --report --only-targets build/tests.xcresult 2>/dev/null
xcrun xccov view --report build/tests.xcresult 2>/dev/null | grep -E "^\s+[A-Za-z]+\.swift" | sort -k2 -t'%' 
xcrun simctl shutdown "$SIM" 2>/dev/null
exit 0
