#!/usr/bin/env python3
"""Independent reference values for SleepCore's sun / moon maths (phase SKY), computed with PyEphem.

    python3 -m venv /tmp/astro && /tmp/astro/bin/pip install ephem
    /tmp/astro/bin/python tools/astro/reference.py > /tmp/astro_reference.json

Geometric values (no atmospheric refraction: pressure 0), topocentric for the moon. Sunrise / sunset use the
standard horizon of -0.833 degrees for the sun's CENTRE (`use_center=True` - without it PyEphem subtracts the
sun's radius a second time), moonrise / moonset the moon's centre at +0.125 degrees. All times are UTC.

The tables in SleepCore/Tests/SleepCoreTests/AstroTests.swift were pasted from the first run of this script, which
still lacked `use_center=True`: their rise / set times are 1-2 minutes off (late rises, early sets), well inside
the tests' tolerances. SleepCore agrees with the corrected values to a few seconds.
"""
import json
import math

import ephem

PLACES = {
    "bratislava": (48.1486, 17.1077),
    "sydney": (-33.8688, 151.2093),
    "quito": (-0.1807, -78.4678),
    "tromso": (69.6492, 18.9553),
}
INSTANTS = ["2026/10/3 10:00", "2026/10/3 16:30", "2026/10/3 19:00", "2026/6/21 11:00", "2026/12/21 11:00",
            "2026/3/20 06:00", "2027/1/15 22:00"]
DAYS = ["2026/10/3", "2026/6/21", "2026/12/21", "2026/3/20"]
PHASES = ["2026/10/3 12:00", "2026/10/10 12:00", "2026/10/18 12:00", "2026/10/26 04:00", "2026/8/12 17:45",
          "2026/3/3 11:30", "2026/11/2 12:00"]


def observer(lat, lon, when, horizon="0"):
    o = ephem.Observer()
    o.lat, o.lon, o.elevation, o.pressure = str(lat), str(lon), 0, 0
    o.horizon = horizon
    o.date = when
    return o


def iso(d):
    return ephem.Date(d).datetime().strftime("%Y-%m-%dT%H:%M:%SZ")


def deg(a):
    return round(math.degrees(a), 2)


out = {"position": [], "sun_day": [], "moon_phase": [], "moon_day": []}
for name, (lat, lon) in PLACES.items():
    if name == "tromso":
        continue
    for t in INSTANTS:
        o = observer(lat, lon, t)
        s, m = ephem.Sun(o), ephem.Moon(o)
        out["position"].append({"place": name, "utc": iso(o.date), "sun_alt": deg(s.alt), "sun_az": deg(s.az),
                                "moon_alt": deg(m.alt), "moon_az": deg(m.az)})
for name, (lat, lon) in PLACES.items():
    for d in DAYS:
        if name == "tromso" and d not in ("2026/6/21", "2026/12/21"):
            continue
        # start the search at the local midnight (approximately: UTC midnight shifted by the longitude)
        start = ephem.Date(ephem.Date(d) - lon / 360.0)
        o = observer(lat, lon, start, "-0:50")
        row = {"place": name, "from_utc": iso(start)}
        try:
            row["sunrise"] = iso(o.next_rising(ephem.Sun(), use_center=True))
            row["sunset"] = iso(o.next_setting(ephem.Sun(), use_center=True))
        except (ephem.AlwaysUpError, ephem.NeverUpError) as e:
            row["sunrise"] = row["sunset"] = None
            row["why"] = type(e).__name__
        out["sun_day"].append(row)
for t in PHASES:
    m = ephem.Moon(t)
    # waxing = the next full moon comes before the next new moon
    waxing = ephem.next_full_moon(t) < ephem.next_new_moon(t)
    out["moon_phase"].append({"utc": iso(ephem.Date(t)), "illuminated": round(m.phase / 100, 3), "waxing": waxing})
lat, lon = PLACES["bratislava"]
for d in ["2026/10/3 12:00", "2026/10/20 12:00", "2026/10/27 12:00"]:
    o = observer(lat, lon, d, "0:07.5")
    out["moon_day"].append({"place": "bratislava", "from_utc": iso(o.date),
                            "next_moonrise": iso(o.next_rising(ephem.Moon(), use_center=True)),
                            "next_moonset": iso(o.next_setting(ephem.Moon(), use_center=True))})
print(json.dumps(out, indent=1))
