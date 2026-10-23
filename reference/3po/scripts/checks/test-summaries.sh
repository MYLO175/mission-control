#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init summaries
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Models/Models.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Review/Inbox/ReviewPolicyStore.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Review/Inbox/ReviewPolicy.swift MissionControl/Sources/Email/EmailSummary.swift MissionControl/Sources/Email/EmailResolution.swift Tests/Review/ReviewPolicyChecks.swift Tests/Sources/Email/EmailSummaryChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
