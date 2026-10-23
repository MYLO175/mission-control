#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init whatsapp
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Sources/WhatsApp/WhatsAppModels.swift Tests/Sources/WhatsApp/WhatsAppChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
# Checks never install, patch or connect a dependency. Reuse only a prepared copy.
missioncontrol_test_node
bridge_dependencies="${MISSIONCONTROL_WHATSAPP_DEPENDENCIES:-$PWD/WhatsAppBridge/node_modules}"
if [[ ! -d "$bridge_dependencies" ]]; then
  print -u2 -- "Required prepared WhatsApp dependencies unavailable: $bridge_dependencies. Checks never download or patch them."
  exit 1
fi
bridge_dependencies="$(cd "$bridge_dependencies" && pwd -P)"
bridge_fixture="$MISSIONCONTROL_TEST_WORK_DIR/WhatsAppBridge"
mkdir -p "$bridge_fixture"
cp WhatsAppBridge/*.mjs "$bridge_fixture/"
ln -s "$bridge_dependencies" "$bridge_fixture/node_modules"
# policy.test verifies the pinned patched source before the offline fixture runs.
"$MISSIONCONTROL_NODE" --test "$bridge_fixture"/*.test.mjs
"$MISSIONCONTROL_NODE" --check "$bridge_fixture/reader.mjs"
