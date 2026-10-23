#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init learning-budget
# An integration owner can verify this bounded fixture against another current
# source checkout without importing/editing that checkout's Swift files.
source_root="${MISSIONCONTROL_TEST_SOURCE_ROOT:-$PWD}"
fixture="$PWD/Tests/Memory/LearningBudgetChecks.swift"
cd "$source_root"
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Storage/Cache.swift MissionControl/Infrastructure/Storage/LocalRecordRepository.swift MissionControl/Infrastructure/Models/Models.swift MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Memory/Learning/MemoryLearning.swift MissionControl/Assistant/Profile/PALearningQuestion.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Background/Briefing/Briefing.swift MissionControl/Memory/Learning/BackgroundLearningCoordinator.swift MissionControl/Memory/Learning/LearningBudget.swift "$fixture" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
