#!/usr/bin/env python3
# Writes latest.json for a release: what the app's update check reads
# (lib/core/update/update_info.dart).
#
#   python3 tool/ci/make_latest_json.py --dir <folder with the release files> \
#       --version 1.12.0 --build 142 --base-url https://github.com/<owner>/<repo> \
#       --tag v1.12.0 [--out latest.json]
#
# Old fields (kept): version, build, date, notes_url.
# New in 1.12: "platforms" - for each system the FIXED-NAME file of this
# release, its size in bytes and its SHA-256, which the app checks before it
# uses a download:
#   windows   -> ClipForge-windows.zip
#   macos     -> ClipForge-macos.zip
#   android   -> ClipForge-android.apk
#   android32 -> ClipForge-android-old-32bit-phones.apk
# The address is the file inside THIS release (releases/download/<tag>/...),
# not "latest": the size and fingerprint belong to exactly this file.
# Standard library only.
import argparse
import datetime
import hashlib
import json
import os
import sys

FILES = {
    "windows": "ClipForge-windows.zip",
    "macos": "ClipForge-macos.zip",
    "android": "ClipForge-android.apk",
    "android32": "ClipForge-android-old-32bit-phones.apk",
}


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True, type=int)
    ap.add_argument("--base-url", required=True, help="https://github.com/<owner>/<repo>")
    ap.add_argument("--tag", required=True)
    ap.add_argument("--date", help="UTC, ISO 8601 (default: now)")
    ap.add_argument("--out", help="default: <dir>/latest.json")
    ap.add_argument("--allow-missing", action="store_true",
                    help="leave out a system whose file is not there instead of failing")
    args = ap.parse_args()

    base = args.base_url.rstrip("/")
    platforms = {}
    for key, name in FILES.items():
        path = os.path.join(args.dir, name)
        if not os.path.isfile(path):
            if args.allow_missing:
                continue
            print("error: %s is missing from %s" % (name, args.dir), file=sys.stderr)
            return 1
        platforms[key] = {
            "url": "%s/releases/download/%s/%s" % (base, args.tag, name),
            "size": os.path.getsize(path),
            "sha256": sha256_of(path),
        }
    latest = {
        "version": args.version,
        "build": args.build,
        "date": args.date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "notes_url": "%s/releases/tag/%s" % (base, args.tag),
        "platforms": platforms,
    }
    out = args.out or os.path.join(args.dir, "latest.json")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(latest, f, separators=(",", ":"))
        f.write("\n")
    print(json.dumps(latest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
