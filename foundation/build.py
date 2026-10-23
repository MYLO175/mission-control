#!/usr/bin/env python3
"""Build a standalone native app with Xcode's Swift compiler; no package downloads."""
import argparse, json, os, platform, plistlib, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parent

def configuration():
    value = json.loads((ROOT / "app.json").read_text())
    name, bundle = value.get("name", ""), value.get("bundleID", "")
    if not isinstance(name, str) or not name.strip() or len(name) > 60 or any(ord(c) < 32 or c in '/\\:' for c in name):
        raise ValueError("Choose an app name of 1–60 characters without path separators")
    if not isinstance(bundle, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", bundle):
        raise ValueError("Choose a valid reverse-DNS bundle ID with at least three parts")
    if value.get("theme") not in ("sage", "ocean", "graphite", "rose", "gold"):
        raise ValueError("Choose sage, ocean, graphite, rose or gold")
    return value

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--render-preview", type=Path, help="Render the fictional foundation to a PNG without personal data")
    args = parser.parse_args()
    config = configuration()
    if platform.system() != "Darwin": raise SystemExit("Building needs macOS 26+ and full Xcode")
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    app = out / (config["name"] + ".app"); macos = app / "Contents/MacOS"; macos.mkdir(parents=True, exist_ok=True)
    generated = out / "AppIdentity.generated.swift"
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    generated.write_text("import Foundation\nenum AppIdentity {\n" +
        " static let name = " + quote(config["name"]) + "\n" +
        " static let bundleID = " + quote(config["bundleID"]) + "\n" +
        " static let theme = " + quote(config["theme"]) + "\n" +
        " static let keychainService = bundleID + \".chatgpt\"\n" +
        " static var dataDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID, isDirectory: true) }\n}\n")
    env = os.environ.copy(); env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env, text=True).strip()
    arch = platform.machine()
    sources = sorted(str(p) for p in (ROOT / "Sources").rglob("*.swift"))
    command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-Onone", "-sdk", sdk,
               "-target", arch + "-apple-macosx26.0", "-module-name", "MissionControlFoundation",
               "-module-cache-path", str(out / "module-cache"), *sources, str(generated), "-o", str(macos / "MissionControl")]
    subprocess.run(command, check=True, env=env)
    info = {"CFBundleExecutable":"MissionControl", "CFBundleIdentifier":config["bundleID"],
            "CFBundleName":config["name"], "CFBundleDisplayName":config["name"], "CFBundlePackageType":"APPL",
            "CFBundleShortVersionString":"0.1.0", "CFBundleVersion":"1", "LSMinimumSystemVersion":"26.0",
            "NSHighResolutionCapable":True, "NSPrincipalClass":"NSApplication"}
    with (app / "Contents/Info.plist").open("wb") as handle: plistlib.dump(info, handle)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    print(app, flush=True)
    if args.render_preview:
        args.render_preview.resolve().parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(macos / "MissionControl"), "--render-preview", str(args.render_preview.resolve())], check=True, timeout=30)
    elif args.run:
        subprocess.run(["open", "-n", str(app), "--args", *(["--preview"] if args.preview else [])], check=True)
if __name__ == "__main__": main()
