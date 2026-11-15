#!/usr/bin/env python3
"""Package a verified Buckle bundle without signing it or replacing an installer."""

import argparse
import json
import os
import plistlib
import subprocess
import sys
import tempfile
from importlib.metadata import version
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_manifest():
    # Reuse the repository's manifest validation and generated-version contract.
    subprocess.run(["node", str(ROOT / ".github/scripts/sync-version.mjs"), "--check"], cwd=ROOT, check=True)
    return json.loads((ROOT / "Config/Release/manifest.json").read_text())


def output_path(output, manifest, release):
    build = ROOT / "build"
    if build.is_symlink():
        raise ValueError("Build directory must not redirect output outside this repository")
    if output is None:
        suffix = "" if release else "-" + str(manifest["build"]) + "-test"
        output = build / ("Buckle-" + manifest["version"] + suffix + ".dmg")
    else:
        output = Path(output)
        if not output.is_absolute():
            output = ROOT / output
    if ".." in output.parts:
        raise ValueError("DMG output must not contain parent-directory traversal")
    try:
        relative = output.relative_to(build)
    except ValueError as error:
        raise ValueError("DMG output must be inside this repository's build directory") from error
    if not relative.parts or output.suffix != ".dmg":
        raise ValueError("Output must be a .dmg file inside build")
    for path in (output, *output.parents):
        if path == ROOT:
            break
        if path.is_symlink():
            raise ValueError("DMG output must not use symbolic links: " + str(path))
    if output.exists():
        raise ValueError("Refusing to overwrite existing DMG: " + str(output))
    return output


def package(app, output=None, release=False):
    manifest = read_manifest()
    if not manifest["packagingEnabled"]:
        raise ValueError("Packaging is disabled in Config/Release/manifest.json")
    app = Path(app).resolve()
    if not app.is_dir() or app.name != "Buckle.app":
        raise ValueError("Input must be the Buckle.app bundle")
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    expected = {
        "CFBundleIdentifier": "studio.slippindylan.Buckle",
        "CFBundleShortVersionString": manifest["version"],
        "CFBundleVersion": str(manifest["build"]),
    }
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError("App identity or version does not match the release manifest")
    flag = info.get("AppUpdaterEnabled")
    enabled = flag is True or flag == "YES"
    disabled = flag is False or flag == "NO"
    if (release and not enabled) or (not release and not disabled):
        raise ValueError("AppUpdaterEnabled must be YES/true for releases and NO/false for test packages")
    output = output_path(output, manifest, release)
    # Keep distribution identity, architecture, nested signature and resource checks in one place.
    subprocess.run(["bash", str(ROOT / "Scripts/verify-bundle.sh"), "--distribution", str(app)], check=True)
    if sys.platform != "darwin" or sys.version_info < (3, 10):
        raise ValueError("DMG packaging requires macOS and Python 3.10+")
    if version("dmgbuild") != "1.6.7":
        raise ValueError("Install dmgbuild==1.6.7 in the packaging environment")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Build privately, then publish with a no-replace operation, including concurrent invocations.
    with tempfile.TemporaryDirectory(prefix="dmg-", dir=output.parent) as staging:
        image = Path(staging) / output.name
        subprocess.run([
            sys.executable, "-m", "dmgbuild", "-s", str(ROOT / "Config/DMG/settings.py"),
            "-D", "app=" + str(app), "Buckle", str(image),
        ], check=True)
        os.link(image, output)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--release", action="store_true", help="Require the signed-feed updater to be enabled")
    args = parser.parse_args()
    try:
        print(package(args.app, args.output, args.release))
    except (ValueError, OSError, ImportError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + "\n")
