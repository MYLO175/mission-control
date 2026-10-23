#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init memory-preparation
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Infrastructure/Storage/Cache.swift MissionControl/Infrastructure/Storage/LocalRecordRepository.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Memory/Learning/MemoryLearning.swift MissionControl/Assistant/Profile/PALearningQuestion.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Infrastructure/Models/Models.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Background/Briefing/Briefing.swift MissionControl/Memory/Records/PAMemoryStore.swift Tests/Memory/MemoryPreparationChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
