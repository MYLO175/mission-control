#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/test-env.sh
missioncontrol_test_init second-brain
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Infrastructure/Models/Models.swift MissionControl/Infrastructure/Storage/Cache.swift "${missioncontrol_storage_sources[@]}" MissionControl/Memory/Records/PAMemory.swift MissionControl/Memory/Records/MemoryInspection.swift MissionControl/Memory/Notebook/LifeNotebook.swift MissionControl/Memory/Notebook/LifeOrganisation.swift MissionControl/Memory/Learning/MemoryLearning.swift MissionControl/Assistant/Profile/PALearningQuestion.swift MissionControl/Memory/Records/MemoryDependencies.swift MissionControl/Review/Inbox/ReviewPolicyModels.swift MissionControl/Background/Briefing/Briefing.swift MissionControl/Projects/LifeWorkspace.swift MissionControl/Projects/LifeProjectPlacement.swift MissionControl/Projects/LifeWorkspaceQuery.swift MissionControl/Projects/LifeWorkspaceStore.swift MissionControl/Memory/Notebook/LifeCanonicalNotebook.swift MissionControl/Memory/Records/PAMemoryStore.swift Tests/Integration/SecondBrainChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
