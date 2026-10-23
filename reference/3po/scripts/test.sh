#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/test-env.sh
missioncontrol_test_init focused
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Infrastructure/Models/Models.swift MissionControl/Development/Previews/SampleServices.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift Tests/Development/FocusedChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
