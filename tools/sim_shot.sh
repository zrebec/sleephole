#!/bin/sh
# Screenshot the app in the iPhone 16 Pro simulator, then ALWAYS clean up (no alarms ringing on the Mac).
# usage: tools/sim_shot.sh out.png wait_seconds [app args…]
OUT=$1; WAIT=$2; shift 2
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=${SIM:-CAB9AC31-E34E-404A-B7C5-B18CA7E1A63A}
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/SleepHole.app
xcrun simctl boot $SIM 2>/dev/null
xcrun simctl install $SIM $APP
xcrun simctl launch $SIM sk.zrebec.sleephole "$@" >/dev/null
sleep "$WAIT"
xcrun simctl io $SIM screenshot "$OUT" >/dev/null 2>&1
xcrun simctl terminate $SIM sk.zrebec.sleephole 2>/dev/null
xcrun simctl uninstall $SIM sk.zrebec.sleephole
xcrun simctl shutdown $SIM
echo "$OUT"
