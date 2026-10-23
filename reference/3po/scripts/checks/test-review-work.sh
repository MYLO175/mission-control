#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init review-work
xcrun swiftc -parse-as-library -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Review/Actions/ReviewWork.swift Tests/Review/ReviewWorkChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
