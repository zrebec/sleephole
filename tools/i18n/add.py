#!/usr/bin/env python3
"""Adds / updates translations in SleepHole/Resources/Localizable.xcstrings.

usage: python3 tools/i18n/add.py translations.json
translations.json: {"English key": {"sk": "Slovak text", "cs": "Czech text"}, …}
  (a bare string is Slovak only – old callers; every new text needs sk AND cs, see CzechTests.everyTextHasCzech)
  plural keys: {"%lld nights": {"en": {"one": "%lld night", "other": "%lld nights"},
                                "sk": {"one": "%lld noc", "few": "%lld noci", "many": "%lld noci", "other": "%lld nocí"},
                                "cs": {"one": "%lld noc", "few": "%lld noci", "many": "%lld noci", "other": "%lld nocí"}}}
The file is written in the catalog's own layout (insertion order, indent 2, no trailing newline).
Then build the app and run tools/i18n/keys.py (0 missing / 0 without sk)."""
import json, os, sys

CATALOG = os.path.join(os.path.dirname(__file__), "..", "..", "SleepHole/Resources/Localizable.xcstrings")


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def main():
    catalog = json.load(open(CATALOG))
    strings = catalog["strings"]
    new = json.load(open(sys.argv[1]))
    for key, value in new.items():
        if isinstance(value, dict) and all(isinstance(v, str) for v in value.values()):
            loc = {"en": unit(key)}
            loc.update({lang: unit(v) for lang, v in value.items()})
            strings[key] = {"localizations": loc}
        elif isinstance(value, dict):
            strings[key] = {"localizations": {
                lang: {"variations": {"plural": {c: unit(v) for c, v in forms.items()}}}
                for lang, forms in value.items()}}
        else:
            strings[key] = {"localizations": {"en": unit(key), "sk": unit(value)}}
    with open(CATALOG, "w") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", ": "))
    print(f"{len(new)} keys added/updated, {len(strings)} in the catalog")


if __name__ == "__main__":
    main()
