#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init ai-activity
xcrun swiftc -parse-as-library -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" \
  MissionControl/Infrastructure/Activity/AIActivity.swift Tests/Infrastructure/Activity/AIActivityChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
