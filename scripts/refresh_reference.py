#!/usr/bin/env python3
"""Review or refresh only the allowlisted, committed 3PO reference snapshot."""
import argparse, datetime, hashlib, json, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ALLOWED = ("MissionControl/", "Tests/", "scripts/", "WhatsAppBridge/", "docs/guides/", "docs/architecture/", "docs/development/", "docs/assets/", "MissionControl.xcodeproj/")
ROOT_FILES = {"README.md", "docs/README.md", ".gitignore"}
def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args])
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Local 3PO source checkout (read only)")
    parser.add_argument("--ref", default="HEAD", help="Explicit commit/ref to review")
    parser.add_argument("--apply", action="store_true", help="Replace the reference after reviewing a dry run")
    args = parser.parse_args()
    commit = git(args.source, "rev-parse", "--verify", args.ref + "^{commit}").decode().strip()
    names = git(args.source, "ls-tree", "-r", "--name-only", "-z", commit).decode().split("\0")
    files = {}
    modes = {}
    for entry in git(args.source, "ls-tree", "-r", "-z", commit).decode().split("\0"):
        if entry:
            metadata, name = entry.split("\t", 1)
            modes[name] = metadata.split()[0]
    for name in names:
        if name and (name in ROOT_FILES or name.startswith(ALLOWED)):
            path = Path(name)
            if path.is_absolute() or ".." in path.parts:
                raise SystemExit("Invalid reference path")
            if modes[name] not in ("100644", "100755"):
                raise SystemExit("Unsupported reference file mode: " + name)
            files[name] = git(args.source, "show", commit + ":" + name)
    if not files:
        raise SystemExit("No allowlisted source files found")
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
    manifest_path = ROOT / "reference/manifest.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"files": {}}
    old = previous["files"]
    changed = sorted(name for name in set(old) | set(hashes) if old.get(name) != hashes.get(name))
    affected = []
    catalogue = ROOT / "catalog.json"
    if catalogue.exists():
        for feature in json.loads(catalogue.read_text())["features"]:
            if any(any(name.startswith(prefix) for prefix in feature.get("sourcePrefixes", [])) for name in changed):
                affected.append(feature["id"])
    print(json.dumps({"sourceCommit": commit, "files": len(files), "changedFiles": len(changed),
                      "affectedRecipes": affected, "foundationReviewRequired": any(name.startswith("MissionControl/Assistant/Provider/") or name == "MissionControl/Infrastructure/Usage/AIUsage.swift" for name in changed), "mode": "apply" if args.apply else "review",
                      "changedPaths": changed}, indent=2))
    if not args.apply:
        return
    target = ROOT / "reference/3po"
    target.mkdir(parents=True, exist_ok=True)
    for name in old:
        if name not in hashes:
            path = target / name
            if path.exists(): path.unlink()
    for name, data in files.items():
        path = target / name
        if path.is_symlink(): raise SystemExit("Refusing reference symlink: " + name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o755 if modes[name] == "100755" else 0o644)
    manifest = {"schemaVersion": 1, "sourceRepository": "https://github.com/MYLO175/3PO",
                "sourceCommit": commit, "importedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "scope": "Committed allowlisted application, tests, build helpers and published documentation; no Git history or local data",
                "files": hashes, "fileModes": {name: modes[name] for name in files}}
    manifest_path.parent.mkdir(exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
if __name__ == "__main__": main()
