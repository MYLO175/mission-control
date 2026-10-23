#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init stream
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Usage/AIUsage.swift MissionControl/Assistant/Provider/ChatGPTStream.swift MissionControl/Assistant/Provider/ChatGPTRecovery.swift Tests/Assistant/ChatGPTStreamChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
