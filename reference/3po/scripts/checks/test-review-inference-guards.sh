#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init review-inference-guards
xcrun swiftc -parse-as-library -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Models/Models.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Review/Inbox/ReviewInferenceGuard.swift Tests/Review/ReviewInferenceGuardChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
