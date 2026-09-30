#!/usr/bin/env python3
"""Adds / updates translations in SleepHole/Resources/Localizable.xcstrings.

usage: python3 tools/i18n/add.py translations.json
translations.json: {"English key": "Slovak text", …}
  plural keys: {"%lld nights": {"en": {"one": "%lld night", "other": "%lld nights"},
                                "sk": {"one": "%lld noc", "few": "%lld noci", "many": "%lld noci", "other": "%lld nocí"}}}
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
        if isinstance(value, dict):
            strings[key] = {"localizations": {
                lang: {"variations": {"plural": {c: unit(v) for c, v in forms.items()}}}
                for lang, forms in value.items()}}
        else:
            strings[key] = {"localizations": {"en": unit(key), "sk": unit(value)}}
    with open(CATALOG, "w") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"{len(new)} keys added/updated, {len(strings)} in the catalog")


if __name__ == "__main__":
    main()
