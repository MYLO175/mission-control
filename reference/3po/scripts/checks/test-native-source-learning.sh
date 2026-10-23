#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init native-source-learning
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Memory/Learning/MemoryLearning.swift MissionControl/Assistant/Profile/PALearningQuestion.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Background/Briefing/Briefing.swift MissionControl/Memory/Records/PAMemoryStore.swift MissionControl/Infrastructure/Models/Models.swift MissionControl/Assistant/Context/PAOrientation.swift MissionControl/Sources/Mail/MailService.swift MissionControl/Sources/Mail/MailBatching.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Review/Inbox/ReviewPolicy.swift MissionControl/Sources/Email/EmailSummary.swift MissionControl/Sources/Email/EmailResolution.swift MissionControl/Memory/Learning/NativeSourceLearning.swift MissionControl/Sources/Native/NativeSourceAdapters.swift Tests/Memory/NativeSourceLearningChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
