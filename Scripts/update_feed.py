"""Validate release identity against the signed feed before replacing it."""

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


@dataclass(frozen=True)
class Release:
    version: tuple[int, int, int]
    url: str
    signature: str
    length: int


def read_releases(path: Path) -> dict[int, Release]:
    releases = {}
    for item in ET.parse(path).findall("./channel/item"):
        build = item.findtext(SPARKLE + "version", "")
        version = item.findtext(SPARKLE + "shortVersionString", "")
        enclosure = item.find("enclosure")
        if not re.fullmatch(r"[1-9][0-9]*", build) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
            raise ValueError("Expected a positive build and a three-part release version.")
        if enclosure is None or not enclosure.get("url") or not enclosure.get(SPARKLE + "edSignature"):
            raise ValueError("Expected a signed update enclosure.")
        length = int(enclosure.get("length", "0"))
        if length <= 0 or int(build) in releases:
            raise ValueError("Invalid archive size or duplicate build in update feed.")
        releases[int(build)] = Release(
            tuple(map(int, version.split("."))), enclosure.get("url"), enclosure.get(SPARKLE + "edSignature"), length
        )
    if not releases:
        raise ValueError("Update feed must contain at least one release.")
    return releases


def validate_transition(previous: dict[int, Release], candidate: dict[int, Release]) -> None:
    if not previous:
        return
    if max(candidate) < max(previous):
        raise ValueError("Update feed cannot drop its latest published build.")
    for build, release in candidate.items():
        if build in previous:
            if release != previous[build]:
                raise ValueError("A published build cannot be reused for a different version, URL or archive.")
        elif build <= max(previous) or release.version <= max(item.version for item in previous.values()):
            raise ValueError("Both version and build must increase beyond the published feed.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--previous", type=Path)
    args = parser.parse_args()
    previous = read_releases(args.previous) if args.previous else {}
    validate_transition(previous, read_releases(args.candidate))
    print("Published release identities and increasing versions verified.")


if __name__ == "__main__":
    main()
