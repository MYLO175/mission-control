#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ -n "${MISSIONCONTROL_TRIAL_APP:-}" ]]; then
  candidate="$MISSIONCONTROL_TRIAL_APP"
else
  export MISSIONCONTROL_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/3po-review-trial.XXXXXX")"
  scripts/build.sh
  candidate="$MISSIONCONTROL_BUILD_ROOT/derived-data/Build/Products/Debug/3PO.app"
fi
codesign --verify --deep --strict "$candidate"
python3 - "$candidate" <<'PYTHON'
from pathlib import Path
import json,plistlib,subprocess,sys
bundle=Path(sys.argv[1])
with (bundle/'Contents/Info.plist').open('rb') as stream:info=plistlib.load(stream)
if info.get('CFBundleIdentifier') != 'com.mylomichael.missioncontrol' or info.get('3POEvaluationProtocol') != 1:
    raise SystemExit('This candidate has no signed evaluation protocol; it was not launched.')
result=subprocess.run([str(bundle/'Contents/MacOS/3PO'),'--evaluation-handshake'],capture_output=True,text=True,timeout=30,check=True)
handshake=json.loads(result.stdout)
if handshake.get('debug') is not True or handshake.get('bundleID') != 'com.mylomichael.missioncontrol':
    raise SystemExit('This trial needs a DEBUG 3PO candidate; it was not launched.')
PYTHON
open -n "$candidate" --args --preview-review-conversation
