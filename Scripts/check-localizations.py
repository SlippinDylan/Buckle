#!/usr/bin/env python3
"""Validate shipped languages, interpolation, and source references."""
import json
from pathlib import Path
import re
import plistlib
import base64

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = {"en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es"}
resources = ROOT / "App/Resources"
assert {p.stem for p in resources.glob("*.lproj")} == LANGUAGES


def read_strings(path):
    result = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");', line)
        assert match, f"Invalid strings entry: {path}"
        key, value = (json.loads(part) for part in match.groups())
        assert key not in result, f"Duplicate key {key}: {path}"
        assert value.strip(), f"Empty translation {key}: {path}"
        result[key] = value
    return result


for filename in ("Localizable.strings", "InfoPlist.strings"):
    english = read_strings(resources / "en.lproj" / filename)
    for language in LANGUAGES:
        localized = read_strings(resources / f"{language}.lproj" / filename)
        assert localized.keys() == english.keys(), f"Mismatched keys: {language}/{filename}"
        for key in english:
            assert localized[key].count("%@") == english[key].count("%@"), f"Mismatched placeholder: {language}/{key}"

keys = read_strings(resources / "en.lproj/Localizable.strings")
referenced = set()
for source in [*(ROOT / "App").rglob("*.swift"), *(ROOT / "FinderExtension").rglob("*.swift")]:
    referenced.update(re.findall(r'"(mouse\.step\.[\w.]+)"', source.read_text()))
    referenced.update(re.findall(r'\blocalized(?:Format)?\(\s*"([\w.]+)"', source.read_text()))
assert referenced == keys.keys(), f"Missing/unused localization keys: {referenced ^ keys.keys()}"
info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
assert info["LSUIElement"] is True
assert "NSServices" not in info
assert info["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["buckle"]
assert info["SURequireSignedFeed"] is True
assert info["SUVerifyUpdateBeforeExtraction"] is True
assert len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32
assert "BUCKLE_UPDATER_ENABLED = NO" in (ROOT / "Config/Debug.xcconfig").read_text()
extension = plistlib.loads((ROOT / "FinderExtension/Info.plist").read_bytes())
assert extension["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.FinderSync"
print("Eight locales, placeholders, source references, and Finder extension metadata verified.")
