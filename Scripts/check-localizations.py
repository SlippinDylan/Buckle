#!/usr/bin/env python3
"""Validate shipped languages, interpolation, and source references."""
import json
from pathlib import Path
import re
import plistlib
import base64
import warnings

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = {"en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es"}
FORMAT = re.compile(
    r"%%|%(?:(?P<position>[1-9]\d*)\$)?[-+#0']*"
    r"(?P<width>\*(?:[1-9]\d*\$)?|\d+)?"
    r"(?:\.(?P<precision>\*(?:[1-9]\d*\$)?|\d*))?"
    r"(?P<length>hh|ll|[hlqLztj])?(?P<conversion>[@diuoxXfFeEgGaAcCsSpn])"
)


def format_arguments(value):
    """Map printf argument positions to types, permitting translated reordering."""
    if "%#@" in value:
        raise ValueError("named substitutions require a project-specific checker")
    arguments = {}
    next_position = 1
    modes = set()

    def add(position, kind):
        nonlocal next_position
        modes.add("explicit" if position else "implicit")
        if len(modes) > 1:
            raise ValueError("format mixes positional and sequential arguments")
        index = int(position) if position else next_position
        if not position:
            next_position += 1
        if index in arguments and arguments[index] != kind:
            raise ValueError("one format argument has conflicting types")
        arguments[index] = kind

    for match in FORMAT.finditer(value):
        if match.group() == "%%":
            continue
        for field in ("width", "precision"):
            token = match.group(field)
            if token and token.startswith("*"):
                add(token[1:-1] if token.endswith("$") else None, "signed")
        conversion = match.group("conversion")
        if conversion == "n":
            raise ValueError("%n is not permitted in localized formats")
        length = match.group("length") or ""
        if conversion in "di":
            kind = "signed"
        elif conversion in "uoxX":
            kind = "unsigned"
        elif conversion in "fFeEgGaA":
            # Float arguments are promoted to double; only L selects long double.
            kind = "long-double" if length == "L" else "double"
            length = ""
        else:
            kind = conversion
        add(match.group("position"), length + kind)
    return arguments


def validate_formats(english, translated, context):
    # A space after % can be ordinary prose or a printf flag; do not guess.
    if any(match.group() != "%%"
           for value in (english, translated)
           for match in re.finditer(r"%%|%(?:[1-9]\d*\$)?[-+#0']* ", value)):
        warnings.warn(
            f"{context}: '% ' is ambiguous; format comparison skipped, manual review required.",
            stacklevel=2,
        )
        return
    if format_arguments(english) != format_arguments(translated):
        raise ValueError(f"Mismatched format arguments: {context}")


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


def main():
    resources = ROOT / "App/Resources"
    assert {p.stem for p in resources.glob("*.lproj")} == LANGUAGES
    for filename in ("Localizable.strings", "InfoPlist.strings"):
        english = read_strings(resources / "en.lproj" / filename)
        for language in LANGUAGES:
            localized = read_strings(resources / f"{language}.lproj" / filename)
            assert localized.keys() == english.keys(), f"Mismatched keys: {language}/{filename}"
            for key in english:
                validate_formats(english[key], localized[key], f"{language}/{key}")

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
    assert info["SUEnableAutomaticChecks"] is False
    assert info["SURequireSignedFeed"] is True
    assert info["SUVerifyUpdateBeforeExtraction"] is True
    assert len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32
    assert "APP_UPDATER_ENABLED = NO" in (ROOT / "Config/Debug.xcconfig").read_text()
    extension = plistlib.loads((ROOT / "FinderExtension/Info.plist").read_bytes())
    assert extension["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.FinderSync"
    print("Eight locales, placeholders, source references, and Finder extension metadata verified.")


if __name__ == "__main__":
    main()
