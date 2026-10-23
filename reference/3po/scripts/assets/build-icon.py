#!/usr/bin/env python3
"""Prepare the supplied artwork for Xcode app-icon compilation and ICNS fallback."""
from pathlib import Path
import json
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = root / "MissionControl/Resources/AppIcon.png"
target = source.with_suffix(".icns")
chunks = []
with tempfile.TemporaryDirectory(prefix="mission-control-icon-") as directory:
    for kind, size in [("icp4", 16), ("icp5", 32), ("icp6", 64),
                       ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                       ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]:
        output = Path(directory) / f"{kind}.png"
        subprocess.run(["/usr/bin/sips", "-z", str(size), str(size), str(source),
                        "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
        png = output.read_bytes()
        chunks.append(kind.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
target.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)

# Let Xcode compile the app icon and emit its system metadata. Retain the
# standalone ICNS for older bundle readers and an explicit Dock fallback.
catalog = root / "MissionControl/Resources/Assets.xcassets"
app_icon = catalog / "AppIcon.appiconset"
app_icon.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        filename = f"icon_{points}x{points}@{scale}x.png"
        size = points * scale
        subprocess.run(["/usr/bin/sips", "-z", str(size), str(size), str(source),
                        "--out", str(app_icon / filename)], check=True, stdout=subprocess.DEVNULL)
        images.append({"idiom": "mac", "size": f"{points}x{points}",
                       "scale": f"{scale}x", "filename": filename})
(app_icon / "Contents.json").write_text(json.dumps({"images": images,
    "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
