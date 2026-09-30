#!/usr/bin/env python3
"""Verify exact KSU module.prop lookup and runtime payload before delivery."""
import hashlib
from pathlib import Path, PurePosixPath
import sys
import zipfile

REQUIRED = (
    "module.prop", "customize.sh", "service.sh", "boot-completed.sh", "action.sh",
    "uninstall.sh", "webroot/index.html", "scripts/lifecycle/supervisor.sh",
    "scripts/lib/dns-filters.sh", "rules/anti-ad-easylist.txt",
    "rules/anti-ad-easylist.txt.sha256", "licenses/anti-AD-MIT.txt",
    "bin/arm64/AdGuardHome", "bin/armv7/AdGuardHome", "SHA256SUMS",
)


def validate(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), "duplicate ZIP entries"
        assert archive.testzip() is None, "corrupt ZIP payload"
        for name in names:
            parts = PurePosixPath(name).parts
            assert not name.startswith(("/", "./")) and ".." not in parts, "unsafe or non-canonical ZIP path: " + name
        for name in REQUIRED:
            assert name in names, "missing installable root entry: " + name
        props = dict(line.split("=", 1) for line in archive.read("module.prop").decode().splitlines() if "=" in line)
        assert props["id"] == "AdGuardHome"
        for line in archive.read("SHA256SUMS").decode().splitlines():
            digest, name = line.split(None, 1)
            assert hashlib.sha256(archive.read(name.strip().removeprefix("./"))).hexdigest() == digest, name
        print("KSU archive contract passed:", Path(path).name, props["version"], len(names), "entries")


if __name__ == "__main__":
    for path in sys.argv[1:]:
        validate(path)
