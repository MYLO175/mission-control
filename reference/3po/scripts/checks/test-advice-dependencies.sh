#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init advice-dependencies
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Infrastructure/Models/Models.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Review/Inbox/ReviewPolicy.swift MissionControl/Sources/Email/EmailSummary.swift MissionControl/Sources/Email/EmailResolution.swift MissionControl/Review/Inbox/Proactive.swift MissionControl/Sources/WhatsApp/WhatsAppModels.swift MissionControl/Memory/Learning/SourceContextLearning.swift MissionControl/Memory/Learning/MemoryLearning.swift MissionControl/Assistant/Profile/PALearningQuestion.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Background/Briefing/Briefing.swift MissionControl/Assistant/Conversation/Conversations.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Memory/Records/PAMemoryStore.swift Tests/Integration/AdviceDependenciesChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
