#!/usr/bin/env python3
"""Copy only the small foundation into a new independent personal app folder."""
import argparse, json, re, shutil, uuid
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def create(name, destination, bundle_id=None):
    destination = Path(destination).expanduser().resolve()
    name = name.strip()
    if not name or len(name) > 60 or any(ord(c) < 32 or c in '/\\:' for c in name):
        raise ValueError("Choose a name of 1–60 characters without path separators")
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "personal"
    bundle_id = bundle_id or "io.missioncontrol." + slug + ".a" + uuid.uuid4().hex[:12]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", bundle_id):
        raise ValueError("Choose a valid reverse-DNS bundle ID")
    if ROOT / "foundation" in destination.parents:
        raise ValueError("Choose a destination outside the foundation source directory")
    if destination.exists(): raise FileExistsError("Destination already exists; existing apps are never overwritten")
    shutil.copytree(ROOT / "foundation", destination, ignore=shutil.ignore_patterns(".build", "__pycache__", "*.pyc"))
    config = {"schemaVersion":1, "name":name, "bundleID":bundle_id, "theme":"sage"}
    (destination / "app.json").write_text(json.dumps(config, indent=2) + "\n")
    (destination / "ORIGIN.json").write_text(json.dumps({"starter":"https://github.com/MYLO175/mission-control", "foundationVersion":"0.1.0"}, indent=2) + "\n")
    print("Created " + str(destination))
    print("Run: python3 " + repr(str(destination / "build.py")) + " --run --preview")
    return destination

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--bundle-id")
    args = parser.parse_args()
    try: create(args.name, args.destination, args.bundle_id)
    except (ValueError, FileExistsError) as error: parser.exit(2, str(error) + "\n")
if __name__ == "__main__": main()
