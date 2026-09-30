#!/usr/bin/env python3
"""Lists the localization keys the compiler extracted from `L("…")` calls (build/DerivedData *.stringsdata)
and compares them with SleepHole/Resources/Localizable.xcstrings.

usage: python3 tools/i18n/keys.py            → keys missing in the catalog / catalog keys no longer used
       python3 tools/i18n/keys.py --all      → every extracted key
Build the app first (tools/test_app.sh or xcodebuild … build) so the .stringsdata files exist.
       python3 tools/i18n/keys.py --prune    → also delete the unused keys from the catalog
Exit code 1 when a key is missing or a key lacks its Slovak translation."""
import glob, json, os, sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
CATALOG = os.path.join(ROOT, "SleepHole/Resources/Localizable.xcstrings")


def extracted():
    keys = {}
    pattern = os.path.join(ROOT, "build/DerivedData/Build/Intermediates.noindex/SleepHole.build/*/SleepHole.build/"
                                 "Objects-normal/*/*.stringsdata")
    # simulator and device builds leave separate outputs – use only the newest one per source file
    newest = {}
    for f in glob.glob(pattern):
        name = os.path.basename(f)
        if name not in newest or os.path.getmtime(f) > os.path.getmtime(newest[name]):
            newest[name] = f
    for f in newest.values():
        data = json.load(open(f))
        if not os.path.exists(data["source"]):
            continue                                   # a deleted Swift file
        for e in data.get("tables", {}).get("Localizable", []):
            keys.setdefault(e["key"], os.path.basename(data["source"]))
    return keys


def main():
    keys = extracted()
    if not keys:
        sys.exit("no .stringsdata found – build the app first")
    if "--all" in sys.argv:
        for k, f in sorted(keys.items(), key=lambda kv: (kv[1], kv[0])):
            print(f"{f}\t{k}")
        return
    strings = json.load(open(CATALOG))["strings"]
    missing = [k for k in keys if k not in strings]
    untranslated = [k for k in keys if k in strings and "sk" not in strings[k].get("localizations", {})]
    unused = [k for k in strings if k not in keys]
    for k in missing:
        print(f"MISSING  {keys[k]}: {k}")
    for k in untranslated:
        print(f"NO SK    {keys[k]}: {k}")
    for k in unused:
        print(f"UNUSED   {k}")
    if "--prune" in sys.argv and unused:
        catalog = json.load(open(CATALOG))
        for k in unused:
            del catalog["strings"][k]
        with open(CATALOG, "w") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"pruned {len(unused)} unused keys")
    print(f"{len(keys)} keys, {len(missing)} missing, {len(untranslated)} without sk, {len(unused)} unused")
    sys.exit(1 if missing or untranslated else 0)


if __name__ == "__main__":
    main()
