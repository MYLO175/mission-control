#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init inference-deadline
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Assistant/Provider/InferenceDeadline.swift Tests/Assistant/InferenceDeadlineChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
