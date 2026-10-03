#!/bin/sh
# Screenshot the app in the iPhone 16 Pro simulator, then ALWAYS clean up (no alarms ringing on the Mac).
# usage: tools/sim_shot.sh out.png wait_seconds [app args…]   e.g. -seedNights 12 -openTab stats -lang sk
#        APPEARANCE=dark tools/sim_shot.sh …   (light by default; add -skyTime 21:45 to pin the sky)
OUT=$1; WAIT=$2; shift 2
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=${SIM:-CAB9AC31-E34E-404A-B7C5-B18CA7E1A63A}
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/SleepHole.app
xcrun simctl boot $SIM 2>/dev/null
xcrun simctl ui $SIM appearance ${APPEARANCE:-light}
xcrun simctl install $SIM $APP
# STORE=<folder with default.store*> (pulled from the iPhone, docs/device-logs/…): the owner's real nights.
# Use it with -screenshot (no permission alert, no guide) instead of -seedNights.
if [ -n "$STORE" ]; then
  C=$(xcrun simctl get_app_container $SIM sk.zrebec.sleephole data)
  mkdir -p "$C/Library/Application Support"
  cp "$STORE"/default.store* "$C/Library/Application Support/"
fi
xcrun simctl launch $SIM sk.zrebec.sleephole "$@" >/dev/null
sleep "$WAIT"
xcrun simctl io $SIM screenshot "$OUT" >/dev/null 2>&1
xcrun simctl terminate $SIM sk.zrebec.sleephole 2>/dev/null
xcrun simctl uninstall $SIM sk.zrebec.sleephole
xcrun simctl shutdown $SIM
echo "$OUT"
