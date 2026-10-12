#!/bin/sh
# App Store screenshots (English, invented data) from the simulator. Always cleans up (no alarms on the Mac).
# usage: tools/store_shots.sh OUT_DIR [shot-name]      e.g. tools/store_shots.sh build/store/en-US/large today
# env:   SIM=<simulator udid> (a 6.9" iPhone Pro Max -> 1320x2868)   APP=<built Debug SleepHole.app>
#        WAIT=<seconds> base wait between launch and screenshot (default 20; some shots add more).
#        Run it on a QUIET Mac: on a busy one launches take minutes and shots come out empty – raise WAIT then.
# One function per shot below; add a line to ALL and a function to add a shot.
# Exit status: 0 when every shot is good, 1 when one stayed empty (a PNG under 200 kB is an empty screen: it is retried
# once with a doubled wait, then reported as FAILED).
OUT=${1:?usage: store_shots.sh OUT_DIR [shot]}; ONLY=$2
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=${SIM:-93342BA9-B9B4-499A-8048-22E44887073D}
APP=${APP:-build/DerivedData/Build/Products/Debug-iphonesimulator/SleepHole.app}
WAIT=${WAIT:-20}
BID=sk.zrebec.sleephole
CITY="Bratislava,48.1486,17.1077"
COMMON="-lang en -screenshot -mute"
ALL="town today night morning stats town-night today-evening sounds nap night-detail schedule"
FAILED=""
mkdir -p "$OUT"

# pick_tz HH:MM -> a time zone whose local time right now is closest to HH:MM (the app's clock is shifted with it)
pick_tz() {
  want=$(( 10#${1%:*} * 60 + 10#${1#*:} )); best=""; bd=9999
  for z in America/Los_Angeles America/Denver America/Chicago America/New_York America/Halifax America/St_Johns \
    America/Sao_Paulo Atlantic/Azores UTC Europe/London Europe/Berlin Europe/Athens Europe/Moscow Asia/Tehran Asia/Dubai \
    Asia/Kabul Asia/Karachi Asia/Kolkata Asia/Kathmandu Asia/Dhaka Asia/Yangon Asia/Bangkok Asia/Singapore Asia/Tokyo \
    Australia/Adelaide Australia/Sydney Australia/Lord_Howe Pacific/Noumea Pacific/Auckland Pacific/Chatham \
    Pacific/Honolulu America/Anchorage Pacific/Marquesas; do
    t=$(TZ=$z date +%H:%M); m=$(( 10#${t%:*} * 60 + 10#${t#*:} ))
    d=$(( m > want ? m - want : want - m )); [ $d -gt 720 ] && d=$((1440 - d))
    if [ $d -lt $bd ]; then bd=$d; best=$z; fi
  done
  echo $best
}

# take NAME WAIT LOOK TZ -- app args…   (one launch + screenshot; the theme is passed every time because it is stored)
take() {
  name=$1; wait=$2; look=$3; tz=$4; shift 5
  xcrun simctl ui $SIM appearance "$look"
  xcrun simctl terminate $SIM $BID 2>/dev/null
  if [ -n "$tz" ]; then SIMCTL_CHILD_TZ="$tz" xcrun simctl launch $SIM $BID $COMMON -theme "$look" "$@" >/dev/null
  else xcrun simctl launch $SIM $BID $COMMON -theme "$look" "$@" >/dev/null; fi
  sleep "$wait"
  # a shifted time zone: the status bar shows the app's clock (set right before the shot); otherwise the classic 9:41
  if [ -n "$tz" ]; then xcrun simctl status_bar $SIM override --time "$(TZ=$tz date +%-H:%M)"
  else xcrun simctl status_bar $SIM override --time "9:41"; fi
  sleep 3
  xcrun simctl io $SIM screenshot "$OUT/$name.png" >/dev/null 2>&1
  xcrun simctl terminate $SIM $BID 2>/dev/null
  # App Store Connect refuses an alpha channel
  python3 -c "import sys; from PIL import Image; f=sys.argv[1]; Image.open(f).convert('RGB').save(f)" "$OUT/$name.png"
}

# shoot NAME EXTRA_WAIT LOOK TZ -- args…   (take + size check + one retry with a doubled wait)
shoot() {
  name=$1; extra=$2; look=$3; tz=$4; shift 5
  take "$name" $((WAIT + extra)) "$look" "$tz" -- "$@"
  if [ "$(wc -c < "$OUT/$name.png")" -lt 200000 ]; then
    echo "retry $name (empty screen)"
    take "$name" $(( (WAIT + extra) * 2 )) "$look" "$tz" -- "$@"
  fi
  if [ "$(wc -c < "$OUT/$name.png")" -lt 200000 ]; then FAILED="$FAILED $name"; echo "FAILED $name"; fi
  echo "$OUT/$name.png $(sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT/$name.png" | awk '/pixel|hasAlpha/{printf $2" "}')"
}

shot_town()          { shoot 01-town 5 light "" -- -seedNights ${TOWN_N:-40} -openTab town -townFit -skyTime 14:10; }
shot_today()         { shoot 02-today 0 light "$(pick_tz 13:50)" -- -seedNights 60 -skyCity "$CITY" -skyTime 13:50 -weather clear -weatherTemp 15; }
# the night: the app's time zone is shifted so that the clock reads late evening; N minutes -> believable alarm time
shot_night()         { shoot 03-night 15 light "$(pick_tz 23:10)" -- -startTestNight -testNightMinutes ${NIGHT_MIN:-450} -previewProgress 0.6 -buddy asleep; }
shot_morning()       { shoot 04-morning 10 light "" -- -seedNights 60 -showResult; }
shot_stats()         { shoot 05-stats 0 light "" -- -seedNights 60 -openTab stats -sleepSim 18 -healthOn; }
shot_town_night()    { shoot 06-town-night 5 dark "" -- -seedNights ${TOWN_NIGHT_N:-100} -openTab town -townFit -skyTime 21:45; }
shot_today_evening() { shoot 07-today-evening 0 dark "$(pick_tz 22:27)" -- -seedNights 60 -skyCity "$CITY" -skyTime 22:27 -skyBody moon -skyArc 0.36 -skyMoon 0.6; }
shot_sounds()        { shoot 08-sounds 0 light "" -- -seedNights 60 -openTab settings -scrollTo sounds; }
shot_nap()           { shoot 09-nap 130 light "$(pick_tz 13:50)" -- -seedNights 60 -startNap; }
shot_night_detail()  { shoot 10-night-detail 20 light "" -- -seedNights 57 -openTab stats -sleepSim 18 -sleepSimName "Apple Watch" -healthOn -selectLastNight -scrollTo detail; }
shot_schedule()      { shoot 11-schedule 0 light "" -- -seedNights 60 -openTab settings; }

xcrun simctl boot $SIM 2>/dev/null
xcrun simctl bootstatus $SIM >/dev/null 2>&1
xcrun simctl status_bar $SIM override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install $SIM "$APP"
# warm-up: the first launch after a boot is slow and shoots a blank screen
xcrun simctl launch $SIM $BID $COMMON >/dev/null; sleep "$WAIT"; xcrun simctl terminate $SIM $BID 2>/dev/null
for s in $ALL; do
  if [ -z "$ONLY" ] || [ "$ONLY" = "$s" ]; then "shot_$(echo "$s" | tr - _)"; fi
done
xcrun simctl uninstall $SIM $BID
xcrun simctl status_bar $SIM clear
xcrun simctl shutdown $SIM
if [ -n "$FAILED" ]; then echo "FAILED shots:$FAILED"; exit 1; fi
