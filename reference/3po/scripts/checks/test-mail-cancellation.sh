#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init mail-cancellation
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Models/Models.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift Tests/Sources/Mail/MailCancellationChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
