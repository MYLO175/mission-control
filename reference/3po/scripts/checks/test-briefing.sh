#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init briefing
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Models/Models.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Review/Inbox/ReviewPolicy.swift MissionControl/Sources/Email/EmailSummary.swift MissionControl/Sources/Email/EmailResolution.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Background/Briefing/Briefing.swift Tests/Background/BriefingChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
