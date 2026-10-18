# App Review notes – the source text (build 9)

The text below goes into App Store Connect → the version → App Review Information → **Notes** when build 9 (or a
later build) is submitted. Two changes against the notes saved with build 7 (read from App Store Connect 2026-10-18):
(1) the section "A WHOLE NIGHT IN ABOUT 15 MINUTES" – since build 8 a bedtime / wake change made in Settings once
tonight's building can start (from bedtime − 3 h) applies from tomorrow, so the reviewer sets the times in the
first-run guide, where they apply at once (plan §12, 2026-10-16, point 6); (2) STRICT MODE – the warning lasts 15 seconds
(was 10; build 9i, owner 2026-10-18). The rest is the build-7 text unchanged.
Changing the field in App Store Connect needs the owner's yes; keep this file and the field identical.

---

SleepHole is a sleep-habit app. At bedtime the user starts a "night" and a building starts to grow; the phone rests during the night; confirming the wake-up in the morning finishes the building. Night by night a small town grows. There is no account and no sign-in.

A WHOLE NIGHT IN ABOUT 15 MINUTES
1. On a fresh install the first-run guide opens. On its page "Your schedule" set Bedtime to about 3 minutes from now and Wake-up to about 15 minutes from now – times set in the guide apply at once. Finish the guide. (In Settings > Schedule a change made within 3 hours of the current bedtime applies only from the next day, so please use the guide; to see the guide again, delete and reinstall the app.)
2. Today tab: tap "Go to sleep" (active from 10 minutes before bedtime until 5 minutes after it). A short first-night checklist appears once.
3. The first minutes are setup time (until 5 minutes after bedtime by default; Settings > Setup time offers 5, 10 or 15 minutes). Then lock the phone; SleepHole must stay the frontmost app, the screen can be off.
4. At the wake-up time the alarm rings. Shake the phone, or type the code shown in Settings > Morning confirmation (the night screen accepts both from 30 minutes before the wake-up time, so in this short test it accepts them straight away). The building is finished and stands on the Town tab.
To see the reminder: after the setup time, leave the app - a notification asks you to come back and shows the seconds left. "Cancel night" ends a test at any time.

BACKGROUND AUDIO (UIBackgroundModes: audio)
During a night the app plays the sleep sound the user chose (noise, rain, sound stories; brown noise all night by default) and rings its own alarm at the wake-up time while the phone is locked and the ringer is off. If the user picks "Silence" or the sleep timer ends, the audio session stays active without sound so that the alarm still rings and the night can be followed. Audio ends when the night ends. The app never records and does not use the microphone.

LOCK DETECTION (changed in build 7 after ITMS-90699 on build 6)
The rule of a night is that the phone rests. The app observes only its own state, with documented UIApplication notifications only: background / foreground, and protectedDataWillBecomeUnavailable / protectedDataDidBecomeAvailable to tell locking the phone from leaving the app. It no longer observes any system lock or display notification. It never blocks or limits other apps and does not use Screen Time APIs. On a device without a passcode with Face ID or Touch ID, leaving the app is not counted (Settings says so).

STRICT MODE (Settings, off by default)
By default, using the phone at night (the device recognised the user and stays in use outside the app for 8 seconds) brings one calm notification. With Strict mode on, a short warning rings as an AlarmKit alarm with a countdown; the app ends it when the phone is locked again, when the user returns to the app, or after 15 seconds. If the phone stays in use, tonight's building is lost.

ALARMKIT (iOS 26 and later)
A backup system alarm at the wake-up time, in case iOS closed the app during the night, and the Strict mode warning above.

EARLY START
"Go to sleep early today" appears from 3 hours before bedtime and asks for a confirmation first.

APPLE HEALTH
Optional and off by default (Settings > "Show when you fell asleep"). The app reads sleep analysis only, to show when the user fell asleep. It writes nothing to Health, and Health data is never stored in iCloud.

WEATHER
The coordinates of the city the user picked in Settings (not the device location) are sent to Apple WeatherKit, or to MET Norway when WeatherKit does not answer. The city search uses Apple Maps.

ICLOUD
With "Sync through iCloud" on (Settings), the user's nights, coins and settings are kept as files in the user's own iCloud Drive container, so the town is the same on all their devices. Nothing else leaves the device: no analytics, no ads, no tracking.
